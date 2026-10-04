# SMS interruptions and narration notifications

> Historical record for `1.1.6-test.sms+10051` and the 2026-09-28 checks described below; this is not certification of the latest 1.2.0 release. See the [documentation index](../README.md).

## Fixes

- Retained a brief pause to preserve speech content rather than letting SMS notification audio cover narration. Repeated transient audio-focus losses paused only once, and focus recovery resumed only once without requesting already-held focus again.
- Already paused, manually paused, stopped, headphone-disconnected, engine-switched or permanently focus-lost sessions did not restart automatically. A further interruption during recovery still required waiting for the final focus recovery.
- Android player notifications explicitly used `setSilent(true)` and `setOnlyAlertOnce(true)`, clearing sound/vibration and default alert flags. New notification channels also explicitly had no sound or vibration. Existing channels and user permissions were retained; channels were not deleted and SMS apps/system volume were unchanged.
- `android/modu_audio_notification.gradle` generated a copy of audio_service Java source only inside the build directory, without modifying the Pub cache. If an upstream change made the patch location ambiguous, the build failed instead of silently omitting the fix. Apple/Windows did not use this Android build patch.

## Regressions

`flutter test test/service/tts` included repeated interruptions, rapid successive interruptions, slow pause, user pause, permanent focus loss and locked-screen media controls.

`node --test test/android_tts_notification.test.mjs` checked build wiring and the silent policy. After APK generation, the generated Java and actual device notification state still needed inspection; source assertions alone could not establish device success.

Device procedure: start continuous narration separately with system narration and an online engine. Keep the screen on, receive a real SMS, and confirm that the SMS sounds once and narration continues after a brief pause. Pause manually during the SMS interruption and confirm there is no automatic resumption. Then check locked-screen pause/play and cross-segment narration. Inspect only Modu media state and logs, without reading SMS contents or other apps' data.

References: [Android audio focus](https://developer.android.com/media/optimize/audio-focus), [NotificationCompat.Builder](https://developer.android.com/reference/androidx/core/app/NotificationCompat.Builder).

## Results from this round (2026-09-28)

- Honor LGE-AN10 / Android 15; installed `1.1.6-test.sms+10051` over the existing app with data preserved.
- Automation: narration tests 133 passed, 1 skipped; Android native policy/wiring tests 5 passed.
- Compiled audio_service Java bytecode was inspected for `setSilent`, `setOnlyAlertOnce` and channel-silencing settings.
- During MiMo narration of synthetic text on the real device, a separate test tool requested `GAIN_TRANSIENT_MAY_DUCK` once and released it after 1800 ms. Media-state samples showed PLAYING → PAUSED → PLAYING, with one pause/resume. Focus history showed no repeated focus request by Modu during automatic resumption.
- Actual Modu notification records: `sound=null`, `vibrate=null`, `defaults=0`, `ONLY_ALERT_ONCE`, `groupKey=silent`, `isNoisy=false`, `mIsInterruptive=false`.
- The user requested the end of testing. Manual confirmation of real SMS sound and the same device scenario with the system narration engine were not completed. The original report's repeated sound could not therefore be claimed resolved on the device.
- Test narration was stopped and the separate test tool uninstalled. The fixed Modu build and test book were retained; existing user content was not deleted.
