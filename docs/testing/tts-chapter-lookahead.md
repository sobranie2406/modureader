# Locked-screen chapter lookahead and media waiting state (2026-09-27)

> Historical record of the 2026-09-27 source checks described below. No release version was specified; this is not certification of the latest 1.2.0 release. See the [documentation index](../README.md).

## Problem and changes

Users reported pauses at the beginning of some chapters while the screen was locked, with narration continuing after unlock while the player retained its previous state.
Code inspection found that although chapter reading was already detached from layout, body text was still decompressed on demand at chapter boundaries. The rolling online-synthesis queue covered only the current chapter, and the media session did not distinguish waiting from actual playback.
These were confirmed waiting paths, not confirmation of all operating-system scheduling behavior on the user's phone.

- On narration start and each new chapter, documents for up to three subsequent narratable chapters were read ahead. Pages, fonts and images were not loaded; body text was unchanged, and neither the cursor nor published reading progress advanced early.
- The sequential audio queue could fetch text across chapters and synthesize the next chapter's title/body in advance. Current-chapter text returned immediately without waiting for unfinished lookahead. Unloaded/corrupt chapters could not be skipped.
- Only the current document and next three chapter documents were retained. Stopping or switching narration mode cleared the cache. Failed lookahead was not retried on every producer poll; it was retried on reaching that chapter, with the document fetched again after a timeout.
- System and online narration shared the waiting state. Only waits longer than 300ms published buffering and “Loading speech,” avoiding flicker during normal fast segment transitions. Playback intent and pause controls were retained without artificial pause/resume cycles to restart audio; user pause/stop took priority.
- Late results from an old session could not clear a new session's waiting state.

## Verification

- `flutter test --no-pub test/service/tts`: 125 passed, 1 existing network test skipped.
- `MODU_JSDOM_ROOT=/tmp/modu-reader-tts-tests node --test test/reader_*.test.mjs test/vertical_*.test.mjs test/android_tts_native_contract.test.mjs`: 266 passed.
- Webpack regenerated `assets/foliate-js/dist/bundle.js`, retaining only existing build warnings about top-level await and older browser targets.
- Dart analysis of changed files had no errors. There were 5 existing brace-related informational findings and an existing custom_lint startup-environment failure; this was not recorded as complete static-analysis success.

Added cases covered cross-chapter audio synthesized before the current segment finished; lookahead without cursor/progress changes; reuse of lookahead when background rendering and repeat decompression were unavailable; empty, annotation and non-body chapters; CFI and paragraph boundaries; cache limits; failure retry; invalidation after stopping; pause/resume while waiting; and locked-screen media-state refresh without a playback-state change.

No package was generated and the issue was not reproduced or accepted on the reporting phone in this round. Simulated regressions alone could not rule out the operating system completely freezing the WebView/process; comparison logs from the same locked device were still needed.
