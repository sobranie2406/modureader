# Recovery from chapter waits while locked (2026-09-25)

> Historical record. This preserves the September 25 investigation and September 26 follow-up, including the original verification limits. See the [documentation index](README.md) and the [current settings guide](SETTINGS.md) for Modu 1.2.0+10082. This documentation update did not rerun tests, build packages or retest lock-screen playback.

## Report and diagnostic limits

The user reported that narration became silent after a chapter transition while the phone was locked. The notification still showed a pause button, and unlocking did not resume playback.

The original test phone was not connected and the device-specific trigger had not been reproduced. This evidence could not establish whether system power saving, a suspended WebView or a lost audio-completion callback caused it.

Inspection found two verifiable gaps in waiting:

- The existing chapter-navigation timeout covered page navigation, but not offscreen text loading for EPUB and similar formats. If `createDocument()` did not return, the serialized narration-navigation queue waited indefinitely.
- Stop waited for the player loop to exit before cancelling reader navigation. If the player was waiting for that navigation, stop could not finish promptly either.

## Changes

- Each offscreen text read waits at most 15 seconds and retries the same chapter once after timeout. A second timeout returns an error to the narration engine, not a book-end marker, and does not skip the chapter.
- Each read has an independent validity check. Results arriving after timeout or stop cannot overwrite the narration cursor.
- Stop immediately releases navigation waits and starts player stop and reader cancellation concurrently to avoid mutual waiting.
- Retry logs contain only the phase and chapter index, without book text.

## Verification at the time

- **246 reader JavaScript tests passed**, including hung reads, same-chapter retry, late results, retry after failure and restarting after stop.
- **32 Flutter tests passed** for narration ordering, lock-screen controls, manual navigation and media state. These included stopping through concurrent cancellation while a real OnlineTts loop waited for a chapter.
- Reader assets rebuilt successfully. Webpack still reported the existing top-level-await compatibility warning.
- Packages and physical-device lock-screen acceptance were not completed. JavaScript timers still depend on WebView execution, so these tests do not prove the implementation can bypass system freezing. If the issue continues, device logs are needed to distinguish text reads, WebView bridging, synthesis and audio-completion waits.

## September 26 follow-up: resume on unlock and occasional repeats

The user confirmed Xiaomi MiMo and stable **1.1.5**. The additional report was immediate recovery upon unlocking after a lock-screen pause, with occasional repetition of the previous sentence. The preceding changes had not yet been packaged, so these reports could not be treated as regressions of a fixed package.

Code still waited on WebView cursor advancement sentence by sentence. Mocked tests could not establish that background WebView suspension had been solved. Dart-side slow-call diagnostics were added: text collection/advancement taking more than five seconds records phase, lifecycle and elapsed waiting time, with another entry upon completion. They contain no text, CFI or credentials, do not automatically repeat cursor operations and do not change playback state.

A recovery path that could cause repetition was also fixed: when the active playback loop had finished the current audio and was waiting for the next sentence or audio data, it no longer sent resume to the native player, avoiding restart of retained old audio. An unfinished current sentence still resumed normally. This did not deduplicate by text; identical sentences in the book remained in sequence.

Additional tests covered repeated pause/resume during a chapter wait without restarting completed audio, and resuming an unfinished sentence. The root cause of the original device's lock-screen pauses still required physical-device logs.
