# Windows inference dispatcher

## Current: Modu 1.2.0+10082

This note describes the stable Modu publishing repository's `v1.2.0` commit
`77dc238fb2ae2ce02455bd80c500ee9fd140f219`, not uncommitted application changes.
The Windows release matrix includes ARM64 and x64 installers.

`flutter_onnxruntime_plugin.cpp` and `.h` derive from the MIT-licensed
flutter_onnxruntime **1.8.4** (MASIC AI); see [LICENSE](LICENSE). Upstream managers
and runtime still come from the pinned dependency. Changes: serial native worker,
background message codec, platform-thread replies and ordered shutdown.

`windows/cmake/modu_onnx_worker.cmake` replaces the upstream synchronous
dispatcher at build time without modifying the global pub cache. Review this
adapter when updating flutter_onnxruntime. This replacement is Windows-specific;
other platforms retain their own dispatch paths.

Local embedding inference and on-demand OCR use the native runtime. Model
weights remain optional downloads, not bundled installer assets; see the
[model-source and checksum guide](../../docs/MODEL_MIRROR.md). Vector indexes
stay local and do not synchronize through WebDAV.

`serial_worker.h` is platform-independent and has recorded coverage in
`test/native/OnnxSerialWorkerTest.cpp`. Windows host integration still requires
a Windows build/run; this test alone does not validate WebView2, Flutter input
or complete embedding/OCR behavior on either Windows architecture. No native
builds, inference runs or tests were performed for this documentation update.
