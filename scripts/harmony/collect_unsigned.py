"""Collect only unsigned HAP candidates; never upload an entire build/SDK tree.

The filename is the toolchain's unsigned-output convention, not a security
attestation. Local signing and signature verification are still mandatory.
"""
import hashlib
from pathlib import Path
import shutil
import zipfile


def collect(root: Path) -> list[Path]:
    sources = sorted({p.resolve() for base in (root / 'ohos', root / 'build/app')
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


if __name__ == '__main__':
    collect(Path.cwd())
