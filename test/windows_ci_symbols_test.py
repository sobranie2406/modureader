"""Never symbolize an RVA using a different image signature."""
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/release'))
from symbolize_windows_ci import signature


class ImageSignatureTest(unittest.TestCase):
    def test_signature_matches_crash_recorder_fields(self):
        data = bytearray(64 + 88)
        data[:2] = b'MZ'
        struct.pack_into('<I', data, 60, 64)
        data[64:68] = b'PE\0\0'
        struct.pack_into('<I', data, 64 + 8, 0x6AA4A233)
        struct.pack_into('<I', data, 64 + 80, 0x7BA000)
        with tempfile.TemporaryDirectory() as root:
            binary = Path(root) / 'fixture.dll'
            binary.write_bytes(data)
            self.assertEqual(signature(binary), '6aa4a233-7ba000')
            struct.pack_into('<I', data, 64 + 8, 0x1234)
            binary.write_bytes(data)
            self.assertNotEqual(signature(binary), '6aa4a233-7ba000')

    def test_malformed_images_are_not_candidates(self):
        with tempfile.TemporaryDirectory() as root:
            binary = Path(root) / 'fixture.dll'
            for data in (b'', b'MZ', b'x' * 200, b'MZ' + b'\0' * 62):
                binary.write_bytes(data)
                self.assertIsNone(signature(binary))


if __name__ == '__main__':
    unittest.main()
