"""Combine verified native builds; retain byte-identical old updater filenames."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile
import tempfile

from native_installers import (build_dmg, checksum, command, verify_payload,
                               windows_script, validate_version)
from verify_mobile import verify_apple_bundle
from windows_runtime import verify_crt

MACHO = {bytes.fromhex(value) for value in
         ('cffaedfe', 'cefaedfe', 'feedfacf', 'feedface', 'cafebabe', 'bebafeca')}


def file_digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def export_payload(bundle, platform, arch):
    output = Path(__file__).resolve().parents[2] / 'build/desktop-payload'
    output.mkdir(parents=True, exist_ok=True)
    with tarfile.open(output / f'{platform}-{arch}.tar', 'w') as archive:
        archive.add(bundle, arcname='.')


def merge_native_assets(arm, intel):
    a, b = json.loads(arm), json.loads(intel)
    if set(a.get('native-assets', {})) != {'macos_arm64'} or set(b.get('native-assets', {})) != {'macos_x64'}:
        raise ValueError('Unexpected native asset architecture')
    if {k:v for k,v in a.items() if k != 'native-assets'} != {k:v for k,v in b.items() if k != 'native-assets'}:
        raise ValueError('Native asset manifest formats differ')
    if a['native-assets']['macos_arm64'] != b['native-assets']['macos_x64']:
        raise ValueError('Native asset library paths differ')
    return json.dumps({**a, 'native-assets': {**a['native-assets'], **b['native-assets']}}, separators=(',', ':'))


def merge_macos(arm, intel, destination, version):
    for folder, arch in [(arm, 'arm64'), (intel, 'x64')]:
        verify_payload(folder, 'macos', arch)
        verify_apple_bundle(folder / 'Modu.app', version)
    shutil.copytree(arm, destination, symlinks=True)
    files = lambda root: {p.relative_to(root) for p in root.rglob('*')
                         if (p.is_file() or p.is_symlink()) and '_CodeSignature' not in p.parts}
    if files(arm) != files(intel):
        raise ValueError('macOS payload file sets differ')
    for relative in sorted(files(arm)):
        a, b, output = arm / relative, intel / relative, destination / relative
        if a.is_symlink() or b.is_symlink():
            if not (a.is_symlink() and b.is_symlink() and os.readlink(a) == os.readlink(b)):
                raise ValueError(f'Incompatible symlink: {relative}')
            continue
        with a.open('rb') as stream:
            native = stream.read(4) in MACHO
        if native:
            if set(command('lipo', '-archs', a).split()) != {'arm64'} or set(command('lipo', '-archs', b).split()) != {'x86_64'}:
                raise ValueError(f'Expected matching thin native slices: {relative}')
            output.unlink()
            command('lipo', '-create', a, b, '-output', output)
            output.chmod(a.stat().st_mode)
            if set(command('lipo', '-archs', output).split()) != {'arm64', 'x86_64'}:
                raise ValueError(f'Missing universal slice: {relative}')
        elif file_digest(a) != file_digest(b):
            if relative.name == 'NativeAssetsManifest.json':
                output.write_text(merge_native_assets(a.read_text(), b.read_text()))
                continue
            if relative.name == 'Assets.car':
                catalogs = [json.loads(command('xcrun', 'assetutil', '--info', path)) for path in (a, b)]
                for catalog in catalogs:
                    for entry in catalog:
                        entry.pop('Timestamp', None)
                        entry.pop('Key Format', None)
                        # actool encodes default icon states explicitly on Intel.
                        if 'AssetType' in entry:
                            entry.setdefault('State', 'Normal')
                            entry.setdefault('Presentation State', 'Active')
                if catalogs[0] == catalogs[1]:
                    continue
            # Native runners can use different Xcode build-machine metadata.
            if relative.name == 'Info.plist':
                pa, pb = (plistlib.loads(p.read_bytes()) for p in (a, b))
                semantic = lambda data: {k: v for k, v in data.items()
                                         if not k.startswith('DT') and k != 'BuildMachineOSBuild'}
                if semantic(pa) == semantic(pb):
                    continue
            raise ValueError(f'Architecture-independent resource differs: {relative}')
    app = destination / 'Modu.app'
    command('codesign', '--force', '--deep', '--sign', '-',
            '--preserve-metadata=entitlements', app)
    verify_payload(destination, 'macos', 'universal')


def combined_windows_script(arm, intel, version, output):
    script = windows_script(intel, 'x64', version, output)
    script = script.replace('ArchitecturesAllowed=x64os', 'ArchitecturesAllowed=x64os or arm64')
    script = script.replace('ArchitecturesInstallIn64BitMode=x64os', 'ArchitecturesInstallIn64BitMode=x64os or arm64')
    script = script.replace(f'Modu-{version}-windows-x64-setup', f'Modu-{version}-windows-universal-setup')
    original = f'Source: "{intel}\\*"; DestDir: "{{app}}"; Flags: ignoreversion recursesubdirs createallsubdirs'
    assert original in script
    return script.replace(original,
        f'Source: "{arm}\\*"; DestDir: "{{app}}"; Check: IsArm64; Flags: ignoreversion recursesubdirs createallsubdirs\n'
        + original + '; Check: not IsArm64')


def compatibility_copies(installer, platform, version):
    checksum(installer)
    suffix = '.dmg' if platform == 'macos' else '-setup.exe'
    for arch in ('arm64', 'x64'):
        alias = installer.parent / f'Modu-{version}-{platform}-{arch}{suffix}'
        if alias.exists():
            raise ValueError(f'Refusing to replace {alias}')
        shutil.copyfile(installer, alias)
        checksum(alias)
        if file_digest(alias) != file_digest(installer):
            raise ValueError('Compatibility copy differs from universal installer')


def combine(platform, inputs, output, version):
    validate_version(version)
    output.mkdir(parents=True, exist_ok=True)
    suffix = '.dmg' if platform == 'macos' else '-setup.exe'
    result = output / f'Modu-{version}-{platform}-universal{suffix}'
    if result.exists():
        raise ValueError('Universal installer already exists')
    with tempfile.TemporaryDirectory(prefix='modu-universal-') as tmp:
        work = Path(tmp)
        folders = {}
        for arch in ('arm64', 'x64'):
            folder = work / arch
            folder.mkdir()
            with tarfile.open(inputs / f'{platform}-{arch}.tar') as archive:
                archive.extractall(folder, filter='data')
            verify_payload(folder, platform, arch)
            folders[arch] = folder
        if platform == 'macos':
            merged = work / 'merged'
            merge_macos(folders['arm64'], folders['x64'], merged, version)
            build_dmg(merged, 'universal', version, output, work)
        else:
            for arch, folder in folders.items():
                verify_crt(folder, arch)
            # Both payloads must be built from this same version and source.
            if (folders['arm64'] / 'SOURCE.txt').read_bytes() != (folders['x64'] / 'SOURCE.txt').read_bytes():
                raise ValueError('Windows payload source revisions differ')
            script = work / 'universal.iss'
            script.write_text(combined_windows_script(folders['arm64'], folders['x64'], version, output), encoding='utf-8-sig')
            compiler = shutil.which('iscc') or str(Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Inno Setup 6/ISCC.exe')
            subprocess.run([compiler, str(script)], check=True)
            if not result.is_file() or result.stat().st_size < 1000000:
                raise ValueError('Universal Windows installer was not generated')
    compatibility_copies(result, platform, version)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('platform', choices=['macos', 'windows'])
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    print(combine(args.platform, args.inputs.resolve(), args.output.resolve(), args.version))
