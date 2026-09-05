"""Bundle architecture-matched, app-local CRT DLLs from Visual Studio's Redist.

No system-wide installer, privilege elevation or third-party DLL downloads.
"""
import hashlib
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


def pe_machine(path):
    data = path.read_bytes()
    if len(data) < 64 or data[:2] != b'MZ':
        raise ValueError(f'Malformed PE library: {path.name}')
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    if offset + 24 > len(data) or data[offset:offset+4] != b'PE\0\0':
        raise ValueError(f'Malformed PE header: {path.name}')
    return struct.unpack_from('<H', data, offset+4)[0]


def pe_imports(path):
    """Normal and delay-loaded DLL names from a PE32+ image, without executing it."""
    pe_machine(path)
    data = path.read_bytes()
    offset = struct.unpack_from('<I', data, 0x3c)[0]
    sections = struct.unpack_from('<H', data, offset+6)[0]
    optional_size = struct.unpack_from('<H', data, offset+20)[0]
    optional = offset + 24
    if optional_size < 112 or optional + optional_size > len(data):
        raise ValueError(f'Malformed PE optional header: {path.name}')
    if struct.unpack_from('<H', data, optional)[0] != 0x20b:
        raise ValueError(f'Expected PE32+ image: {path.name}')
    count = struct.unpack_from('<I', data, optional+108)[0]
    table = optional + optional_size

    def rva(address):
        for index in range(sections):
            start = table + index * 40
            if start + 40 > len(data): raise ValueError('Truncated PE sections')
            virtual_size, virtual_address, raw_size, raw_address = struct.unpack_from('<IIII', data, start+8)
            if virtual_address <= address < virtual_address + max(virtual_size, raw_size):
                result = raw_address + address - virtual_address
                if result >= len(data): raise ValueError('PE RVA outside file')
                return result
        raise ValueError(f'Unmapped PE RVA in {path.name}')

    names = set()
    for directory, stride, name_index in [(1, 20, 3), (13, 32, 1)]:
        if count <= directory: continue
        entry = optional + 112 + directory * 8
        if entry + 8 > table: raise ValueError('Truncated PE data directories')
        address, size = struct.unpack_from('<II', data, entry)
        if not address: continue
        start = rva(address)
        for position in range(start, start + size, stride):
            if position + stride > len(data): raise ValueError('Truncated PE imports')
            values = struct.unpack_from('<' + 'I' * (stride // 4), data, position)
            if not any(values): break
            if directory == 13 and values[0] != 1:
                raise ValueError('Unsupported delay import addressing')
            name_start = rva(values[name_index])
            name_end = data.find(b'\0', name_start)
            if name_end < 0: raise ValueError('Unterminated DLL import')
            names.add(data[name_start:name_end].decode('ascii').lower())
    return names


def verify_crt(bundle, arch):
    required = ['msvcp140.dll', 'msvcp140_1.dll', 'vcruntime140.dll']
    if arch == 'x64':
        required.append('vcruntime140_1.dll')
    for name in required:
        path = bundle / name
        if not path.is_file():
            raise ValueError(f'Missing app-local VC++ runtime: {name}')
    for path in bundle.glob('*.dll'):
        if not path.name.lower().startswith(('msvcp', 'vcruntime', 'concrt', 'vccorlib')):
            continue
        if pe_machine(path) != {'x64': 0x8664, 'arm64': 0xaa64}[arch]:
            raise ValueError(f'Incorrect CRT architecture: {path.name}')


def find_redist():
    if os.environ.get('VCToolsRedistDir'):
        return Path(os.environ['VCToolsRedistDir'])
    vswhere = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Microsoft Visual Studio/Installer/vswhere.exe'
    install = subprocess.check_output([
        str(vswhere), '-latest', '-products', '*', '-requires',
        'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath',
    ], text=True).strip()
    if not install:
        raise RuntimeError('Visual Studio C++ build tools and redistributable files are required')
    root = Path(install)
    # Match the active default build toolset instead of selecting arbitrary older DLLs.
    version_file = root / 'VC/Auxiliary/Build/Microsoft.VCRedistVersion.default.txt'
    version = version_file.read_text().strip()
    if not version or any(c not in '0123456789.' for c in version):
        raise ValueError('Invalid Visual Studio redistributable version')
    return root / 'VC/Redist/MSVC' / version


def prepare_windows_runtime(bundle, arch, redist=None):
    redist = Path(redist) if redist is not None else find_redist()
    candidates = sorted((redist / arch).glob('Microsoft.VC*.CRT'))
    if len(candidates) != 1:
        raise RuntimeError(f'Expected one {arch} CRT directory in the selected VS redistributable')
    source = candidates[0]
    # Only files marked redistributable by VS, never Debug CRT or System32.
    expected_machine = {'x64': 0x8664, 'arm64': 0xaa64}[arch]
    candidates = sorted(source.glob('*.dll'))
    dlls = [dll for dll in candidates if pe_machine(dll) == expected_machine]
    excluded = [dll for dll in candidates if dll not in dlls]
    if not dlls:
        raise RuntimeError('Visual Studio CRT redistributable is empty')
    # VS ARM64 redist can include compatibility-only binaries of another
    # architecture. Never ship those in the pure ARM64 payload, and refuse to
    # omit them if the application or retained CRT actually imports them.
    if excluded:
        required = set()
        images = [p for p in bundle.rglob('*') if p.suffix.lower() in ('.exe', '.dll')]
        for image in images + dlls:
            required.update(pe_imports(image))
        for dll in excluded:
            machine = pe_machine(dll)
            if dll.name.lower() in required:
                raise ValueError(f'Required CRT has incompatible architecture: {dll.name} (0x{machine:04x})')
            print(f'Excluded unused compatibility CRT: {dll.name} (0x{machine:04x}); target {arch}')
    for dll in dlls:
        shutil.copy2(dll, bundle / dll.name)
    verify_crt(bundle, arch)
    records = [f'{dll.name}  SHA-256: {hashlib.sha256(dll.read_bytes()).hexdigest()}' for dll in dlls]
    (bundle / 'WINDOWS-RUNTIME.txt').write_text(
        'Microsoft Visual C++ Runtime (proprietary Microsoft redistributable)\n'
        f'Visual Studio Redist version: {redist.name}; architecture: {arch}\n'
        f'Source component: {source.name}\n'
        'App-local deployment; no system-wide runtime installation or elevation.\n'
        'These DLLs are not covered by the application GPL license.\n'
        'https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files\n'
        + '\n'.join(records) + '\n', encoding='utf-8')


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('arch', choices=['x64', 'arm64'])
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='modu-crt-preflight-') as temporary:
        prepare_windows_runtime(Path(temporary), args.arch)
    print(f'Windows {args.arch} toolchain CRT preflight passed')
