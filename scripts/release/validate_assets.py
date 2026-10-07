"""Reject incomplete/mixed-version releases before uploading public assets."""
import argparse
import hashlib
from pathlib import Path
import re


def validate(directory, tag, include_harmony=False):
    if not re.fullmatch(r'v\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?', tag):
        raise ValueError('Invalid version tag')
    version = tag[1:]
    expected = set()
    for platform, extension in [('android', '.apk'), ('linux', '.deb'),
                                ('windows', '-setup.exe'), ('macos', '.dmg')]:
        for arch in ('x64', 'arm64'):
            if platform == 'android' and arch == 'x64':
                continue
            expected.add(f'Modu-{version}-{platform}-{arch}{extension}')
    expected.add(f'Modu-{version}-ios-arm64.ipa')
    if include_harmony:
        expected.add(f'Modu-{version}-harmony-arm64.hap')
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
    args = parser.parse_args()
    print(f'Verified {validate(args.directory, args.tag, args.include_harmony)} application packages and their SHA-256 files.')
