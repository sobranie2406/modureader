"""Architecture checks must reject cross-labelled or malformed native binaries."""
import importlib.util
import hashlib
from pathlib import Path
import struct
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "release_package", Path(__file__).resolve().parents[1] / "scripts/release/package.py")
release_package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_package)


class ArchitectureTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="modu-package-test-")
        self.addCleanup(self.directory.cleanup)
        self.binary = Path(self.directory.name) / "binary"

    def test_windows_x64_and_arm64_are_not_interchangeable(self):
        for arch, machine in {"x64": 0x8664, "arm64": 0xAA64}.items():
            data = bytearray(512)
            data[:2] = b"MZ"
            struct.pack_into("<I", data, 0x3C, 128)
            data[128:132] = b"PE\0\0"
            struct.pack_into("<H", data, 132, machine)
            self.binary.write_bytes(data)
            release_package.verify(self.binary, "windows", arch)
            with self.assertRaises(AssertionError):
                release_package.verify(self.binary, "windows", "arm64" if arch == "x64" else "x64")

    def test_linux_x64_and_arm64_are_not_interchangeable(self):
        for arch, machine in {"x64": 62, "arm64": 183}.items():
            data = bytearray(64)
            data[:5] = b"\x7fELF\x02"
            struct.pack_into("<H", data, 18, machine)
            self.binary.write_bytes(data)
            release_package.verify(self.binary, "linux", arch)
            with self.assertRaises(AssertionError):
                release_package.verify(self.binary, "linux", "arm64" if arch == "x64" else "x64")

    def test_text_file_cannot_pass_as_a_linux_program(self):
        self.binary.write_text("not a program")
        with self.assertRaises(AssertionError):
            release_package.verify(self.binary, "linux", "arm64")

    def test_missing_binary_is_an_error(self):
        with self.assertRaises(FileNotFoundError):
            release_package.verify(self.binary, "linux", "x64")

    def test_checksums_use_portable_lf_bytes(self):
        self.binary.write_bytes(b"Modu release artifact")
        release_package.write_checksum(self.binary)
        checksum = self.binary.with_name(self.binary.name + ".sha256").read_bytes()
        digest = hashlib.sha256(self.binary.read_bytes()).hexdigest()
        self.assertEqual(checksum, f"{digest}  binary\n".encode("utf-8"))
        self.assertNotIn(b"\r", checksum)


if __name__ == "__main__":
    unittest.main()
