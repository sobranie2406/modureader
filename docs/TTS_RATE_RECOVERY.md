# Online narration failure recovery in 1.0.9

> Historical record. This describes the 1.0.9 investigation and local verification, not a fresh test of Modu 1.2.0+10082. See the [documentation index](README.md) and the [current settings guide](SETTINGS.md). The documentation update did not rerun tests or reproduce the device issue.

## What the logs establish

Against the 1.0.9+10028 source, `online_tts.dart:170/173` were the native player's `stop` / `dispose`; `:540` invoked cleanup during stop; `:577` stopped current playback in `next()`; and `tts_handler.dart:196` was “next segment.” Service switching used the same cleanup chain. These are historical line numbers.

Old cleanup ran sequentially. An exception exited early, skipping the clearing of the player reference and buffers. Subsequent next-segment, stop and voice-switch actions could encounter the same failed player again. This can explain “after the first error, narration stopped working entirely,” but the logs did not retain the native error code/message or rate value, so they cannot establish which rate triggered the first native failure.

Changing the rate itself did not restart the OnlineTts player; it cleared pending audio and changed the request version. Previously, every slider movement triggered this operation. Requests using old parameters could keep retrying after failure, adding unnecessary requests and waiting. Edge voice-list network errors in the logs belonged to a separate path.

## Local fixes

- Slider dragging previews rate/pitch and commits on release. The current sentence continues; subsequent sentences are regenerated. Identical or invalid values do not trigger new online requests.
- Audio and request errors from old parameters are discarded; invalidated parameters no longer keep retrying.
- Cleanup detaches the player reference first, and one native cleanup failure does not block the remaining cleanup. A player is cached only after successful initialization; recovery creates a new player.
- Native pause/resume exceptions become retryable states that preserve the current sentence. Pause/resume remains usable after recovery.
- Consecutive service switches clean up serially. Stop or later navigation invalidates earlier pending navigation, preventing narration from restarting after stop.
- Rate-change request-failure logs contain neither book snippets nor raw service-error content.

## Verification at the time

`tts_rate_recovery_test.dart` used controllable requests and a mocked native player for 11 scenarios: old-rate request success/failure, uninterrupted current sentences, initialization/play/pause/resume failure, consecutive navigation and stop, and release failure during service switching. TTS and AI reading-error component regressions totaled **61 passed, one skipped**.

This was automated verification, not reproduction on a vivo V2301A. The fixes were included in **1.1.0+10029**; installed 1.0.9 builds required an upgrade to contain those code changes.
