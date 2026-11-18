"""Execute the OCR bridge's production tensor bounds on a host C++ compiler."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HarmonyOcrNativeTest(unittest.TestCase):
    def test_production_tensor_limits_accept_v5_v6_and_reject_invalid_shapes(self):
        compiler = shutil.which('c++') or shutil.which('clang++')
        if not compiler:
            self.skipTest('C++ compiler unavailable')
        with tempfile.TemporaryDirectory() as temporary:
            executable = Path(temporary) / 'ocr-tensor-test'
            subprocess.run([compiler, '-std=c++17', '-Wall', '-Wextra', '-Werror',
                            '-I', str(ROOT / 'ohos/entry/src/main/cpp'),
                            str(ROOT / 'scripts/harmony/ocr_tensor_test.cpp'),
                            '-o', str(executable)], check=True, capture_output=True, text=True)
            subprocess.run([str(executable)], check=True, capture_output=True, timeout=15)


if __name__ == '__main__':
    unittest.main()
