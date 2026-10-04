# Continuous scrolling Android ARM64 preview

> Historical record for 1.0.7-preview.1+10019, based on 1.0.6; this is not certification of the latest 1.2.0 release. See the [documentation index](../README.md).

Version: 1.0.7-preview.1+10019. Based on 1.0.6, this release provided only an Android ARM64 APK and did not replace the stable release for all platforms.

## Feature scope

- In scrolling mode, adjacent chapters of horizontal, reflowable books were laid out in advance within one scroll area. Prepending chapters compensated the current position.
- The cache normally retained at most 9 chapter views; short chapters were preloaded according to viewport coverage. Chapters larger than 2 MiB were not laid out in the background but could still open in the foreground. The declared chapter-text budget was 8 MiB, not a process memory limit. Foreground navigation and the active narration document could temporarily retain additional views.
- Pagination, PDF/fixed-layout, vertical writing and reading with book JavaScript enabled retained their existing paths. Enabling book scripts did not execute adjacent chapters' scripts in advance.
- Pre-layout did not trigger narration, proactively request AI/translation or create reading-position records. Interactions initialized only once a chapter became visible.
- Only continuous mode separated the current screen position from the TTS cursor. When the screen reached a later chapter, narration still finished the original chapter, then continued from the next chapter's title, retaining existing rules for skipping non-body chapters. Highlight CFIs used a fixed narration-chapter identifier.
- Bookshelf, contents and mode-switching scenarios retained the app's existing stop/pause policies. No online service synthesis interfaces or voice parameters were changed.

## Verification

- Reader automated regressions: 120 passed, including new cache-boundary, equal-distance eviction thrashing, continuity, resource-ownership transfer, close/load-failure and TTS cursor-isolation tests.
- Full Flutter suite: 667 passed, 5 skipped, including system and online TTS chapter-end continuation and pause/resume regressions.
- Synthetic books in actual Chromium and WebKit browsers: initial chapter 2 was not pulled backward by preceding-chapter preloading; loading did not loop while stationary. After scrolling to chapter 5, TTS still advanced through the chapter 2 title, two body sentences and the chapter 3 title. A distant contents jump retained the original narration document, with no reload on return.
- Chromium: forward to the book end, backward to the beginning, the 9-chapter window limit, switching between pagination/scrolling and current-document reuse; native scrolling checked with the mouse wheel.
- Static package validation passed for build number 10019, Modu's original release signature, ARM64-only native libraries, 16 KB page alignment, ONNX JNI entry points, four bundled models and reader-code consistency. Release/project policy tests: 40 passed.

No Android device was connected in this round. Device-specific frame rates, long-running memory peaks and real voice playback were not accepted. Browser and simulated TTS cursor success did not guarantee flawless operation on every device/voice provider.

Very large chapters, slow image decoding, rapid repeated navigation or first-time font loading could still cause waits; zero pauses for every book were not promised. Native selection across iframes cannot drag-select across chapters in one gesture. This change targeted continuous reading and did not alter that selection limitation.

## Suggested tests

Back up before upgrading. The package used Modu's original dedicated signature, allowing installation over the existing app while preserving the library and settings. Open a book, set page turning to scrolling, and test:

1. Scroll continuously forward/backward in a novel with short chapters; check for repetition, skipped chapters and sudden position changes.
2. Start narration at a chapter end; check the next chapter's title and first sentence. Scroll manually into a later chapter while playing, then pause/resume.
3. Save a note, close and reopen the book, and sync; check reading position and note ownership.
4. Change font size, rotate the screen, and switch between scrolling/pagination.

The WebDAV protocol and database schema were unchanged. Problems could be reported through Settings, optionally previewing and attaching redacted diagnostics.

## Source and licenses

This project is based on [Anx Reader](https://github.com/Anxcye/anx-reader) and [ReadAny](https://github.com/codedogQBY/ReadAny), released under GPL-3.0-or-later with upstream licenses and attribution retained. The APK included license files; the Source code attachment under this release tag corresponded to the build's source.
