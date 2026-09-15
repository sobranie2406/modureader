"""Build-wiring guards; these are not Windows native execution tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WindowsOnnxWorkerTest(unittest.TestCase):
    def test_native_dispatcher_is_compiled_in_place_of_upstream(self):
        cmake = (ROOT / 'windows/CMakeLists.txt').read_text()
        self.assertLess(cmake.index('include(flutter/generated_plugins.cmake)'),
                        cmake.index('include(cmake/modu_onnx_worker.cmake)'))
        adapter = (ROOT / 'windows/cmake/modu_onnx_worker.cmake').read_text()
        self.assertIn('list(FILTER MODU_ORT_SOURCES EXCLUDE', adapter)
        self.assertIn('/onnx/flutter_onnxruntime_plugin.cpp', adapter)
        self.assertIn('flutter_onnxruntime: 1.8.4', (ROOT / 'pubspec.yaml').read_text())

    def test_native_decode_infer_encode_run_inside_worker_reply_on_owner(self):
        source = (ROOT / 'windows/onnx/flutter_onnxruntime_plugin.cpp').read_text()
        submit = source.index('worker_->Post(')
        decode = source.index('codec.DecodeMethodCall')
        infer = source.index('plugin_pointer->HandleMethodCall')
        reply = source.index('return [job]')
        self.assertLess(submit, decode)
        self.assertLess(decode, infer)
        self.assertLess(infer, reply)
        self.assertIn('[this] { impl_.reset(); }', source)
        platform = (ROOT / 'windows/onnx/platform_worker.h').read_text()
        self.assertLess(platform.index('worker_.reset()'), platform.index('DestroyWindow(window_)'))

    def test_shutdown_invalidates_handler_without_accessing_stopped_engine(self):
        source = (ROOT / 'windows/onnx/flutter_onnxruntime_plugin.cpp').read_text()
        destructor = source.split('FlutterOnnxruntimePlugin::~FlutterOnnxruntimePlugin() {', 1)[1].split('\n}', 1)[0]
        # Comments document the unsafe API; executable teardown must not call it.
        statements = '\n'.join(line for line in destructor.splitlines()
                               if not line.strip().startswith('//'))
        self.assertNotIn('SetMessageHandler', statements)
        self.assertNotIn('messenger_', statements)
        self.assertLess(statements.index('message_lifetime_.reset()'),
                        statements.index('worker_.reset()'))
        self.assertIn('const std::weak_ptr<int> message_lifetime', source)
        self.assertIn('[plugin_pointer = plugin.get(), message_lifetime]', source)
        self.assertLess(source.index('if (message_lifetime.expired()) return;'),
                        source.index('plugin_pointer->worker_->Post('))

    def test_windows_dart_worker_owns_tokenizer_and_model(self):
        source = (ROOT / 'lib/service/knowledge/onnx_embedding_provider.dart').read_text()
        self.assertIn('BackgroundIsolateBinaryMessenger.ensureInitialized', source)
        self.assertIn('IsolateWorker.start(_windowsEmbeddingMain, token)', source)
        self.assertIn("_windowsWorker!.call('embed'", source)
        self.assertIn("await worker.call('close', null)", source)
        self.assertIn('intraOpNumThreads: 2', source)
        self.assertIn('interOpNumThreads: 1', source)


if __name__ == '__main__':
    unittest.main()
