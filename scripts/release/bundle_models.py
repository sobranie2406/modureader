"""Fetch pinned models for native TESTS; release apps contain only the catalogue."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'assets/models/embeddings'


def manifest():
    return json.loads((ASSETS / 'manifest.json').read_text())


def valid(path, item):
    if not path.is_file() or path.stat().st_size != item['size']:
        return False
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest() == item['sha256']


def fetch(job, output):
    model, item = job
    destination = output / model['id'] / item['name']
    destination.parent.mkdir(parents=True, exist_ok=True)
    if valid(destination, item):
        print('Verified cached asset:', model['id'], item['name'], flush=True)
        return
    url = f"https://huggingface.co/{model['repository']}/resolve/{model['revision']}/{item['path']}"
    temporary = destination.with_suffix(destination.suffix + '.part')
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=120) as response, temporary.open('wb') as target:
                shutil.copyfileobj(response, target)
            if not valid(temporary, item):
                raise ValueError('Downloaded model hash/size mismatch')
            temporary.replace(destination)
            print('Test fixture:', model['id'], item['name'], item['size'], flush=True)
            return
        except Exception:
            if temporary.exists(): temporary.unlink()
            if attempt == 2: raise
            time.sleep(attempt + 1)


def verify_directory(assets):
    expected = manifest()
    packaged_manifest = assets / 'assets/models/embeddings/manifest.json'
    if not packaged_manifest.is_file() or json.loads(packaged_manifest.read_text()) != expected:
        raise ValueError('Missing or mismatched model download manifest')
    extras = [p for p in packaged_manifest.parent.rglob('*')
              if p.is_file() and p != packaged_manifest]
    if extras:
        raise ValueError('Release must not bundle model weights or tokenizers')


def verify_archive(archive, prefix):
    expected = manifest()
    base = prefix + 'assets/models/embeddings/'
    if json.loads(archive.read(base + 'manifest.json')) != expected:
        raise ValueError('Mismatched archived model manifest')
    extras = [name for name in archive.namelist()
              if name.startswith(base) and not name.endswith('/')
              and name != base + 'manifest.json']
    if extras:
        raise ValueError('Release must not bundle model weights or tokenizers')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/model-test-fixtures')
    args = parser.parse_args()
    jobs = [(m, f) for m in manifest()['models'] for f in m['files']]
    if not args.verify_only:
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(lambda job: fetch(job, args.output), jobs))
    for model, item in jobs:
        if not valid(args.output / model['id'] / item['name'], item):
            raise ValueError('Missing or corrupt native test fixture')
    print('Four native test fixtures verified (not packaged); total bytes:', sum(f['size'] for _, f in jobs))
