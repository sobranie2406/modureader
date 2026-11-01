"""Reject incomplete/mixed-version releases before uploading public assets."""
import argparse
import hashlib
from pathlib import Path
import re


def validate(directory, tag, include_harmony=False, targets='all'):
    if not re.fullmatch(r'v\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?', tag):
        raise ValueError('Invalid version tag')
    version = tag[1:]
    packages = {}
    for platform, extension in [('android', '.apk'), ('linux', '.deb'),
                                ('windows', '-setup.exe'), ('macos', '.dmg')]:
        for arch in ('x64', 'arm64'):
            if platform == 'android' and arch == 'x64':
                continue
            key = 'android' if platform == 'android' else f'{platform}-{arch}'
            packages[key] = f'Modu-{version}-{platform}-{arch}{extension}'
    packages['ios'] = f'Modu-{version}-ios-arm64.ipa'
    if include_harmony:
        packages['harmony'] = f'Modu-{version}-harmony-arm64.hap'
    selected = list(packages) if targets == 'all' else [t.strip() for t in targets.split(',')]
    if not selected or any(t not in packages for t in selected) or len(set(selected)) != len(selected):
        raise ValueError('Invalid release targets')
    expected = {packages[t] for t in selected}
    files = {p.name for p in Path(directory).iterdir() if p.is_file()}
    complete = expected | {name + '.sha256' for name in expected}
    if files != complete:
        raise ValueError(f'Wrong release asset set: missing={sorted(complete-files)}, unexpected={sorted(files-complete)}')
    for name in sorted(expected):
        artifact = Path(directory) / name
        if artifact.stat().st_size == 0:
            raise ValueError(f'Empty artifact: {name}')
        checksum = artifact.with_name(name + '.sha256').read_text().split()
        with artifact.open('rb') as source:
            actual = hashlib.file_digest(source, 'sha256').hexdigest()
        if checksum != [actual, name]:
            raise ValueError(f'Checksum mismatch: {name}')
    return len(expected)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('tag')
    parser.add_argument('--include-harmony', action='store_true')
    parser.add_argument('--targets', default='all')
    args = parser.parse_args()
    print(f'Verified {validate(args.directory, args.tag, args.include_harmony, args.targets)} application packages and their SHA-256 files.')
