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

native_spec = importlib.util.spec_from_file_location(
    'native_installers', Path(__file__).resolve().parents[1] / 'scripts/release/native_installers.py')
native = importlib.util.module_from_spec(native_spec)
native_spec.loader.exec_module(native)


class NativeInstallerTest(unittest.TestCase):
    def test_debian_prerelease_sorts_before_final(self):
        self.assertEqual(native.deb_version('0.1.0-beta.1'), '0.1.0~beta.1')
        self.assertEqual(native.deb_version('1.0.0'), '1.0.0')

    def test_invalid_versions_cannot_inject_installer_configuration(self):
        for version in ('../x', 'v1.0.0', '1.0.0\nAppId=Other', '1.0.0;evil'):
            with self.assertRaises(ValueError):
                native.validate_version(version)

    def test_windows_native_os_restrictions_and_user_data_safety(self):
        for arch, rule in [('x64', 'x64os'), ('arm64', 'arm64')]:
            script = native.windows_script(Path('payload'), arch, '0.1.0-beta.1', Path('out'))
            self.assertIn(f'ArchitecturesAllowed={rule}\n', script)
            self.assertIn(f'ArchitecturesInstallIn64BitMode={rule}\n', script)
            self.assertIn('PrivilegesRequired=lowest', script)
            self.assertNotIn('[UninstallDelete]', script)
            self.assertIn('skipifsilent', script)

    def test_native_checksum_is_portable(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'package.deb'
            path.write_bytes(b'native package')
            native.checksum(path)
            self.assertEqual(path.with_suffix('.deb.sha256').read_bytes(),
                             f'{hashlib.sha256(b"native package").hexdigest()}  package.deb\n'.encode())

    def test_only_installed_uninstaller_engine_can_have_different_architecture(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('LICENSE', 'NOTICE', 'SOURCE.txt'):
                (root / name).write_text('notice')
            data = bytearray(512)
            data[:2] = b'MZ'
            struct.pack_into('<I', data, 0x3c, 128)
            data[128:132] = b'PE\0\0'
            struct.pack_into('<H', data, 132, 0xaa64)
            for name in ('modu.exe', 'flutter_windows.dll', 'onnxruntime.dll', 'tokenizers_ffi.dll'):
                (root / name).write_bytes(data)
            struct.pack_into('<H', data, 132, 0x14c)
            (root / 'unins000.exe').write_bytes(data)
            native.verify_payload(root, 'windows', 'arm64', installed=True)
            with self.assertRaises(ValueError):
                native.verify_payload(root, 'windows', 'arm64')
            (root / 'wrong.dll').write_bytes(data)
            with self.assertRaises(ValueError):
                native.verify_payload(root, 'windows', 'arm64', installed=True)


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
