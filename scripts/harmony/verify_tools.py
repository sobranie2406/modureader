"""Reject login/error pages and incomplete SDK archives before installation."""
import hashlib
from pathlib import Path, PurePosixPath
import re
import stat
import sys
import zipfile


def verify(path: Path, expected_sha256: str) -> None:
    if not re.fullmatch(r'[0-9a-fA-F]{64}', expected_sha256):
        raise ValueError('Expected an official SHA-256 digest.')
    with path.open('rb') as source:
        if source.read(4) != b'PK\x03\x04':
            raise ValueError('Download is not a ZIP; it may be a login/error page. '
                             'Obtain the authorized file URL, not the download-center page URL.')
        source.seek(0)
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    if digest != expected_sha256.lower():
        raise ValueError('SHA-256 mismatch: incomplete or wrong-version download; installation stopped.')
    try:
        with zipfile.ZipFile(path) as archive:
            for member in archive.infolist():
                name = PurePosixPath(member.filename)
                if name.is_absolute() or '..' in name.parts or '\\' in member.filename:
                    raise ValueError('Unsafe ZIP member path.')
                if stat.S_ISLNK(member.external_attr >> 16):
                    # Official tool bundles can contain relative links. Do not
                    # permit links that escape the extraction directory.
                    target = archive.read(member).decode('utf-8')
                    parts = list(name.parent.parts)
                    if target.startswith('/') or '\\' in target:
                        raise ValueError('Unsafe ZIP symbolic link.')
                    for part in PurePosixPath(target).parts:
                        if part == '..':
                            if not parts:
                                raise ValueError('Unsafe ZIP symbolic link.')
                            parts.pop()
                        elif part != '.':
                            parts.append(part)
            if archive.testzip() is not None:
                raise ValueError('ZIP integrity check failed; installation stopped.')
    except zipfile.BadZipFile as error:
        raise ValueError('Incomplete or invalid ZIP; installation stopped.') from error


if __name__ == '__main__':
    try:
        verify(Path(sys.argv[1]), sys.argv[2])
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
