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
    for notice in ('LICENSE', 'NOTICE', 'SOURCE.txt'):
        if not (bundle / notice).is_file():
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


def build_dmg(bundle, arch, version, output, work):
    stage = work / 'image'
    command('ditto', bundle, stage)
    (stage / 'Applications').symlink_to('/Applications', target_is_directory=True)
    (stage / 'READ-ME-FIRST.txt').write_text(
        'Modu / 默读\n将 Modu.app 拖到 Applications 安装。\n'
        '此版本没有 Apple Developer ID 公证。请勿关闭系统安全保护。\n'
        'Drag Modu.app to Applications. This release is not notarized.\n', encoding='utf-8')
    result = output / f'Modu-{version}-macos-{arch}-unnotarized.dmg'
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
        if (mount / 'SOURCE.txt').read_bytes() != (bundle / 'SOURCE.txt').read_bytes():
            raise ValueError('Source provenance changed')
    finally:
        command('hdiutil', 'detach', mount)
    return result


def windows_script(bundle, arch, version, output):
    validate_version(version)
    arch_rule = {'x64': 'x64os', 'arm64': 'arm64'}[arch]
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
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Files]
Source: "{bundle}\\*"; DestDir: "{{app}}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{{group}}\\Modu"; Filename: "{{app}}\\modu.exe"; WorkingDir: "{{app}}"
Name: "{{userdesktop}}\\Modu"; Filename: "{{app}}\\modu.exe"; WorkingDir: "{{app}}"; Tasks: desktopicon
[Run]
Filename: "{{app}}\\modu.exe"; Description: "Launch Modu (requires Microsoft WebView2 Runtime)"; Flags: nowait postinstall skipifsilent
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


def prepare_linux_runtime(app, arch, work):
    # flutter_onnxruntime 1.8.4 bundles only a symlink, omitting its target.
    # Supply the exact upstream version used to link the released plugin.
    upstream_arch, digest = {
        'x64': ('x64', '8344d55f93d5bc5021ce342db50f62079daf39aaafb5d311a451846228be49b3'),
        'arm64': ('aarch64', 'bb76395092d150b52c7092dc6b8f2fe4d80f0f3bf0416d2f269193e347e24702'),
    }[arch]
    basename = f'onnxruntime-linux-{upstream_arch}-1.22.0'
    url = f'https://github.com/microsoft/onnxruntime/releases/download/v1.22.0/{basename}.tgz'
    archive = work / 'onnxruntime.tgz'
    with urllib.request.urlopen(url, timeout=120) as response, archive.open('wb') as target:
        shutil.copyfileobj(response, target)
    with archive.open('rb') as source:
        if hashlib.file_digest(source, 'sha256').hexdigest() != digest:
            raise ValueError('Official ONNX Runtime archive checksum mismatch')
    library = app / 'lib/libonnxruntime.so.1.22.0'
    with tarfile.open(archive) as source:
        member = source.getmember(f'{basename}/lib/{library.name}')
        if not member.isfile():
            raise ValueError('Expected a real ONNX Runtime shared library')
        with source.extractfile(member) as data, library.open('wb') as target:
            shutil.copyfileobj(data, target)
    soname = app / 'lib/libonnxruntime.so.1'
    if not soname.exists():
        soname.symlink_to(library.name)
    # Plugin files carry absolute CI build paths. Relocate them to the package's
    # own library directory; never add application libraries to global ldconfig.
    for plugin in (app / 'lib').glob('*.so'):
        if not plugin.is_symlink() and plugin.name != 'libapp.so':
            command('patchelf', '--set-rpath', '$ORIGIN', plugin)
    command('patchelf', '--set-rpath', '$ORIGIN/lib', app / 'modu')
    (app / 'LINUX-RUNTIME.txt').write_text(
        f'ONNX Runtime 1.22.0: {url}\nSHA-256: {digest}\n'
        'MIT license and ThirdPartyNotices: LICENSES/ONNXRuntime-1.22.0-*.txt\n'
        'Missing runtime payload restored; ELF RPATH metadata made relocatable.\n'
        'This packaging step adjusts runtime libraries; application source is recorded in SOURCE.txt.\n', encoding='utf-8')


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
    (desktop / 'modureader.desktop').write_text(
        '[Desktop Entry]\nType=Application\nName=Modu Reader\nName[zh_CN]=默读\n'
        'Comment=Read ebooks with AI tools\nExec=modureader\nIcon=modureader\n'
        'Terminal=false\nCategories=Office;Viewer;\nStartupWMClass=com.modu.reader\n', encoding='utf-8')
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
    command('desktop-file-validate', desktop / 'modureader.desktop')
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


def build(bundle, platform, arch, version, output, build_number=None):
    bundle, output = Path(bundle).resolve(), Path(output).resolve()
    validate_version(version)
    verify_payload(bundle, platform, arch)
    if platform == 'macos':
        verify_apple_bundle(bundle / 'Modu.app', version)
    output.mkdir(parents=True, exist_ok=True)
    names = {'macos': f'Modu-{version}-macos-{arch}-unnotarized.dmg',
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
