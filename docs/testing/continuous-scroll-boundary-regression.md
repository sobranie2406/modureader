# Continuous scrolling chapter-end pauses and repeated page-turn regression

> Historical record of the 2026-09-14 source checks concerning the 1.0.7 preview; this is not certification of the latest 1.2.0 release. See the [documentation index](../README.md).

2026-09-14, in response to 1.0.7 preview feedback. Only source and reader assets were changed; no package was rebuilt or published.

## Causes and changes

- The old pre-layout condition considered only distance to the window boundary. At the beginning of a long chapter it did not prepare adjacent chapters, so a fast scroll to the end could hit the boundary of loaded content. The change prepared preceding/following chapters in the background on chapter entry, then filled short chapters according to viewport coverage. Existing count and text-size limits were retained.
- The old `View.#handleClick` added another click callback to the long-lived renderer for every chapter it processed. Loading three documents with the old code made one edge click produce three `click-view` events. Renderer callbacks were changed to bind once at creation; clicks within each chapter still had their own handling.
- Continuous mode previously reported reading position twice during one page turn and jumped chapters separately when scrolling was unavailable. The change first ensured content existed at the target, then performed one 80% viewport movement calculated relative to the original document, and finally reported position. Prepending chapters did not change that movement's reference point.
- A neighboring chapter hidden but retained for TTS reused its original document and returned to the continuous area without reloading or resetting the narration cursor.

## Verification scope

- Reader regressions: 125 passed, including first preload of long chapters, adjacent chapters outside the viewport, bidirectional paging at uncached boundaries, duplicate click registration and TTS document restoration.
- Release/project policy regressions: 43 passed.
- Chromium synthetic book: with the next chapter visible by about 2 pixels at the bottom, and completely outside the viewport by about 25 pixels, one actual click on the edge target at each position produced only one `click-view` and a 512-pixel movement (80% of the 640-pixel viewport).
- One native Chromium wheel movement of 800 pixels crossed into chapter 3. The TTS cursor still returned chapter 2 body text first, then chapter 3's title on completion. This was a text-cursor check on actual DOM, not voice-playback acceptance.
- Reader script assets rebuilt successfully, retaining the three existing build warnings.

Finger-driven inertial scrolling was not verified on an Android device. Very large chapters, image/font decoding or slow devices could still cause waits; these results did not promise pause-free chapter transitions on all devices.
