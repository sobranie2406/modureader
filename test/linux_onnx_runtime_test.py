"""Fresh Linux packages reuse their verified runtime; old bundles remain repairable."""
import hashlib
import io
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/release'))
import native_installers as native

ROOT = Path(__file__).resolve().parents[1]


class LinuxOnnxBuildLinkTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which('cmake'), 'CMake is required for the build-link fixture')
    def test_build_soname_and_runner_search_path_exist_before_plugin_configuration(self):
        source = (ROOT / 'linux/CMakeLists.txt').read_text()
        start = source.index('set(MODU_ORT_LINK_DIR ')
        end = source.index('# The plugin\'s unchecked', start)
        self.assertLess(start, source.index('include(flutter/generated_plugins.cmake)'))
        binding = next(line for line in source.splitlines()
                       if line.startswith('set(ONNXRUNTIME_LIBRARY '))
        for arch in ('x64', 'arm64'):
            with self.subTest(arch=arch), tempfile.TemporaryDirectory(prefix='modu ort link ') as temporary:
                root = Path(temporary).resolve()
                library = root / f'runtimes/linux-{arch}/native/libonnxruntime.so'
                library.parent.mkdir(parents=True)
                library.write_bytes(b'configure-only fixture')
                (root / 'main.c').write_text('int main(void) { return 0; }\n')
                (root / 'CMakeLists.txt').write_text(
                    'cmake_minimum_required(VERSION 3.14)\nproject(OrtLinkSmoke C)\n'
                    'set(BINARY_NAME smoke)\nadd_executable(smoke main.c)\n'
                    f'set(MODU_ORT_NATIVE_LIBRARY "{library}")\n' + source[start:end] + binding + '\n'
                    'get_target_property(flags smoke LINK_OPTIONS)\n'
                    'file(WRITE "${CMAKE_BINARY_DIR}/flags.txt" "${flags}\\n${ONNXRUNTIME_LIBRARY}")\n')
                build = root / 'build'
                result = subprocess.run(['cmake', '-S', str(root), '-B', str(build)],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                link = build / 'modu-onnxruntime/libonnxruntime.so.1'
                self.assertTrue(link.is_symlink())
                self.assertEqual(link.resolve(), library)
                self.assertEqual((build / 'flags.txt').read_text().splitlines(), [
                    f'LINKER:-rpath-link,{link.parent}', str(link)])


class LinuxOnnxRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / 'app'
        (self.app / 'lib').mkdir(parents=True)
        (self.app / 'modu').write_bytes(b'app')
        (self.app / 'lib/plugin.so').write_bytes(b'plugin')
        (self.app / 'lib/libapp.so').write_bytes(b'AOT')
        self.library = self.app / 'lib/libonnxruntime.so.1.22.0'
        self.record = self.app / 'LINUX-RUNTIME.txt'
        self.payloads = {}
        for arch, machine in [('x64', 62), ('arm64', 183)]:
            data = bytearray(64)
            data[:6] = b'\x7fELF\x02\x01'
            struct.pack_into('<H', data, 18, machine)
            self.payloads[arch] = bytes(data)
        patcher = patch.object(native, 'LINUX_ONNX_LIBRARY_SHA256', {
            arch: hashlib.sha256(data).hexdigest() for arch, data in self.payloads.items()})
        patcher.start()
        self.addCleanup(patcher.stop)

    def prepare(self, arch):
        with patch.object(native, 'command') as command:
            native.prepare_linux_runtime(self.app, arch, self.root)
        return command

    def archive(self, arch, symbolic=False):
        upstream = 'x64' if arch == 'x64' else 'aarch64'
        name = f'onnxruntime-linux-{upstream}-1.22.0/lib/{self.library.name}'
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode='w:gz') as tar:
            info = tarfile.TarInfo(name)
            data = self.payloads[arch]
            info.size = len(data)
            if symbolic:
                info.type = tarfile.SYMTYPE
                info.linkname = '/outside'
                tar.addfile(info)
            else:
                tar.addfile(info, io.BytesIO(data))
        data = buffer.getvalue()
        return data, (upstream, hashlib.sha256(data).hexdigest())

    def test_fresh_payload_reused_offline_for_both_architectures(self):
        for arch in self.payloads:
            with self.subTest(arch=arch):
                self.library.write_bytes(self.payloads[arch])
                self.record.write_text('Package SHA-256: verified NuGet package\n')
                with patch.object(native.urllib.request, 'urlopen') as download:
                    command = self.prepare(arch)
                download.assert_not_called()
                self.assertEqual(self.library.read_bytes(), self.payloads[arch])
                self.assertEqual((self.app / 'lib/libonnxruntime.so.1').readlink(), Path(self.library.name))
                self.assertEqual((self.app / 'lib/libonnxruntime.so').readlink(), Path('libonnxruntime.so.1'))
                self.assertEqual(command.call_args_list[0].args,
                                 ('patchelf', '--set-rpath', '$ORIGIN', self.app / 'lib/plugin.so'))
                self.assertEqual(command.call_args_list[1].args,
                                 ('patchelf', '--set-rpath', '$ORIGIN/lib', self.app / 'modu'))
                self.assertIn('verified NuGet package', self.record.read_text())

    def test_bad_payload_is_rejected_without_download(self):
        self.library.write_bytes(b'corrupt')
        with patch.object(native.urllib.request, 'urlopen') as download:
            with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                self.prepare('x64')
        download.assert_not_called()

    def test_wrong_architecture_is_rejected_even_if_hash_is_allowed(self):
        self.library.write_bytes(self.payloads['arm64'])
        with patch.dict(native.LINUX_ONNX_LIBRARY_SHA256, x64=hashlib.sha256(self.library.read_bytes()).hexdigest()):
            with self.assertRaisesRegex(ValueError, 'architecture'):
                self.prepare('x64')

    def test_missing_fresh_payload_cannot_fall_back_to_download(self):
        self.record.write_text('Package SHA-256: verified NuGet package\n')
        with patch.object(native.urllib.request, 'urlopen') as download:
            with self.assertRaisesRegex(ValueError, 'payload is missing'):
                self.prepare('x64')
        download.assert_not_called()

    def test_versioned_symlink_cannot_pass_as_real_payload(self):
        self.library.symlink_to('missing')
        with self.assertRaisesRegex(ValueError, 'real ONNX'):
            self.prepare('x64')

    def test_historical_archive_mirror_preserves_hash_check_for_both_architectures(self):
        for arch in self.payloads:
            with self.subTest(arch=arch):
                if self.library.exists():
                    self.library.unlink()
                data, pin = self.archive(arch)
                with patch.dict(native.LINUX_ONNX_ARCHIVES, {arch: pin}), patch.object(
                        native.urllib.request, 'urlopen', side_effect=[
                            urllib.error.HTTPError('upstream', 404, 'missing', None, None),
                            io.BytesIO(data)]) as download:
                    self.prepare(arch)
                self.assertEqual(self.library.read_bytes(), self.payloads[arch])
                self.assertEqual(download.call_count, 2)
                self.assertTrue(download.call_args.args[0].startswith('https://dl.photoprism.app/onnx/runtime/v1.22.0/'))
                self.assertIn('https://dl.photoprism.app/', self.record.read_text())

    def test_historical_bad_archive_hash_does_not_try_another_source(self):
        with patch.object(native.urllib.request, 'urlopen', return_value=io.BytesIO(b'bad archive')) as download:
            with self.assertRaisesRegex(ValueError, 'archive checksum mismatch'):
                self.prepare('x64')
        self.assertEqual(download.call_count, 1)
        self.assertFalse(self.library.exists())

    def test_historical_archive_link_member_is_rejected(self):
        data, pin = self.archive('x64', symbolic=True)
        with patch.dict(native.LINUX_ONNX_ARCHIVES, x64=pin), patch.object(
                native.urllib.request, 'urlopen', return_value=io.BytesIO(data)):
            with self.assertRaisesRegex(ValueError, 'real ONNX'):
                self.prepare('x64')


if __name__ == '__main__':
    unittest.main()
