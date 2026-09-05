"""Architecture checks must reject cross-labelled or malformed native binaries."""
import importlib.util
import hashlib
from pathlib import Path
import struct
import tempfile
import unittest
import sys
import plistlib
import json
import zipfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/release'))
from verify_mobile import apple_version, verify_android_elf, verify_apple_bundle
from windows_runtime import prepare_windows_runtime, verify_crt, pe_imports
import bundle_models


class BundledModelsTest(unittest.TestCase):
    def test_manifest_pins_all_four_models_and_tokenizers(self):
        models = bundle_models.manifest()['models']
        self.assertEqual(len(models), 4)
        self.assertEqual({m['id'] for m in models}, {
            'all-MiniLM-L6-v2', 'bge-small-en-v1.5',
            'bge-small-zh-v1.5', 'multilingual-e5-small'})
        for model in models:
            self.assertRegex(model['revision'], r'^[0-9a-f]{40}$')
            self.assertEqual({f['name'] for f in model['files']},
                             {'model_quantized.onnx', 'tokenizer.json'})
            for item in model['files']:
                self.assertGreater(item['size'], 0)
                self.assertRegex(item['sha256'], r'^[0-9a-f]{64}$')

    def test_missing_or_corrupt_assets_cannot_be_packaged(self):
        payload = b'public test model'
        manifest = {'models': [{'id': 'test', 'files': [{
            'name': 'model_quantized.onnx', 'size': len(payload),
            'sha256': hashlib.sha256(payload).hexdigest()}]}]}
        with tempfile.TemporaryDirectory() as tmp, patch.object(bundle_models, 'manifest', return_value=manifest):
            root = Path(tmp)
            base = root / 'assets/models/embeddings'
            base.mkdir(parents=True)
            (base / 'manifest.json').write_text(json.dumps(manifest))
            with self.assertRaises(ValueError):
                bundle_models.verify_directory(root)
            (base / 'test').mkdir()
            model = base / 'test/model_quantized.onnx'
            model.write_bytes(payload)
            bundle_models.verify_directory(root)
            for content in (payload, b'x' * len(payload)):
                model.write_bytes(content)
                with zipfile.ZipFile(root / 'assets.zip', 'w') as archive:
                    for asset in base.rglob('*'):
                        if asset.is_file():
                            archive.write(asset, 'flutter_assets/' + asset.relative_to(root).as_posix())
                with zipfile.ZipFile(root / 'assets.zip') as archive:
                    if content == payload:
                        bundle_models.verify_archive(archive, 'flutter_assets/')
                    else:
                        with self.assertRaises(ValueError):
                            bundle_models.verify_archive(archive, 'flutter_assets/')
                        with self.assertRaises(ValueError):
                            bundle_models.verify_directory(root)

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
        self.assertEqual(native.deb_version('0.1.0-beta.1', 6326), '0.1.0~beta.1-6326')
        with self.assertRaises(ValueError):
            native.deb_version('0.1.0-beta.1', 'bad\nrevision')

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


class CompatibilityTest(unittest.TestCase):
    def test_arm64_redist_excludes_only_unneeded_foreign_compatibility_dll(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / 'redist/arm64/Microsoft.VC143.CRT'
            source.mkdir(parents=True)
            bundle = root / 'bundle'
            bundle.mkdir()
            data = bytearray(1024)
            data[:2] = b'MZ'
            struct.pack_into('<I', data, 0x3c, 128)
            data[128:132] = b'PE\0\0'
            struct.pack_into('<HH', data, 132, 0xaa64, 1)
            struct.pack_into('<H', data, 148, 240)
            struct.pack_into('<H', data, 152, 0x20b)
            struct.pack_into('<I', data, 260, 16)
            struct.pack_into('<IIII', data, 400, 512, 0x1000, 512, 512)
            for name in ('msvcp140.dll', 'msvcp140_1.dll', 'vcruntime140.dll'):
                (source / name).write_bytes(data)
            struct.pack_into('<H', data, 132, 0x8664)
            (source / 'vcruntime140_1.dll').write_bytes(data)
            prepare_windows_runtime(bundle, 'arm64', root / 'redist')
            self.assertFalse((bundle / 'vcruntime140_1.dll').exists())
            verify_crt(bundle, 'arm64')
            # Both ordinary and delay imports must prevent unsafe exclusion.
            struct.pack_into('<H', data, 132, 0xaa64)
            for directory, name_offset in [(1, 12), (13, 4)]:
                image = bytearray(data)
                struct.pack_into('<II', image, 264 + directory * 8, 0x1000, 64)
                if directory == 13:
                    struct.pack_into('<I', image, 512, 1)
                struct.pack_into('<I', image, 512 + name_offset, 0x1080)
                image[640:659] = b'vcruntime140_1.dll\0\0'
                (bundle / 'modu.exe').write_bytes(image)
                self.assertIn('vcruntime140_1.dll', pe_imports(bundle / 'modu.exe'))
                with self.assertRaisesRegex(ValueError, 'Required CRT'):
                    prepare_windows_runtime(bundle, 'arm64', root / 'redist')

    def test_apple_prerelease_does_not_become_four_components(self):
        self.assertEqual(apple_version('0.1.0-beta.1+6325'), '0.1.0')
        self.assertEqual(apple_version('1.2.3'), '1.2.3')
        with self.assertRaises(ValueError):
            apple_version('0.1.0.1')

    def test_invalid_apple_bundle_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp)
            for version in ('0.1.0.1', '0.1.0-beta.1', '1.0.0'):
                (app / 'Info.plist').write_bytes(plistlib.dumps({
                    'CFBundleShortVersionString': version, 'CFBundleVersion': '6325'}))
                with self.assertRaises(ValueError):
                    verify_apple_bundle(app, '0.1.0-beta.1')
            (app / 'Info.plist').write_bytes(plistlib.dumps({
                'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '6325'}))
            verify_apple_bundle(app, '0.1.0-beta.1')

    def test_android_16kb_load_segments_required_for_both_architectures(self):
        for machine in (62, 183):
            data = bytearray(120)
            data[:6] = b'\x7fELF\x02\x01'
            struct.pack_into('<H', data, 18, machine)
            struct.pack_into('<Q', data, 32, 64)
            struct.pack_into('<HH', data, 54, 56, 1)
            for alignment in (4096, 8192, 16384, 65536):
                struct.pack_into('<IIQQQQQQ', data, 64, 1, 5, 0, 0, 0, 120, 120, alignment)
                if alignment < 16384:
                    with self.assertRaisesRegex(ValueError, '16 KB'):
                        verify_android_elf(data, machine)
                else:
                    verify_android_elf(data, machine)
            with self.assertRaisesRegex(ValueError, 'architecture'):
                verify_android_elf(data, 183 if machine == 62 else 62)
            struct.pack_into('<Q', data, 80, 4096)  # Misaligned file offset.
            with self.assertRaisesRegex(ValueError, '16 KB'):
                verify_android_elf(data, machine)

    def test_android_malformed_or_empty_program_headers_are_rejected(self):
        for data in (b'', b'not an ELF', b'\x7fELF\x02\x01' + bytes(58)):
            with self.assertRaises(ValueError):
                verify_android_elf(data, 62)

    def test_windows_crt_is_app_local_and_architecture_checked(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for arch, machine in [('x64', 0x8664), ('arm64', 0xaa64)]:
                source = root / '14.44.35211' / arch / 'Microsoft.VC143.CRT'
                source.mkdir(parents=True)
                bundle = root / arch
                bundle.mkdir()
                data = bytearray(512)
                data[:2] = b'MZ'
                struct.pack_into('<I', data, 0x3c, 128)
                data[128:132] = b'PE\0\0'
                struct.pack_into('<H', data, 132, machine)
                for name in ['msvcp140.dll', 'msvcp140_1.dll', 'vcruntime140.dll', 'vcruntime140_1.dll']:
                    (source / name).write_bytes(data)
                prepare_windows_runtime(bundle, arch, root / '14.44.35211')
                verify_crt(bundle, arch)
                self.assertIn('SHA-256:', (bundle / 'WINDOWS-RUNTIME.txt').read_text())
                with self.assertRaises(ValueError):
                    verify_crt(bundle, 'arm64' if arch == 'x64' else 'x64')
                (bundle / 'msvcp140.dll').unlink()
                with self.assertRaisesRegex(ValueError, 'Missing'):
                    verify_crt(bundle, arch)


if __name__ == "__main__":
    unittest.main()
