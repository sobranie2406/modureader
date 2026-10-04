# Online narration in paragraph groups

Current guide for Modu 1.2.0+10082. See the [documentation index](README.md) and [settings guide](SETTINGS.md).

## Behavior

- Edge, MiMo, OpenAI-compatible and DashScope online narration share the same grouping. System speech retains sentence-by-sentence playback.
- Only adjacent sentences in the same DOM paragraph are grouped, with at most four sentences and 240 UTF-16 code units per group. Groups do not cross headings, list items or chapters.
- Long sentences are split preferentially at a comma, semicolon, colon or whitespace in the latter half, otherwise by length. Unicode surrogate pairs are not split. Hidden annotations and numbering remain excluded from synthesis text.
- Each group maps to one audio item and an actual source Range/CFI. The whole group is highlighted; previous/next segment moves one group. The implementation does not estimate sentence timestamps or split returned audio.
- Selecting text and choosing narration starts at the selection. The first group synthesizes only the remainder, then continues to the next group. Manually returning to that first group reads it in full.
- Pause/resume keeps the current audio. Chapter advancement while locked uses the reader channel that does not depend on page layout. It still requires WebView execution; this does not guarantee progress while the system suspends the WebView.

## Requests and boundaries

- The selected voice and description are retained with stable narration-rate instructions. Unsupported APIs do not receive forced prompt fields. The API may still vary the voice between groups; identical model output is not guaranteed.
- At most four playback groups are cached. The first group has request priority; later groups use at most two concurrent requests. Playback can begin before later groups are ready.
- Manual navigation or stop cancels waiting for old synthesis results. Late audio or errors no longer affect playback. The underlying HTTP request may still finish; cancelling a wait does not guarantee avoidance of server charges.
- Streaming decoding was not added. In particular, MiMo text-designed voices must not treat a compatibility streaming wrapper around a complete result as a low-latency audio stream. The implementation uses bounded groups and prefetching.

## Regression coverage

- `test/reader_tts_paragraph.test.mjs`: paragraph boundaries, length limits, hidden content, selection start, accurate highlights, chapter transitions and engine switching.
- `test/service/tts/tts_paragraph_playback_test.dart`: first-group priority, playback order, navigation during slow requests, late success/error, pause/resume and movement by groups.
- Tests do not send book text to live speech APIs. Actual voice continuity and device background playback still require listening checks with installed packages; this documentation update did not perform them or rerun tests.

Implementation: [reader grouping](../assets/foliate-js/src/tts.js), [online playback](../lib/service/tts/online_tts.dart). Related historical investigations: [reader regression](tts-reader-regression.md), [background chapter recovery](tts-background-chapter-recovery.md), [rate recovery](TTS_RATE_RECOVERY.md).
