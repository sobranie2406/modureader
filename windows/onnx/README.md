# Windows inference dispatcher

`flutter_onnxruntime_plugin.cpp` and `.h` derive from the MIT-licensed
flutter_onnxruntime **1.8.4** (MASIC AI); see LICENSE. Upstream managers and
runtime still come from the pinned dependency. Changes: serial native worker,
background message codec, platform-thread replies, ordered shutdown.

`windows/cmake/modu_onnx_worker.cmake` replaces the upstream synchronous
dispatcher at build time without modifying the global pub cache. Review this
adapter when updating flutter_onnxruntime. Other platforms are unaffected.

`serial_worker.h` is platform-independent and exercised by
`test/native/OnnxSerialWorkerTest.cpp`. Windows host integration still requires
a Windows build/run; this test alone does not validate WebView2 or Flutter input.
