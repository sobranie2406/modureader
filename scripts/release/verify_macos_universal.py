"""Mount, launch and normally close the universal app only on disposable CI Macs."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import time
from native_installers import command, verify_payload
from verify_mobile import verify_apple_bundle


def verify(image, arch):
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Requires an ephemeral macOS CI runner')
    expected = 'arm64' if arch == 'arm64' else 'x86_64'
    if command('uname', '-m') != expected:
        raise ValueError('Native architecture mismatch')
    with tempfile.TemporaryDirectory(prefix='modu-universal-check-') as tmp:
        mount = Path(tmp) / 'mounted'
        mount.mkdir()
        command('hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', mount, image)
        try:
            verify_payload(mount, 'macos', 'universal')
            app = mount / 'Modu.app'
            version = next(line.split(':', 1)[1].strip() for line in
                           Path('pubspec.yaml').read_text().splitlines() if line.startswith('version:'))
            verify_apple_bundle(app, version.split('+')[0])
            process = subprocess.Popen([str(app / 'Contents/MacOS/Modu')])
            try:
                time.sleep(15)
                if process.poll() is not None:
                    raise RuntimeError('Universal app exited during startup')
                command('osascript', '-e', 'tell application "Modu" to quit')
                if process.wait(timeout=45) != 0:
                    raise RuntimeError('Universal app failed normal close')
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=15)
        finally:
            command('hdiutil', 'detach', mount)
    print(f'Universal macOS signature, version and native {arch} launch/close passed')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('image', type=Path)
    parser.add_argument('arch', choices=['arm64', 'x64'])
    args = parser.parse_args()
    verify(args.image.resolve(), args.arch)
