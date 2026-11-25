"""Native desktop installers, preserving the already verified app payload."""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import tarfile
import tempfile
import urllib.error
import urllib.request
from windows_runtime import prepare_windows_runtime, verify_crt
from verify_mobile import verify_apple_bundle


def command(*args, **kwargs):
    return subprocess.check_output([str(a) for a in args], text=True, **kwargs).strip()


def checksum(path):
    with path.open('rb') as f:
        value = hashlib.file_digest(f, 'sha256').hexdigest()
    path.with_name(path.name + '.sha256').write_bytes(f'{value}  {path.name}\n'.encode())


def validate_version(version):
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?', version):
        raise ValueError('Expected a semantic release version')
    return version


def deb_version(version, build_number=None):
    value = validate_version(version).replace('-', '~', 1)
    if build_number is not None:
        if not re.fullmatch(r'[1-9][0-9]*', str(build_number)):
            raise ValueError('Invalid Debian build revision')
        value += '-' + str(build_number)
    return value


def verify_payload(bundle, platform, arch, installed=False):
    if arch not in ('x64', 'arm64'):
        raise ValueError(arch)
    notice_root = bundle
    if platform == 'macos' and not (bundle / 'SOURCE.txt').is_file():
        notice_root = bundle / 'Modu.app/Contents/Resources/Distribution'
    for notice in ('LICENSE', 'NOTICE', 'SOURCE.txt'):
        if not (notice_root / notice).is_file():
            raise ValueError(f'Missing source/license notice: {notice}')
    if platform == 'macos':
        app = bundle / 'Modu.app'
        with (app / 'Contents/Info.plist').open('rb') as f:
            executable = plistlib.load(f)['CFBundleExecutable']
        expected = 'x86_64' if arch == 'x64' else 'arm64'
        if expected not in command('lipo', '-archs', app / 'Contents/MacOS' / executable).split():
            raise ValueError('Mislabeled macOS architecture')
        command('codesign', '--verify', '--deep', '--strict', app)
        return
    required = ['modu', 'lib/libflutter_linux_gtk.so', 'lib/libtokenizers_ffi.so'] if platform == 'linux' else [
        'modu.exe', 'flutter_windows.dll', 'onnxruntime.dll', 'tokenizers_ffi.dll']
    for name in required:
        if not (bundle / name).is_file():
            raise ValueError(f'Missing native payload: {name}')
    for path in bundle.rglob('*'):
        if not path.is_file():
            continue
        if installed and platform == 'windows' and path == bundle / 'unins000.exe':
            # Inno's uninstall engine is x86; application binaries remain native.
            continue
        with path.open('rb') as f:
            header = f.read(4096)
        if platform == 'linux' and header[:4] == b'\x7fELF':
            expected = 62 if arch == 'x64' else 183
            if header[4] != 2 or struct.unpack_from('<H', header, 18)[0] != expected:
                raise ValueError(f'Mislabeled ELF: {path}')
        elif platform == 'windows' and path.suffix.lower() in ('.exe', '.dll'):
            if len(header) < 64 or header[:2] != b'MZ':
                raise ValueError(f'Malformed PE payload: {path}')
            offset = struct.unpack_from('<I', header, 0x3c)[0]
            expected = 0x8664 if arch == 'x64' else 0xaa64
            if (offset + 6 > len(header) or header[offset:offset+4] != b'PE\0\0'
                    or struct.unpack_from('<H', header, offset+4)[0] != expected):
                raise ValueError(f'Mislabeled PE payload: {path}')


def prepare_macos_image(bundle, stage):
    # Keep the install window focused on drag-to-install. Legal/source records
    # remain accessible inside the application, not alongside its icon.
    stage.mkdir(parents=True)
    app = stage / 'Modu.app'
    command('ditto', bundle / 'Modu.app', app)
    notices = app / 'Contents/Resources/Distribution'
    notices.mkdir(parents=True, exist_ok=True)
    for name in ('LICENSE', 'NOTICE', 'SOURCE.txt', 'UPSTREAM.md', 'PRIVACY.md',
                 'INSTALL.md', 'INSTALLER-SOURCE.txt'):
        if (bundle / name).is_file():
            shutil.copy2(bundle / name, notices / name)
    if (bundle / 'LICENSES').is_dir():
        shutil.copytree(bundle / 'LICENSES', notices / 'LICENSES', dirs_exist_ok=True)
    # Adding bundled notices changes the resource seal: sign only the copy.
    command('codesign', '--force', '--deep', '--sign', '-',
            '--preserve-metadata=entitlements', app)
    command('codesign', '--verify', '--deep', '--strict', app)
    (stage / 'Applications').symlink_to('/Applications', target_is_directory=True)


def build_dmg(bundle, arch, version, output, work):
    stage = work / 'image'
    prepare_macos_image(bundle, stage)
    result = output / f'Modu-{version}-macos-{arch}.dmg'
    command('hdiutil', 'create', '-volname', f'Modu {version} {arch}', '-srcfolder', stage,
            '-format', 'UDZO', '-fs', 'HFS+', result)
    command('hdiutil', 'verify', result)
    mount = work / 'mounted'
    mount.mkdir()
    command('hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, result)
    try:
        verify_payload(mount, 'macos', arch)
        if os.readlink(mount / 'Applications') != '/Applications':
            raise ValueError('Missing Applications drag target')
        if {p.name for p in mount.iterdir() if not p.name.startswith('.')} != {'Modu.app', 'Applications'}:
            raise ValueError('macOS install window must contain only the app and Applications shortcut')
        if (mount / 'Modu.app/Contents/Resources/Distribution/SOURCE.txt').read_bytes() != (bundle / 'SOURCE.txt').read_bytes():
            raise ValueError('Source provenance changed')
    finally:
        command('hdiutil', 'detach', mount)
    return result


def windows_script(bundle, arch, version, output):
    validate_version(version)
    arch_rule = {'x64': 'x64os', 'arm64': 'arm64'}[arch]
    book_associations = '\n'.join(
        f'Root: HKCU; Subkey: "Software\\Classes\\.{ext}\\OpenWithProgids"; '
        'ValueType: none; ValueName: "Modu.Book"; Flags: uninsdeletevalue'
        for ext in ('epub', 'mobi', 'azw3', 'fb2', 'txt', 'pdf', 'md', 'markdown', 'umd'))
    # Inno's installer engine architecture is separate from the native payload.
    # The OS restriction prevents installing x64 app files on an ARM64 system.
    return f'''[Setup]
AppId=ModuReader
AppName=Modu Reader
AppVersion={version}
AppPublisher=Modu contributors
AppPublisherURL=https://github.com/sobranie2406/modureader
AppSupportURL=https://github.com/sobranie2406/modureader/issues
DefaultDirName={{localappdata}}\\Programs\\Modu
DefaultGroupName=Modu
PrivilegesRequired=lowest
ArchitecturesAllowed={arch_rule}
ArchitecturesInstallIn64BitMode={arch_rule}
MinVersion=10.0.17763
OutputDir={output}
OutputBaseFilename=Modu-{version}-windows-{arch}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={{app}}\\modu.exe
LicenseFile={bundle}\\LICENSE
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
ChangesAssociations=yes
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Files]
Source: "{bundle}\\*"; DestDir: "{{app}}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{{group}}\\Modu"; Filename: "{{app}}\\modu.exe"; WorkingDir: "{{app}}"
Name: "{{userdesktop}}\\Modu"; Filename: "{{app}}\\modu.exe"; WorkingDir: "{{app}}"; Tasks: desktopicon
[Registry]
{book_associations}
Root: HKCU; Subkey: "Software\\Classes\\Modu.Book"; ValueType: string; ValueData: "Modu Book"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\Modu.Book\\shell\\open\\command"; ValueType: string; ValueData: """{{app}}\\modu.exe"" ""%1"""
Root: HKCU; Subkey: "Software\\Classes\\modu"; ValueType: string; ValueData: "URL:Modu Reading Link"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\\Classes\\modu"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\\Classes\\modu\\shell\\open\\command"; ValueType: string; ValueData: """{{app}}\\modu.exe"" ""%1"""
[Run]
Filename: "{{app}}\\modu.exe"; Description: "Launch Modu (requires Microsoft WebView2 Runtime)"; Flags: nowait postinstall skipifsilent
[Code]
function InitializeSetup(): Boolean;
var
  I: Integer;
begin
  Result := True;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/S') = 0 then
    begin
      // Do not leave unattended callers waiting for the interactive wizard.
      Log('Unsupported /S: use /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- instead.');
      Result := False;
      Exit;
    end;
end;
'''


def build_windows(bundle, arch, version, output, work):
    # Work on a separate payload so the input and its provenance remain intact.
    prepared = work / 'windows-payload'
    shutil.copytree(bundle, prepared, symlinks=True)
    prepare_windows_runtime(prepared, arch)
    verify_payload(prepared, 'windows', arch)
    verify_crt(prepared, arch)
    bundle = prepared
    compiler = shutil.which('iscc')
    if not compiler:
        compiler = str(Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)'))
                       / 'Inno Setup 6/ISCC.exe')
    script = work / 'modu.iss'
    script.write_text(windows_script(bundle, arch, version, output), encoding='utf-8-sig')
    subprocess.run([compiler, str(script)], check=True)
    result = output / f'Modu-{version}-windows-{arch}-setup.exe'
    if not result.is_file() or result.stat().st_size < 1000000:
        raise ValueError('Installer was not generated')
    return result


# Native libraries were built against Debian 13. Depending on the matching WPE
# packages also brings in their transitive media/text/graphics dependencies.
DEB_DEPENDS = ('libc6 (>= 2.41), libstdc++6 (>= 14), libgcc-s1, libgtk-3-0t64, '
               'libsecret-1-0, libjsoncpp26, libwpewebkit-2.0-1 (>= 2.48.3), '
               'libwpebackend-fdo-1.0-1, libwpe-1.0-1, libepoxy0, libsqlite3-0, '
               'libasound2t64, libpulse0, gstreamer1.0-plugins-base, gstreamer1.0-plugins-good')


LINUX_ONNX_LIBRARY = 'libonnxruntime.so.1.22.0'
LINUX_ONNX_LIBRARY_SHA256 = {
    'x64': '3da6146e14e7b8aaec625dde11d6114c7457c87a5f93d744897da8781e35c673',
    'arm64': '0afd69a0ae38c5099fd0e8604dda398ac43dee67cd9c6394b5142b19e82528de',
}
LINUX_ONNX_ARCHIVES = {
    'x64': ('x64', '8344d55f93d5bc5021ce342db50f62079daf39aaafb5d311a451846228be49b3'),
    'arm64': ('aarch64', 'bb76395092d150b52c7092dc6b8f2fe4d80f0f3bf0416d2f269193e347e24702'),
}


def verify_linux_onnx_library(library, arch):
    if library.is_symlink() or not library.is_file():
        raise ValueError('Expected a real ONNX Runtime shared library')
    with library.open('rb') as source:
        if hashlib.file_digest(source, 'sha256').hexdigest() != LINUX_ONNX_LIBRARY_SHA256[arch]:
            raise ValueError('ONNX Runtime library checksum mismatch')
    with library.open('rb') as source:
        header = source.read(24)
    if (len(header) != 24 or header[:6] != b'\x7fELF\x02\x01' or
            struct.unpack_from('<H', header, 18)[0] != {'x64': 62, 'arm64': 183}[arch]):
        raise ValueError('Mislabeled ONNX Runtime library architecture')


def prepare_linux_runtime(app, arch, work, *, relocate=True):
    library = app / 'lib' / LINUX_ONNX_LIBRARY
    provenance = app / 'LINUX-RUNTIME.txt'
    if library.exists() or library.is_symlink():
        # New builds already install the hash-pinned NuGet payload during CMake.
        verify_linux_onnx_library(library, arch)
        if not provenance.is_file():
            provenance.write_text(
                'ONNX Runtime 1.22.0: verified existing runtime payload\n'
                f'Library SHA-256: {LINUX_ONNX_LIBRARY_SHA256[arch]}\n', encoding='utf-8')
    else:
        if provenance.is_file() and 'Package SHA-256:' in provenance.read_text(encoding='utf-8'):
            raise ValueError('Verified ONNX Runtime build payload is missing')
        # Historical plugin bundles omitted the real target of their symlink.
        _restore_linux_runtime(library, arch, work, provenance)
    for name, target in [('libonnxruntime.so.1', library.name),
                         ('libonnxruntime.so', 'libonnxruntime.so.1')]:
        link = library.parent / name
        if link.is_symlink():
            link.unlink()
        elif link.exists():
            verify_linux_onnx_library(link, arch)
            link.unlink()
        link.symlink_to(target)
    if relocate:
        # Plugins carry absolute CI build paths. Keep their library search private.
        for plugin in (app / 'lib').glob('*.so'):
            if not plugin.is_symlink() and plugin.name != 'libapp.so':
                command('patchelf', '--set-rpath', '$ORIGIN', plugin)
        command('patchelf', '--set-rpath', '$ORIGIN/lib', app / 'modu')
        with provenance.open('a', encoding='utf-8') as record:
            record.write('ELF RPATH metadata made relocatable; application source is recorded in SOURCE.txt.\n')


def _restore_linux_runtime(library, arch, work, provenance):
    upstream_arch, digest = LINUX_ONNX_ARCHIVES[arch]
    basename = f'onnxruntime-linux-{upstream_arch}-1.22.0'
    urls = [f'https://github.com/microsoft/onnxruntime/releases/download/v1.22.0/{basename}.tgz',
            f'https://dl.photoprism.app/onnx/runtime/v1.22.0/{basename}.tgz']
    archive = work / 'onnxruntime.tgz'
    for index, url in enumerate(urls):
        try:
            with urllib.request.urlopen(url, timeout=120) as response, archive.open('wb') as target:
                shutil.copyfileobj(response, target)
            break
        except (urllib.error.URLError, TimeoutError):
            if index == len(urls) - 1:
                raise
    with archive.open('rb') as source:
        if hashlib.file_digest(source, 'sha256').hexdigest() != digest:
            raise ValueError('Official ONNX Runtime archive checksum mismatch')
    with tarfile.open(archive) as source:
        member = source.getmember(f'{basename}/lib/{library.name}')
        if not member.isfile():
            raise ValueError('Expected a real ONNX Runtime shared library')
        with source.extractfile(member) as data, library.open('wb') as target:
            shutil.copyfileobj(data, target)
    verify_linux_onnx_library(library, arch)
    provenance.write_text(
        f'ONNX Runtime 1.22.0: {url}\nSHA-256: {digest}\n'
        'MIT license and ThirdPartyNotices: LICENSES/ONNXRuntime-1.22.0-*.txt\n'
        'Missing runtime payload restored; ELF RPATH metadata made relocatable.\n'
        'This packaging step adjusts runtime libraries; application source is recorded in SOURCE.txt.\n', encoding='utf-8')


def write_linux_desktop_entry(path, executable):
    path.write_text(
        '[Desktop Entry]\nType=Application\nName=Modu Reader\nName[zh_CN]=默读\n'
        f'Comment=Read ebooks with AI tools\nExec={executable} %U\nIcon=modureader\n'
        'MimeType=x-scheme-handler/modu;application/pdf;application/epub+zip;'
        'application/x-mobipocket-ebook;application/vnd.amazon.ebook;'
        'application/x-fictionbook+xml;text/plain;text/markdown;application/x-umd;\n'
        'Terminal=false\nCategories=Office;Viewer;\nStartupWMClass=com.modu.reader\n', encoding='utf-8')
    command('desktop-file-validate', path)


def build_deb(bundle, arch, version, output, work, build_number=None):
    root = work / 'deb'
    app = root / 'opt/modureader'
    shutil.copytree(bundle, app, symlinks=True)
    prepare_linux_runtime(app, arch, work)
    (app / 'modu').chmod(0o755)
    control = root / 'DEBIAN'
    control.mkdir()
    architecture = {'x64': 'amd64', 'arm64': 'arm64'}[arch]
    size = sum(p.stat().st_size for p in app.rglob('*') if p.is_file()) // 1024
    (control / 'control').write_text(
        f'Package: modureader\nVersion: {deb_version(version, build_number)}\nArchitecture: {architecture}\n'
        'Maintainer: Modu contributors <162990443+sobranie2406@users.noreply.github.com>\n'
        'Section: text\nPriority: optional\n'
        f'Installed-Size: {size}\nDepends: {DEB_DEPENDS}\n'
        'Homepage: https://github.com/sobranie2406/modureader\n'
        'Description: Modu AI ebook reader\n'
        ' Independent GPL-3.0-or-later derivative of Anx Reader and ReadAny.\n'
        ' Reader, notes, AI tools, vector search, translation and WebDAV sync.\n', encoding='utf-8')
    desktop = root / 'usr/share/applications'
    desktop.mkdir(parents=True)
    write_linux_desktop_entry(desktop / 'modureader.desktop', 'modureader')
    mime = root / 'usr/share/mime/packages'
    mime.mkdir(parents=True)
    (mime / 'modureader.xml').write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">'
        + ''.join(f'<mime-type type="{kind}"><glob pattern="*.{ext}"/></mime-type>'
                  for ext, kind in {
                      'epub': 'application/epub+zip', 'pdf': 'application/pdf',
                      'mobi': 'application/x-mobipocket-ebook', 'azw3': 'application/vnd.amazon.ebook',
                      'fb2': 'application/x-fictionbook+xml', 'txt': 'text/plain',
                      'md': 'text/markdown', 'markdown': 'text/markdown', 'umd': 'application/x-umd',
                  }.items()) + '</mime-info>\n', encoding='utf-8')
    icons = root / 'usr/share/pixmaps'
    icons.mkdir(parents=True)
    shutil.copy2(app / 'data/flutter_assets/assets/icon/modu-app-icon.png', icons / 'modureader.png')
    binaries = root / 'usr/bin'
    binaries.mkdir(parents=True)
    (binaries / 'modureader').symlink_to('/opt/modureader/modu')
    docs = root / 'usr/share/doc/modureader'
    docs.mkdir(parents=True)
    for name in ('LICENSE', 'NOTICE', 'SOURCE.txt'):
        shutil.copy2(bundle / name, docs / name)
    result = output / f'Modu-{version}-linux-{arch}.deb'
    command('dpkg-deb', '--root-owner-group', '--build', root, result)
    if command('dpkg-deb', '-f', result, 'Architecture') != architecture:
        raise ValueError('Incorrect Debian architecture')
    if command('dpkg-deb', '-f', result, 'Version') != deb_version(version, build_number):
        raise ValueError('Incorrect Debian prerelease version')
    extracted = work / 'deb-verify'
    command('dpkg-deb', '-x', result, extracted)
    verify_payload(extracted / 'opt/modureader', 'linux', arch)
    return result


# Ubuntu 24.04's private dependency ABIs that need to travel with the WPE build.
# The host supplies glibc, graphics drivers and the desktop/media platform.
APPIMAGE_COMPAT_LIBRARIES = {
    **{f'libicu{name}.so.74': 'libicu74' for name in ('data', 'i18n', 'uc')},
    'libjsoncpp.so.25': 'libjsoncpp25',
    'libjxl.so.0.7': 'libjxl0.7',
    'libjxl_threads.so.0.7': 'libjxl0.7',
    'libhwy.so.1': 'libhwy1t64',
    'libxml2.so.2': 'libxml2',
    'libxslt.so.1': 'libxslt1.1',
    'libexslt.so.0': 'libxslt1.1',
    'libhyphen.so.0': 'libhyphen0',
    **{f'libflite{name}.so.1': 'libflite1' for name in (
        '', '_cmulex', '_usenglish', '_cmu_indic_lang', '_cmu_indic_lex',
        '_cmu_us_kal16', '_cmu_us_slt')},
}


def prepare_appimage_wpe(prefix, appdir, app):
    libdir = appdir / 'usr/lib'
    helpers = tuple(Path('libexec/wpe-webkit-2.0') / f'WPE{name}Process'
                    for name in ('Web', 'Network', 'GPU'))
    notices = Path('share/doc/modu-wpe')
    required = (
        Path('lib/libWPEWebKit-2.0.so.1'),
        *helpers,
        Path('lib/wpe-webkit-2.0/injected-bundle/libWPEInjectedBundle.so'),
        Path('share/wpe-webkit-2.0/inspector.gresource'),
        notices / 'SOURCE.txt',
    )
    for path in required:
        if not (prefix / path).is_file():
            raise ValueError(f'Incomplete AppImage WPE runtime: {path}')
    for path in sorted((prefix / 'lib').glob('libWPE*.so*')):
        shutil.copy2(path, libdir / path.name, follow_symlinks=False)
    for path in ('lib/wpe-webkit-2.0', 'libexec', 'share'):
        shutil.copytree(prefix / path, appdir / 'usr' / path, symlinks=True)

    for pattern in ('libWPE*.so*', 'libwpe-1.0.so*'):
        for path in (app / 'lib').glob(pattern):
            path.unlink()

    binaries = []
    for path in sorted((appdir / 'usr').rglob('*')):
        if path.is_symlink():
            if (path.readlink().is_absolute() or
                    not path.resolve(strict=True).is_relative_to(appdir)):
                raise ValueError(f'External AppImage symlink: {path}')
        elif path.is_file():
            with path.open('rb') as source:
                header = source.read(20)
            if header[:4] != b'\x7fELF':
                continue
            if header[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', header, 18)[0] != 62:
                raise ValueError(f'Mislabeled AppImage ELF: {path}')
            binaries.append(path)

    c_locale = {**os.environ, 'LC_ALL': 'C'}
    packages = set()
    for path in binaries:
        elf = command('readelf', '--wide', '--dynamic', '--version-info', path, env=c_locale)
        needs = elf.partition('Version needs section')[2]
        for version in re.findall(r'Name:\s+GLIBC_(\d+\.\d+(?:\.\d+)?)\b', needs):
            if tuple(map(int, version.split('.'))) > (2, 39, 0):
                raise ValueError(f'{path.name} requires GLIBC_{version}, newer than Ubuntu 24.04')
        for library in re.findall(r'\(NEEDED\)\s+Shared library: \[([^\]]+)\]', elf):
            if '/' in library:
                raise ValueError(f'AppImage {path.name} uses an absolute build dependency: {library}')
            package = APPIMAGE_COMPAT_LIBRARIES.get(library)
            target = libdir / library
            if package and not target.exists():
                sources = command('dpkg-query', '-L', package)
                source = next((Path(item) for item in sources.splitlines()
                               if Path(item).name == library and Path(item).is_file()), None)
                if source is None:
                    raise ValueError(f'Missing required AppImage library {library} in {package}')
                shutil.copy2(source, target)
                # Check the dependencies of each newly copied library as well.
                binaries.append(target)
                packages.add(package)
        # The pinned ONNX payload does not need relocation and keeps its published checksum.
        if 'Dynamic section at offset' in elf and path.name not in ('libapp.so', LINUX_ONNX_LIBRARY):
            search = (app / 'lib', libdir) if path.is_relative_to(app) else (libdir,)
            relative = [os.path.relpath(directory, path.parent) for directory in search]
            runpath = ':'.join('$ORIGIN' if value == '.' else f'$ORIGIN/{value}'
                               for value in relative)
            command('patchelf', '--set-rpath', runpath, path)

    notice_dir = appdir / 'usr' / notices
    with (notice_dir / 'SOURCE.txt').open('a', encoding='utf-8') as record:
        if packages:
            record.write('\nUbuntu corresponding source packages for compatibility libraries:\n')
            for package in sorted(packages):
                shutil.copy2(Path('/usr/share/doc') / package / 'copyright',
                             notice_dir / f'{package}-copyright.txt')
                record.write(command('dpkg-query', '--show',
                                     '--showformat=${source:Package} ${source:Version}', package) + '\n')
            record.write('Retrieve with apt-get source PACKAGE=VERSION using Ubuntu 24.04 sources.\n')

    clean_env = c_locale.copy()
    clean_env.pop('LD_LIBRARY_PATH', None)
    for path in (app / 'modu', *(appdir / 'usr' / path for path in helpers)):
        if not os.access(path, os.X_OK):
            raise ValueError(f'Missing AppImage executable permission: {path}')
        dependencies = command('ldd', path, env=clean_env)
        if 'not found' in dependencies:
            raise ValueError(f'Unresolved AppImage libraries for {path.name}:\n{dependencies}')
        for line in dependencies.splitlines():
            if 'libWPEWebKit-2.0.so.1 =>' in line:
                resolved = line.split('=>', 1)[1].split(' (', 1)[0].strip()
                if not Path(resolved).resolve().is_relative_to(libdir):
                    raise ValueError(f'{path.name} resolved WPE WebKit outside the AppImage: {resolved}')


def build_linux_appimage(bundle, version, output, runtime_path, wpe_prefix):
    from fetch_appimage_runtime import RUNTIME_TAG, RUNTIME_URL, validate_runtime

    validate_version(version)
    runtime = Path(runtime_path).read_bytes()
    validate_runtime(runtime)
    result = output / f'Modu-{version}-linux-x64.AppImage'
    if result.exists():
        raise ValueError('Refusing to overwrite an existing AppImage')
    with tempfile.TemporaryDirectory(prefix='modu-appimage-', dir=output) as tmp:
        work = Path(tmp)
        appdir = work / 'Modu.AppDir'
        app = appdir / 'usr' / 'lib' / 'modureader'
        shutil.copytree(bundle, app, symlinks=True)
        prepare_linux_runtime(app, 'x64', work, relocate=False)
        (app / 'modu').chmod(0o755)
        prepare_appimage_wpe(Path(wpe_prefix), appdir, app)
        with (app / 'SOURCE.txt').open('a', encoding='utf-8') as source:
            source.write(f'\nAppImage Type 2 runtime: {RUNTIME_URL}\n'
                         f'Runtime source: https://github.com/AppImage/type2-runtime/tree/{RUNTIME_TAG}\n'
                         'Bundled WPE WebKit source and license: ../../share/doc/modu-wpe/\n')
        run = appdir / 'AppRun'
        run.write_text(
            '#!/bin/sh\n'
            'set -eu\n'
            'appdir=$(CDPATH= cd -P "${APPDIR:-${0%/*}}" && pwd)\n'
            'export MODU_WPE_PREFIX="$appdir/usr"\n'
            'exec "$MODU_WPE_PREFIX/lib/modureader/modu" "$@"\n',
            encoding='utf-8')
        run.chmod(0o755)
        write_linux_desktop_entry(appdir / 'modureader.desktop', 'AppRun')
        shutil.copy2(app / 'data/flutter_assets/assets/icon/modu-app-icon.png', appdir / 'modureader.png')
        (appdir / '.DirIcon').symlink_to('modureader.png')
        verify_payload(app, 'linux', 'x64')

        filesystem = work / 'image.squashfs'
        command('mksquashfs', appdir, filesystem, '-noappend', '-all-root', '-no-progress', '-comp', 'gzip')
        packed = work / result.name
        with packed.open('wb') as image, filesystem.open('rb') as data:
            image.write(runtime)
            shutil.copyfileobj(data, image)
        packed.chmod(0o755)
        if command(packed, '--appimage-offset') != str(len(runtime)):
            raise ValueError('Incorrect AppImage filesystem offset')
        packed.rename(result)
    return result


def build(bundle, platform, arch, version, output, build_number=None):
    bundle, output = Path(bundle).resolve(), Path(output).resolve()
    validate_version(version)
    verify_payload(bundle, platform, arch)
    if platform == 'macos':
        verify_apple_bundle(bundle / 'Modu.app', version)
    output.mkdir(parents=True, exist_ok=True)
    names = {'macos': f'Modu-{version}-macos-{arch}.dmg',
             'windows': f'Modu-{version}-windows-{arch}-setup.exe',
             'linux': f'Modu-{version}-linux-{arch}.deb'}
    if (output / names[platform]).exists():
        raise ValueError('Refusing to overwrite an existing installer')
    with tempfile.TemporaryDirectory(prefix='modu-installer-') as tmp:
        work = Path(tmp)
        builder = {'macos': build_dmg, 'windows': build_windows, 'linux': build_deb}[platform]
        options = {'build_number': build_number} if platform == 'linux' else {}
        result = builder(bundle, arch, version, output, work, **options)
    checksum(result)
    print(f'Created and checked: {result}')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('platform', choices=['macos', 'windows', 'linux'])
    parser.add_argument('arch', choices=['x64', 'arm64'])
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    build(args.bundle, args.platform, args.arch, args.version, args.output)
