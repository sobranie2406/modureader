"""Wrap a released desktop payload without rebuilding or changing its app code."""
import argparse
import hashlib
from pathlib import Path
import shutil
import tarfile
import tempfile
import zipfile

from native_installers import build, command, validate_version


def repack(platform, arch, tag, output):
    if not tag.startswith('v'):
        raise ValueError('Release tag must start with v')
    version = validate_version(tag[1:])
    suffix = {'macos': '-unnotarized.zip', 'windows': '.zip', 'linux': '.tar.gz'}[platform]
    filename = f'Modu-{version}-{platform}-{arch}{suffix}'
    repo = 'sobranie2406/modureader'
    with tempfile.TemporaryDirectory(prefix='modu-repack-') as tmp:
        root = Path(tmp)
        command('gh', 'release', 'download', tag, '--repo', repo,
                '--pattern', filename, '--pattern', filename + '.sha256', '--dir', root)
        archive = root / filename
        expected = (root / (filename + '.sha256')).read_text().split()[0]
        with archive.open('rb') as f:
            if hashlib.file_digest(f, 'sha256').hexdigest() != expected:
                raise ValueError('Released payload checksum mismatch')
        bundle = root / 'payload'
        bundle.mkdir()
        if platform == 'macos':
            command('ditto', '-x', '-k', archive, bundle)
        elif platform == 'linux':
            with tarfile.open(archive) as t:
                t.extractall(bundle, filter='data')
            bundle = bundle / filename.removesuffix('.tar.gz')
        else:
            with zipfile.ZipFile(archive) as z:
                for info in z.infolist():
                    target = (bundle / info.filename).resolve()
                    if not target.is_relative_to(bundle.resolve()):
                        raise ValueError('Unsafe archive path')
                z.extractall(bundle)
        source_sha = command('gh', 'api', f'repos/{repo}/commits/{tag}', '--jq', '.sha')
        if source_sha not in (bundle / 'SOURCE.txt').read_text():
            raise ValueError('Payload source does not match the release tag')
        installer_sha = command('git', 'rev-parse', 'HEAD')
        shutil.copy2(Path(__file__).resolve().parents[2] / 'docs/RELEASING.md', bundle / 'INSTALL.md')
        (bundle / 'INSTALLER-SOURCE.txt').write_text(
            f'Application source: {source_sha} ({tag})\n'
            f'Application payload SHA-256: {expected}\n'
            f'Installer scripts: https://github.com/{repo}/tree/{installer_sha}/scripts/release\n'
            'Application business code is not recompiled.\n'
            'Linux additionally restores ONNX Runtime and relocates ELF RPATH; see LINUX-RUNTIME.txt.\n', encoding='utf-8')
        return build(bundle, platform, arch, version, Path(output))


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('platform', choices=['macos', 'windows', 'linux'])
    p.add_argument('arch', choices=['x64', 'arm64'])
    p.add_argument('--tag', required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    repack(a.platform, a.arch, a.tag, a.output)
