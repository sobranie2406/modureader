# Windows indexing responsiveness

## Cause and implementation

The 1.0.6 dependency lock selects flutter_onnxruntime 1.8.4. Its Windows method
handler runs model creation and `Ort::Session::Run` synchronously on the platform
thread. A Dart Future or delaying between batches does not move that native work.
Tokenizer FFI and full-book chunk/hash preparation also ran on the Dart caller.

Changes:

- The Windows CMake build replaces only the plugin dispatcher with the locally
  maintained MIT-licensed adapter in `windows/onnx`. All native operations and
  tensor message decoding/encoding run on one lower-priority serial worker.
  Binary responses are posted back to the owning Windows message thread.
- Shutdown expires the channel handler's lifetime gate, drops queued work, joins active inference,
  releases the model on the worker and destroys the reply window last. There
  are no detached worker threads or callbacks into a destroyed plugin.
- A persistent Windows Dart isolate owns the tokenizer, tensor materialization
  and pooling. It receives only model metadata, paths and bounded text chunks.
  Main-isolate cancellation is checked between native operations. Session close
  completes before the isolate is disposed; killing Dart is not native cancellation.
- Pure book chunk/hash preparation runs in an isolate. Custom synchronous
  callbacks remain on their caller for compatibility with unsendable captures.
- CPU inference remains limited to two intra-op threads and one inter-op thread;
  four model files, normalization, queue serialization and index formats remain
  unchanged. Other platforms keep their original native inference paths.

## Local checks

2026-09-15: full Flutter suite **674 passed / 5 skipped**; Python suite
**46 passed**; portable C++ worker compiled with warnings-as-errors and passed.

- `clang++ -std=c++17 -Wall -Wextra -Werror -pthread test/native/OnnxSerialWorkerTest.cpp ...`
  compiles/runs the actual portable worker: owner stays available while a job is
  blocked; replies return on owner; load/run/close remain serial; shutdown joins
  active work and suppresses queued work/replies. Also wired into PR CI.
- `test/service/knowledge/isolate_worker_test.dart` covers CPU work while owner
  timers run, sequential close, reported errors, unexpected exit and startup failure.
- Existing knowledge tests cover all four model selections, pooling, index
  provenance, incomplete-index rejection, queue cancellation and persistence.
- `test/windows_onnx_worker_test.py` checks CMake/source wiring, not Windows execution.

## Windows verification still required

This change was made on macOS. The portable C++ test is **not** a Windows plugin
build, and there is no measured Windows UI frame-rate improvement yet. No package
has been published by this change. On a Windows test account:

1. Build normally; verify the compilation selects `windows/onnx/flutter_onnxruntime_plugin.cpp`.
2. Run `flutter test integration_test/bundled_embedding_test.dart -d windows --dart-define=MODU_EMBEDDING_STRESS=true` for real offline inference with all four bundled models.
3. Index a synthetic long EPUB with each model while scrolling another book,
   switching the AI panel and typing; record frame/input latency in profile mode.
4. Cancel during inference, queue a different model, repeat start/stop and close
   the app mid-inference. Check no partial index is marked complete, no hung
   request, no use-after-free and no sustained model memory after completion.

The fix removes identified blocking paths; hardware/renderer performance and
end-to-end Windows behavior must be assessed separately using these tests.

## Release shutdown regression (2026-09-15)

The first 1.0.7 release attempt (Actions run 34937906783, commit 81fbbefa)
passed Windows x64 compilation, reader extraction, null callback and bundled
model tests, but the installed app crashed on normal close with `0xc0000005`.
Publication was blocked by the installation smoke check.

Flutter 3.47.2 clears `FlutterDesktopMessenger`'s engine before invoking plugin
destruction callbacks. The adapter called `SetMessageHandler(nullptr)` from its
destructor, which resolves that already-cleared engine. Teardown now invalidates
a weak lifetime gate without calling the messenger. The registrar releases its
handler, and late platform messages cannot dereference the destroyed plugin.
Worker shutdown still joins active inference and suppresses pending replies.

Source-wiring regression checks reject a messaging call in the destructor and
require invalidation before worker shutdown. These do not replace native tests:
the release workflow retains three installed-app launch/normal-close cycles,
uninstallation, and all native inference/reader checks. No checks were disabled.
