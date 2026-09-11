"""Install/uninstall smoke test, ONLY on an ephemeral Windows CI runner."""
import argparse
import ctypes
import os
from pathlib import Path
import subprocess
import tempfile
import time

from native_installers import verify_payload
from windows_runtime import verify_crt


def verify_window_close(executable):
    """Exercise the actual installed runner on a disposable Windows account."""
    user32 = ctypes.windll.user32
    callback_type = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p,
                                     ctypes.c_void_p)
    user32.GetWindowThreadProcessId.argtypes = [ctypes.c_void_p,
                                               ctypes.POINTER(ctypes.c_ulong)]
    user32.IsWindowVisible.argtypes = [ctypes.c_void_p]
    user32.PostMessageW.argtypes = [ctypes.c_void_p, ctypes.c_uint,
                                   ctypes.c_size_t, ctypes.c_ssize_t]
    for cycle in range(3):
        process = subprocess.Popen([str(executable)], cwd=executable.parent)
        try:
            window = None
            deadline = time.monotonic() + 40
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f'App exited before close: {process.returncode}')
                windows = []

                @callback_type
                def collect(hwnd, _):
                    pid = ctypes.c_ulong()
                    user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
                    if pid.value == process.pid and user32.IsWindowVisible(hwnd):
                        windows.append(hwnd)
                    return True

                user32.EnumWindows(collect, 0)
                if windows:
                    window = windows[0]
                    break
                time.sleep(0.5)
            if window is None:
                raise RuntimeError('Installed app did not show a window')
            time.sleep(5)  # Allow Dart and WebView environment startup to finish.
            if not user32.PostMessageW(window, 0x0010, 0, 0):  # WM_CLOSE
                raise RuntimeError('Could not request a normal window close')
            code = process.wait(timeout=50)
            if code != 0:
                raise RuntimeError(f'Normal close crashed: exit={code:#x}')
            print(f'Windows installed app: launch/normal-close cycle {cycle + 1} passed')
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=15)


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
        if arch == 'x64':
            verify_window_close(install / 'modu.exe')
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
