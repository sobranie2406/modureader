# Android vectorization memory revision verification (6330)

> Historical record for `0.1.0-beta.3+6330`, compared with Beta3 build 6329; this is not certification of the latest 1.2.0 release. See the [documentation index](README.md).

## Problem and scope

User report: on Beta3, Android 16, iQOO Neo8, EPUB vectorization with the third, 512-dimensional Chinese BGE model exited partway through. No crash stack was received and the phone was not connected, so system memory reclamation, a native signal crash or another cause could not be distinguished.

The four bundled models previously shared one inference path. The old implementation used the default ONNX memory arena, transferred up to 512 × 512 hidden-state values to Dart, then copied and pooled them into the final vector. This increased memory and garbage-collection pressure during sustained inference. It was a confirmed code risk, not the sole root cause reproduced on the original phone.

## Code changes

- Android used a separate background serial channel and CPU session, with a single thread, basic graph optimization, and CPU arena and memory pattern disabled.
- Mean pooling and L2 normalization ran natively; only the final 384/512 values crossed the channel. Model IDs, output dimensions and pooling methods were retained; existing books and indexes were not cleared.
- Input tensors, output Result and SessionOptions had explicit close lifecycles. The model was released after exceptions and unloaded after 15 seconds of session inactivity.
- Catchable Java out-of-memory exceptions were caught and reported as task failures. This could not intercept Android force-kills, SIGSEGV or other native signals.
- Actual input was capped at 512 tokens again after re-tokenization, preserving the final separator token.
- macOS/Linux/Windows/iOS retained the original inference backend; only Android revision packages were produced in this round.

Official resource ownership guidance: [ONNX Java getting started](https://onnxruntime.ai/docs/get-started/with-java.html), [Result.close](https://onnxruntime.ai/docs/api/java/ai/onnxruntime/OrtSession.Result.html).

## Tests performed

- Full Flutter suite: 242 passed, 2 skipped; the vector module had 40 passing tests, including 6 new channel, dimension, error and length-boundary tests.
- Reader JavaScript: 19 passed.
- Package inspection tool unit tests: 18 passed.
- Per-file `dart analyze` passed for the added/modified inference Dart code, channel tests and integration tests. Flutter's multi-file analysis command encountered an internal analyzer JSON error; that failure was not recorded as a pass.
- Android ARM64 Debug compilation passed.
- Android ARM64 / x64 Release (6330) compilation passed. Both APKs were checked for the original signing fingerprint, application ID, version, non-debuggable flag, absence of vibration permission, content hashes of all four bundled models, the new native inference channel, ONNX 1.24.3 native library Build IDs, and architecture and 16 KB alignment of all 7 native libraries.
- Using the production Java session implementation, official ONNX Runtime Java 1.24.3 and all four real bundled models, 332 inferences ran on macOS ARM64. Each model ran 80 alternating-length inferences (16–512 tokens) plus 3 release/reload inferences. Checks covered dimensions, finite values, normalization and rejection of overlong input.
- Java heap limit: 192 MiB; direct-memory limit: 128 MiB. The table shows process RSS checkpoints after requesting GC at inference 16/80, not peak values or Android memory measurements.

| Model | Dimensions | Runs | RSS checkpoints KiB (16 → 80) | Result |
| --- | ---: | ---: | ---: | --- |
| all-MiniLM-L6-v2 | 384 | 83 | 185264 → 192944 | Passed |
| bge-small-en-v1.5 | 384 | 83 | 229952 → 231776 | Passed |
| bge-small-zh-v1.5 | 512 | 83 | 286000 → 287872 | Passed |
| multilingual-e5-small | 384 | 83 | 527424 → 323408 | Passed |

Tests used no user books or keys. E5 remained significantly larger; these results could not guarantee operation on every phone under arbitrary memory pressure.

## Not yet verified

- Full vectorization of the original EPUB on iQOO Neo8 / Android 16, background switching, and simultaneous reading and vectorization on the device.
- Other Android devices, very large EPUBs, system low-memory force-kills, and the complete Rust tokenizer stress path on devices.
- A real-tokenization and channel stress mode was added to `integration_test/bundled_embedding_test.dart`, but it was not run because no Android device was available locally. With a connected device, run:

```sh
flutter test integration_test/bundled_embedding_test.dart -d DEVICE_ID --dart-define=MODU_EMBEDDING_STRESS=true
```

This mode runs 80 short/long Chinese and English texts per model, validates output, and reloads after release. It still cannot replace reproduction with the original EPUB.

## Installation and retesting

The version was `0.1.0-beta.3+6330`; the original Beta3 build was 6329. It used the original dedicated Modu signing key and unchanged application ID. Install over the existing app; do not uninstall the old version. Choose the ARM64 APK for iQOO Neo8.

After installation, re-vectorize the original EPUB from the book menu, testing Chinese BGE first and then the other three models. Observe completion, cancellation/queueing and reading behavior. If the app still exits, the crash time and system logs are needed to identify the cause; not every exit should continue to be attributed to memory.

The README was not changed. Following the user's subsequent request, the 6330 revision packages were to replace the existing Beta3 Release's Android attachments and their checksum/license attachments. Other platforms retained 6329, and the original Beta3 tag was not moved. The revised Android source was linked separately in the Release notes and license attachments.

Packages were in `dist-release/android-hotfix-6330/`:

- `Modu-0.1.0-beta.3-6330-android-arm64.apk`, SHA-256: `045eac1a427c6292fdc9da4b3766f7a8e28ed24d08f6e76b2a6fd4496155473c`.
- `Modu-0.1.0-beta.3-6330-android-x64.apk`, SHA-256: `f96b5fec3ab8b65338467c6882e6e1ed87fc33005e81dbc11dd2da02cd073501`.

Local packaging note: after debug tests, use the standard `flutter build apk --release ...` flow to regenerate platform plugin registration. Two `--no-pub` builds in this round retained test-plugin registration, while release dependencies excluded the test plugin, causing Java compilation failure. The packages were rebuilt after removing that skip flag. Do not manually add integration_test to production dependencies.
