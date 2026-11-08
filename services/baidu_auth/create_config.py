"""Run interactively; secrets never go into arguments, shell history or logs."""
import getpass
import json
import os
from pathlib import Path
import secrets
import sys


def main():
    path = Path(sys.argv[1]).expanduser()
    if path.exists():
        raise SystemExit('File already exists; keep existing encryption/session keys.')
    app_key = getpass.getpass('Baidu AppKey (hidden): ').strip()
    app_secret = getpass.getpass('Rotated Baidu SecretKey (hidden): ').strip()
    if not app_key or not app_secret:
        raise SystemExit('Both fields are required.')
    os.umask(0o077)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open('x') as f:
        json.dump(dict(app_key=app_key, app_secret=app_secret,
                       encryption_key=secrets.token_hex(32),
                       origin_secret=secrets.token_urlsafe(32)), f)
    print('Saved protected configuration. Do not paste its contents into chat.')

if __name__ == '__main__':
    main()
