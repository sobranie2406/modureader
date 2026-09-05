"""Install/uninstall smoke test, ONLY on an ephemeral Windows CI runner."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import time

from native_installers import verify_payload
from windows_runtime import verify_crt


def smoke(installer, arch):
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.name != 'nt':
        raise RuntimeError('This installation smoke test requires a disposable Windows CI runner')
    with tempfile.TemporaryDirectory(prefix='modu-install-check-') as tmp:
        root = Path(tmp)
        install = root / 'Modu'
        subprocess.run([str(installer.resolve()), '/VERYSILENT', '/SUPPRESSMSGBOXES',
                        '/NORESTART', '/SP-', f'/DIR={install}', f'/LOG={root / "install.log"}'],
                       check=True, timeout=180)
        verify_payload(install, 'windows', arch, installed=True)
        verify_crt(install, arch)
        if not (install / 'WINDOWS-RUNTIME.txt').is_file():
            raise RuntimeError('Missing VC++ redistributable provenance')
        sentinel = root / 'user-library-must-survive.txt'
        sentinel.write_text('Synthetic user data outside program files')
        uninstall = install / 'unins000.exe'
        if not uninstall.is_file():
            raise RuntimeError('No registered uninstaller was installed')
        subprocess.run([str(uninstall), '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
                       check=True, timeout=120)
        # Inno's uninstaller uses a child process to remove its own executable.
        # Especially under ARM64 emulation, waiting only for modu.exe races with
        # that child and makes TemporaryDirectory cleanup hit a locked EXE.
        for _ in range(50):
            if not (install / 'modu.exe').exists() and not uninstall.exists():
                break
            time.sleep(1)
        if (install / 'modu.exe').exists() or uninstall.exists() or not sentinel.is_file():
            raise RuntimeError('Uninstall smoke check failed')
    print(f'Windows {arch}: silent installation, payload architecture and uninstall passed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('installer', type=Path)
    parser.add_argument('arch', choices=['x64', 'arm64'])
    args = parser.parse_args()
    smoke(args.installer, args.arch)
