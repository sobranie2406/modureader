"""Fail packaging on native mobile ABI, page-size or Apple version mistakes."""
import argparse
from pathlib import Path
import plistlib
import re
import struct
import zipfile


def apple_version(version):
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?(?:\+\d+)?', version):
        raise ValueError('Invalid application version')
    return version.split('+')[0].split('-')[0]


def verify_apple_bundle(app, expected):
    info = app / ('Contents/Info.plist' if (app / 'Contents').is_dir() else 'Info.plist')
    metadata = plistlib.loads(info.read_bytes())
    if metadata.get('CFBundleShortVersionString') != apple_version(expected):
        raise ValueError(f'Apple marketing version must be {apple_version(expected)}: {info}')
    if not re.fullmatch(r'\d+(?:\.\d+){0,2}', str(metadata.get('CFBundleVersion', ''))):
        raise ValueError(f'Invalid Apple build number: {info}')


def verify_android_elf(data, machine):
    if len(data) < 64 or data[:6] != b'\x7fELF\x02\x01':
        raise ValueError('Expected a little-endian ELF64 library')
    if struct.unpack_from('<H', data, 18)[0] != machine:
        raise ValueError('Incorrect Android native architecture')
    offset = struct.unpack_from('<Q', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 54)
    if size < 56 or not count or offset + size * count > len(data):
        raise ValueError('Malformed ELF program headers')
    loads = []
    for i in range(count):
        header = struct.unpack_from('<IIQQQQQQ', data, offset + i * size)
        if header[0] == 1:
            loads.append(header)
            if (header[7] < 16384 or header[7] & (header[7] - 1)
                    or (header[3] - header[2]) % 16384):
                raise ValueError('ELF LOAD segments must be 16 KB aligned')
    if not loads:
        raise ValueError('ELF has no LOAD segments')


def verify_android_apk(apk, arch):
    abi, machine = {'arm64': ('arm64-v8a', 183), 'x64': ('x86_64', 62)}[arch]
    with zipfile.ZipFile(apk) as archive:
        if archive.testzip() is not None:
            raise ValueError('Corrupt APK')
        libraries = [n for n in archive.namelist() if n.startswith('lib/') and n.endswith('.so')]
        for required in ('libapp.so', 'libflutter.so', 'libtokenizers_ffi.so'):
            if f'lib/{abi}/{required}' not in libraries:
                raise ValueError(f'Missing Android native library: {required}')
        for name in libraries:
            if not name.startswith(f'lib/{abi}/'):
                raise ValueError(f'Unexpected APK ABI: {name}')
            try:
                verify_android_elf(archive.read(name), machine)
            except ValueError as error:
                raise ValueError(f'{name}: {error}') from error
    print(f'Android {arch}: all {len(libraries)} native libraries have correct ABI and 16 KB ELF alignment')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--apple-build-name', action='store_true')
    args = parser.parse_args()
    if args.apple_build_name:
        pubspec = Path(__file__).resolve().parents[2] / 'pubspec.yaml'
        version = next(line.split(':', 1)[1].strip() for line in pubspec.read_text().splitlines()
                       if line.startswith('version:'))
        print(apple_version(version))
