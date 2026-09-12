"""Resolve only synthetic CI crash RVAs against that run's exact PE/PDB files.

Not shipped or run on a user's computer; never enables memory dumps or uploads
user logs. Even 'omitted' module names can be matched using the PE signature.
"""
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys


def signature(binary):
    with Path(binary).open('rb') as stream:
        dos = stream.read(64)
        if len(dos) != 64 or dos[:2] != b'MZ':
            return None
        stream.seek(struct.unpack_from('<I', dos, 60)[0])
        header = stream.read(88)
    if len(header) != 88 or header[:4] != b'PE\0\0':
        return None
    return f'{struct.unpack_from("<I", header, 8)[0]:x}-{struct.unpack_from("<I", header, 80)[0]:x}'


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.name != 'nt':
        raise RuntimeError('Only run against synthetic Windows CI records')
    trace, folder = map(Path, sys.argv[1:])
    symbols = shutil.which('llvm-symbolizer') or r'C:\Program Files\LLVM\bin\llvm-symbolizer.exe'
    if not Path(symbols).is_file():
        print('LLVM symbolizer unavailable; retain binaries/PDBs for offline analysis')
        return
    binaries = {}
    for file in folder.iterdir():
        if file.suffix.lower() in ('.exe', '.dll'):
            binaries.setdefault(signature(file), []).append(file)
    for line in trace.read_text().splitlines():
        frame = re.fullmatch(r'frame=([^|]+)\|([0-9a-f]+)\|([0-9a-f-]+)', line)
        if not frame:
            continue
        name, offset, image = frame.groups()
        matches = binaries.get(image, [])
        if len(matches) != 1:
            print(f'No unique local PE match: {name} +0x{offset} {image}')
            continue
        binary = matches[0]
        print(f'CI SYMBOL {binary.name} +0x{offset} signature={image}', flush=True)
        subprocess.run([symbols, f'--obj={binary}', '--relative-address',
                        '--inlining=false', f'0x{offset}'], check=False, timeout=20)


if __name__ == '__main__':
    main()
