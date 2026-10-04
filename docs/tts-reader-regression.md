# Narration missing headings / skipping chapters (2026-09-06)

> Historical record. This preserves the investigation, local test results and later Beta3 inclusion recorded at the time; it is not a new test of Modu 1.2.0+10082. See the [documentation index](README.md) and the [current settings guide](SETTINGS.md). No tests, builds or device checks were repeated for this documentation update.

## Comparison source

The user's “Reader Annie” reference was interpreted as ReadAny. Its official source was reviewed at commit `021137eb3dbb398096193ee7b6819e665a281d32`:

- [Narration session management](https://github.com/codedogQBY/ReadAny/blob/021137eb3dbb398096193ee7b6819e665a281d32/packages/core/src/stores/tts-store.ts): session IDs ignore late callbacks after stop; completion is reported only after natural playback completion.
- [Foliate narration extraction](https://github.com/codedogQBY/ReadAny/blob/021137eb3dbb398096193ee7b6819e665a281d32/packages/foliate-js/tts.js): headings are text blocks; ordinary link text should not all be treated as annotations to skip.
- [Playback cursor](https://github.com/codedogQBY/ReadAny/blob/021137eb3dbb398096193ee7b6819e665a281d32/packages/core/src/tts/playback-cursor.ts): the cursor follows actual playback position rather than synthesis-request progress.

The fixes targeted Modu's Flutter/WebView call chain; they did not directly replace it with ReadAny's player.

## Identified problems

1. JavaScript `from()` selected the first sentence in `initTts()`, but its return value was discarded. System narration then called `next()`, advancing again and skipping the heading/first sentence.
2. The text filter skipped all local links, including chapter headings linked back to the table of contents.
3. Android's native start callback pre-enqueued text while completion callbacks also advanced the cursor. Stop, resume and chapter loading lacked session isolation.
4. Online prefetch could cross a chapter transition while still excluding the current sentence, skipping the next heading. Text-hash deduplication also skipped repeated paragraphs without CFI.
5. Synthesis failures or empty audio were marked silent and automatically skipped; consecutive failures could appear as a skipped chapter.
6. Previous/next chapter buttons did not await stop, then also invoked previous/next sentence after changing chapter, causing extra advancement.
7. Chapter completion depended on mutual recursion. Empty chapters and book end lacked strict termination, and navigation failures were not clearly returned to Dart.

## Fix principles

- Initialization returns the current sentence directly, without another advance. Ordinary links and H1–H6 are retained; only explicit footnote references, back-reference marks, hidden text, ruby pronunciation annotations and similar non-body content are filtered.
- System speech uses a loop that waits for each utterance to finish. Android's old dual-callback enqueue path is disabled.
- Session IDs suppress asynchronous results after stop. Pausing during chapter loading preserves the located first sentence of the new chapter on resume.
- Online speech adds ordered batches only at a stable playback cursor and advances after playback completes; it no longer deduplicates by text.
- Synthesis, playback or navigation failures pause and show an error. Retry preserves position rather than substituting silence.
- Chapter navigation is serialized; empty-chapter handling is bounded; book end stops playback. Manual chapter changes do not add an extra sentence jump.
- Native media controls follow actual playback completion/failure, preventing a playing state at book end.

## Verification and limits at the time

Final results for that round: **215 Flutter tests passed, two network tests skipped; 19 JavaScript tests passed; one macOS native system-speech integration test passed; Android ARM64 Debug build succeeded.** The local custom_lint analysis plugin still had a runtime-environment error, so full static analysis was not established.

- JavaScript coverage included text headings, linked headings, footnotes, current-range initialization, single-sentence chapters, empty chapters, book end, dual requests and cancellation after stop.
- Dart tests used real `SystemTts` / `OnlineTts` classes with controllable native/audio interfaces to check ordering, error retry and asynchronous interleaving, rather than checking source strings only.
- The macOS native speech integration test actually completed three test sentences, including two headings, and verified cursor order after native completion. It did not read private books. Foreground window activation failed, so UI acceptance was not claimed.
- The Android ARM64 build established compilation/packaging, not listening acceptance on a physical Android device.
- The original problem book was unavailable. No OCR was added in this fix; image-only headings, purely scanned PDFs and text absent from the file were outside this text-extraction fix.

Commands recorded for retesting:

```sh
flutter test --no-pub
MODU_JSDOM_ROOT=/path/to/jsdom-fixture node --test test/reader_business.test.mjs test/reader_background.test.mjs test/reader_tts.test.mjs
flutter test integration_test/tts_reader_test.dart -d macos --dart-define=MODU_NATIVE_TTS_TEST=true
```

The verification above occurred during local fixing. At the user's later release request, the fixes were included in **Beta3 (build 6329)** without replacing Beta2 packages. Distribution status was subject to the corresponding GitHub Release and CI results.
