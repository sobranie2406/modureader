"""Offline provenance/packaging and actual C++ pooling regression checks."""
import hashlib
from io import BytesIO
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/harmony'))
from prepare_embedding_runtime import is_arm64_library, prepare, runtime_manifest, verified_files

ELF = bytes.fromhex('7f454c460201010000000000000000000300b700') + bytes(44)


def fixture(extra=None, library=ELF):
    files = {
        'include/onnxruntime_c_api.h': b'header',
        'include/onnxruntime_cxx_api.h': b'header',
        'include/onnxruntime_cxx_inline.h': b'header',
        'lib/libonnxruntime.so': library,
        'VERSION_NUMBER': b'1.27.0\n',
        'LICENSE': b'MIT fixture',
        'ThirdPartyNotices.txt': b'Notices fixture',
    }
    files.update(extra or {})
    output = BytesIO()
    with zipfile.ZipFile(output, 'w') as archive:
        for name, data in files.items():
            archive.writestr(f'onnxruntime-ohos-arm64-v8a-1.27.0/{name}', data)
    data = output.getvalue()
    return data, {'version': '1.27.0', 'archiveSha256': hashlib.sha256(data).hexdigest(),
                  'librarySha256': hashlib.sha256(library).hexdigest()}


class HarmonyEmbeddingTest(unittest.TestCase):
    def test_runtime_is_version_and_content_pinned_to_ohos_not_android(self):
        manifest = runtime_manifest()
        self.assertRegex(manifest['url'], r'^https://huggingface\.co/csukuangfj2/onnxruntime-libs/'
                         r'resolve/[0-9a-f]{40}/onnxruntime-ohos-arm64-v8a-1\.27\.0\.zip$')
        self.assertEqual(manifest['target'], 'ohos-arm64')
        self.assertRegex(manifest['archiveSha256'], r'^[0-9a-f]{64}$')
        self.assertRegex(manifest['librarySha256'], r'^[0-9a-f]{64}$')
        profile = json.loads((ROOT / 'ohos/entry/build-profile.json5').read_text())
        self.assertEqual(profile['buildOption']['externalNativeOptions']['abiFilters'], ['arm64-v8a'])
        self.assertIn('**/libonnxruntime.so', profile['buildOption']['nativeLib']['debugSymbol']['exclude'])

    def test_archive_and_library_checksums_are_both_enforced(self):
        payload, manifest = fixture()
        self.assertEqual(verified_files(payload, manifest)['lib/libonnxruntime.so'], ELF)
        with self.assertRaisesRegex(ValueError, 'archive checksum'):
            verified_files(payload + b'changed', manifest)
        manifest['librarySha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'Invalid OHOS'):
            verified_files(payload, manifest)

    def test_archive_cannot_escape_root_or_install_another_abi(self):
        payload, manifest = fixture({'../outside': b'bad'})
        with self.assertRaisesRegex(ValueError, 'archive path'):
            verified_files(payload, manifest)
        wrong = ELF[:18] + b'\x3e\x00' + ELF[20:]
        payload, manifest = fixture(library=wrong)
        with self.assertRaisesRegex(ValueError, 'Invalid OHOS'):
            verified_files(payload, manifest)
        self.assertFalse(is_arm64_library(b''))

    def test_offline_prepare_stages_runtime_headers_and_license_for_hap(self):
        payload, manifest = fixture()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'runtime.zip'
            source.write_bytes(payload)
            with patch('prepare_embedding_runtime.runtime_manifest', return_value=manifest):
                target = prepare(root, source)
                self.assertEqual(prepare(root, source), target)
            self.assertEqual((target / 'include/onnxruntime_cxx_api.h').read_bytes(), b'header')
            self.assertEqual((root / 'ohos/entry/libs/arm64-v8a/libonnxruntime.so').read_bytes(), ELF)
            self.assertEqual((root / 'ohos/entry/src/main/resources/rawfile/onnxruntime/LICENSE').read_bytes(),
                             b'MIT fixture')

    def test_native_pooling_runs_the_production_cpp_implementation(self):
        compiler = shutil.which('c++') or shutil.which('clang++')
        if not compiler:
            self.skipTest('C++ compiler unavailable')
        with tempfile.TemporaryDirectory() as temporary:
            executable = Path(temporary) / 'embedding-math-test'
            subprocess.run([compiler, '-std=c++17', '-Wall', '-Wextra', '-Werror',
                            '-I', str(ROOT / 'ohos/entry/src/main/cpp'),
                            str(ROOT / 'scripts/harmony/embedding_math_test.cpp'),
                            '-o', str(executable)], check=True, capture_output=True, text=True)
            subprocess.run([str(executable)], check=True, capture_output=True, timeout=15)


if __name__ == '__main__':
    unittest.main()
