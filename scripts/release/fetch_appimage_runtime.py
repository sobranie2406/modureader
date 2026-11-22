"""Fetch the pinned official AppImage Type 2 x86-64 launcher."""
import argparse
import hashlib
from pathlib import Path
import urllib.request


RUNTIME_TAG = '20251108'
RUNTIME_URL = f'https://github.com/AppImage/type2-runtime/releases/download/{RUNTIME_TAG}/runtime-x86_64'
RUNTIME_SHA256 = '2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d'


def validate_runtime(payload):
    if hashlib.sha256(payload).hexdigest() != RUNTIME_SHA256:
        raise ValueError('AppImage runtime SHA-256 mismatch')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    path = parser.parse_args().output
    with urllib.request.urlopen(RUNTIME_URL, timeout=60) as response:
        payload = response.read()
    validate_runtime(payload)
    path.write_bytes(payload)
