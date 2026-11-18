"""Stage the pinned OHOS CPU runtime and notices; never install/execute it.

The artifact is built from Microsoft ONNX Runtime by onnxruntime-libs, not a
Microsoft OHOS release. Pin both archive and library bytes before using it.
Use --archive for an already downloaded copy. Source/build provenance is in
embedding_runtime.json; Android/Linux libraries are never substituted.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import shutil
import tempfile
import urllib.request
import zipfile

MANIFEST = Path(__file__).with_name('embedding_runtime.json')
MAX_ARCHIVE = 16 * 1024 * 1024


def runtime_manifest():
    return json.loads(MANIFEST.read_text())


def is_arm64_library(data):
    return (len(data) >= 20 and data[:6] == b'\x7fELF\x02\x01'
            and data[16:20] == b'\x03\x00\xb7\x00')


def verified_files(payload, manifest):
    if len(payload) > MAX_ARCHIVE or hashlib.sha256(payload).hexdigest() != manifest['archiveSha256']:
        raise ValueError('OHOS ONNX Runtime archive checksum mismatch')
    files = {}
    prefix = f'onnxruntime-ohos-arm64-v8a-{manifest["version"]}'
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        if len(archive.infolist()) > 200 or sum(x.file_size for x in archive.infolist()) > 128 * 1024 * 1024:
            raise ValueError('Invalid runtime archive size')
        for item in archive.infolist():
            path = PurePosixPath(item.filename)
            if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != prefix:
                raise ValueError('Invalid runtime archive path')
            if item.is_dir():
                continue
            relative = PurePosixPath(*path.parts[1:]).as_posix()
            if (relative.startswith('include/') and relative.endswith('.h')
                    or relative in ('lib/libonnxruntime.so', 'LICENSE', 'ThirdPartyNotices.txt', 'VERSION_NUMBER')):
                if relative in files:
                    raise ValueError('Duplicate runtime archive file')
                files[relative] = archive.read(item)
    required = ('include/onnxruntime_c_api.h', 'include/onnxruntime_cxx_api.h',
                'include/onnxruntime_cxx_inline.h', 'lib/libonnxruntime.so',
                'LICENSE', 'ThirdPartyNotices.txt', 'VERSION_NUMBER')
    if any(name not in files for name in required):
        raise ValueError('Incomplete OHOS ONNX Runtime archive')
    library = files['lib/libonnxruntime.so']
    if (not is_arm64_library(library)
            or hashlib.sha256(library).hexdigest() != manifest['librarySha256']
            or files['VERSION_NUMBER'].decode().strip() != manifest['version']):
        raise ValueError('Invalid OHOS ONNX Runtime library')
    return files


def prepare(root, archive=None):
    root = Path(root).resolve()
    manifest = runtime_manifest()
    if archive is not None:
        with Path(archive).open('rb') as source:
            payload = source.read(MAX_ARCHIVE + 1)
    else:
        request = urllib.request.Request(manifest['url'], headers={'User-Agent': 'Modu-OHOS-runtime-build'})
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = response.read(MAX_ARCHIVE + 1)
    files = verified_files(payload, manifest)
    base = root / 'build/ohos-embedding'
    base.mkdir(parents=True, exist_ok=True)
    target = base / 'onnxruntime'
    with tempfile.TemporaryDirectory(prefix='.runtime-', dir=base) as temporary:
        staged = Path(temporary)
        for name, content in files.items():
            destination = staged / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(content)
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(staged, target)
    library = root / 'ohos/entry/libs/arm64-v8a/libonnxruntime.so'
    library.parent.mkdir(parents=True, exist_ok=True)
    library.write_bytes(files['lib/libonnxruntime.so'])
    notices = root / 'ohos/entry/src/main/resources/rawfile/onnxruntime'
    notices.mkdir(parents=True, exist_ok=True)
    for name in ('LICENSE', 'ThirdPartyNotices.txt'):
        (notices / name).write_bytes(files[name])
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path.cwd())
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    prepare(args.root, args.archive)
    print('Verified OHOS arm64 ONNX Runtime staged')
