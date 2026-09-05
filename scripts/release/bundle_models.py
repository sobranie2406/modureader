"""Fetch pinned public model assets at BUILD time, never at app startup."""
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


def fetch(job):
    model, item = job
    destination = ASSETS / model['id'] / item['name']
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
            print('Bundled:', model['id'], item['name'], item['size'], flush=True)
            return
        except Exception:
            if temporary.exists(): temporary.unlink()
            if attempt == 2: raise
            time.sleep(attempt + 1)


def verify_directory(assets):
    expected = manifest()
    packaged_manifest = assets / 'assets/models/embeddings/manifest.json'
    if not packaged_manifest.is_file() or json.loads(packaged_manifest.read_text()) != expected:
        raise ValueError('Missing or mismatched bundled model manifest')
    for model in expected['models']:
        for item in model['files']:
            path = assets / 'assets/models/embeddings' / model['id'] / item['name']
            if not valid(path, item):
                raise ValueError(f'Missing/corrupt bundled model asset: {model["id"]}/{item["name"]}')


def verify_archive(archive, prefix):
    expected = manifest()
    base = prefix + 'assets/models/embeddings/'
    if json.loads(archive.read(base + 'manifest.json')) != expected:
        raise ValueError('Mismatched archived model manifest')
    for model in expected['models']:
        for item in model['files']:
            name = base + model['id'] + '/' + item['name']
            if archive.getinfo(name).file_size != item['size']:
                raise ValueError(f'Wrong bundled model size: {name}')
            with archive.open(name) as source:
                if hashlib.file_digest(source, 'sha256').hexdigest() != item['sha256']:
                    raise ValueError(f'Wrong bundled model hash: {name}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    jobs = [(m, f) for m in manifest()['models'] for f in m['files']]
    if not args.verify_only:
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(fetch, jobs))
    verify_directory(ROOT)
    print('All four bundled models and tokenizers verified; total bytes:', sum(f['size'] for _, f in jobs))
