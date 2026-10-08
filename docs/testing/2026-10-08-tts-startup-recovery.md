# TTS startup recovery — 2026-10-08

## Report and scope

Modu 1.2.2+10087 on iQOO Neo8, OriginOS 6 / Android 16: reading is silent on Wi-Fi, cellular works, and settings preview speaks after a delay. No useful application log was reported. The connected device is an Honor LGE-AN10, not the affected iQOO. The reported Wi-Fi-specific failure has **not** been reproduced on the original device.

## Verified code defect

The pinned flutter_tts Android implementation (ad4a10bb4977031a1e60fd8027fb62b932d635ce, FlutterTtsPlugin.kt) sends `speak.onError` from both native onError overloads without completing `speakResult`. Modu awaited `speak` with awaitSpeakCompletion enabled and did not install an error handler. A native failure can therefore leave the reader in a playing/waiting state indefinitely without logging the failure. This is a confirmed failure mechanism, not proof of the original network failure's cause.

## Changes

- Race the native completion with an explicit native-error signal; stop the native utterance on failure, preserve the sentence, and allow retry.
- Watch only the pre-start interval (60 seconds). Cancel this deadline when native speech starts; do not impose a duration limit on long passages. Pause/stop releases the pending wait and invalidates old playback through the existing generation checks.
- Show buffering while waiting for native start. Log a slow start after five seconds and native numeric error codes, never plugin messages or text.
- Remove unused default-engine/default-voice queries from reader initialization.
- Diagnose initial WebView text retrieval, backend initialization, notification preparation, audio focus and online initialization failures. Log connection **type** asynchronously, without blocking playback or recording SSID/IP/credentials/book text.
- Catch narration-panel startup failures and avoid auto-starting after that panel/reader has been disposed.

## Validation

`flutter test --no-pub test/service/tts test/widgets/tts_fab_test.dart test/widgets/tts_quick_toolbar_test.dart`

156 passed; one opt-in live Edge network test skipped. Added tests cover an unresolved native request followed by onError, same-sentence retry, no-start timeout without advancement, long speech unaffected after onStart, and initialization without unused default-voice queries. Existing pause/resume, manual navigation, lock-screen, buffering and online provider tests passed. No live cloud synthesis or same-device Wi-Fi/cellular comparison was performed, and no package was installed for this change.

## Original-device follow-up

Use the same book, position and voice on Wi-Fi and cellular. Collect logs immediately after failure, with particular attention to `TTS network transport`, `backend-init`, `audio-focus`, `start waiting`, `system waiting for native audio start`, `system native error`, and `online reader initialization failed`. Do not attribute a transport-dependent failure to DNS, IPv6 or vendor network policy without that evidence.
