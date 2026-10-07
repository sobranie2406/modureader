"""Collect only unsigned HAP candidates; never upload an entire build/SDK tree.

The filename is the toolchain's unsigned-output convention, not a security
attestation. Local signing and signature verification are still mandatory.
"""
import hashlib
import json
from pathlib import Path
import shutil
import zipfile
import re
import argparse


def verify_native_assets(archive):
    names = archive.namelist()
    library = 'libs/arm64-v8a/libtokenizers_ffi.so'
    if library not in names:
        raise ValueError('HAP is missing the OHOS arm64 tokenizer library.')
    header = archive.read(library)[:20]
    if (len(header) != 20 or header[:6] != b'\x7fELF\x02\x01'
            or header[16:20] != b'\x03\x00\xb7\x00'):
        raise ValueError('HAP tokenizer is not an AArch64 shared library.')
    manifests = [name for name in names if name.endswith('/NativeAssetsManifest.json')]
    if len(manifests) != 1:
        raise ValueError('HAP must contain one native-assets manifest.')
    manifest = json.loads(archive.read(manifests[0]))
    entry = manifest.get('native-assets', {}).get('ohos_arm64', {}).get(
        'package:hf_tokenizers/src/bindings.dart')
    if entry != ['absolute', 'libtokenizers_ffi.so']:
        raise ValueError('HAP native-assets manifest does not map the OHOS tokenizer.')


def collect(root: Path) -> list[Path]:
    # Flutter OH copies Hvigor outputs here; prefer that final copy.
    canonical = root / 'build/ohos/hap'
    bases = (canonical,) if any(canonical.glob('*-unsigned.hap')) else (root / 'ohos', root / 'build/app')
    sources = sorted({p.resolve() for base in bases
                      if base.exists() for p in base.rglob('*-unsigned.hap')})
    if not sources:
        raise ValueError('No unsigned HAP; nothing will be published.')
    if len({p.name for p in sources}) != len(sources):
        raise ValueError('Ambiguous duplicate HAP names; inspect build outputs.')
    for source in sources:
        if not source.is_relative_to(root.resolve()):
            raise ValueError('HAP resolves outside the workspace.')
        with zipfile.ZipFile(source) as archive:
            if archive.testzip() is not None:
                raise ValueError('Corrupt HAP.')
            if 'module.json' not in archive.namelist():
                raise ValueError('HAP is missing module.json.')
            verify_native_assets(archive)
    output = root / 'build/harmony-unsigned'
    output.mkdir(parents=True, exist_ok=False)
    checksums = []
    for source in sources:
        target = output / source.name
        shutil.copyfile(source, target)
        with target.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        checksums.append(f'{digest}  {target.name}')
    (output / 'SHA256SUMS').write_text('\n'.join(checksums) + '\n', encoding='utf-8')
    return sources


def package_release(root: Path) -> Path:
    """Require the same version/build and native payload as the tagged source."""
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+(?:-[\w.]+)?)\+(\d+)\s*$',
                      (root / 'pubspec.yaml').read_text(), re.MULTILINE)
    if match is None:
        raise ValueError('Missing release version/build in pubspec')
    version, build = match.groups()
    sources = collect(root)
    if len(sources) != 1:
        raise ValueError('Expected exactly one entry HAP for release')
    with zipfile.ZipFile(sources[0]) as archive:
        app = json.loads(archive.read('module.json')).get('app', {})
        if (app.get('bundleName') != 'com.modu.reader'
                or app.get('versionName') != version
                or app.get('versionCode') != int(build)):
            raise ValueError('HAP identity/version/build does not match release source')
    output = root / 'dist-release'
    output.mkdir(parents=True, exist_ok=True)
    target = output / f'Modu-{version}-harmony-arm64.hap'
    if target.exists() or target.with_name(target.name + '.sha256').exists():
        raise ValueError('Refusing to overwrite an existing release HAP')
    shutil.copyfile(sources[0], target)
    with target.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    target.with_name(target.name + '.sha256').write_text(
        f'{digest}  {target.name}\n', encoding='utf-8')
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', action='store_true')
    args = parser.parse_args()
    if args.release:
        package_release(Path.cwd())
    else:
        collect(Path.cwd())
