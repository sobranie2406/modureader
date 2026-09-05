"""Bundle architecture-matched, app-local CRT DLLs from Visual Studio's Redist.

No system-wide installer, privilege elevation or third-party DLL downloads.
"""
import hashlib
import os
from pathlib import Path
import shutil
import struct
import subprocess


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
        data = path.read_bytes()
        if len(data) < 64 or data[:2] != b'MZ':
            raise ValueError(f'Malformed CRT library: {path.name}')
        offset = struct.unpack_from('<I', data, 0x3c)[0]
        if (offset + 6 > len(data) or data[offset:offset+4] != b'PE\0\0'
                or struct.unpack_from('<H', data, offset+4)[0] != {'x64': 0x8664, 'arm64': 0xaa64}[arch]):
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
    dlls = sorted(source.glob('*.dll'))
    if not dlls:
        raise RuntimeError('Visual Studio CRT redistributable is empty')
    verify_crt(source, arch)
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
