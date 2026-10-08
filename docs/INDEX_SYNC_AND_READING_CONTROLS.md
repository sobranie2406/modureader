# Local indexing and reading controls

## Current: Modu 1.2.3+10090

Current behavior was reviewed against main commit [`b6bf820a`](https://github.com/sobranie2406/modureader/tree/b6bf820a4a3fd5ee1f657c80c061f64349a1aedb) on 2026-10-08. See the detailed feature guide ([English](FEATURES.md) · [简体中文](FEATURES_zh.md)) for current reading, speech and sync settings. Dated results below retain their historical scope; this documentation review did not rerun application or device tests.

PDF and classified image books have original-page controls for crop/splits, per-page automatic crop, bounded 100%–1500% zoom, rotation, panning, continuous scrolling and image enhancement. Import classification samples at most five body sections for EPUB, MOBI, AZW3 and FB2 and caches the result per book/source fingerprint. Opening a book only reads that result. Uncertain detection falls back to ordinary reading; bookshelf actions allow a manual correction. Ordinary text books retain their normal reader and menus.

Text Reflow and OCR Reflow display selectable text directly in the reader for the current original page, or the whole page inside its saved crop boundary. They do not limit recognition to a split cell or zoomed viewport. Only Extract opens the region selector and can fill an editable AI input without sending it. OCR requires an optional local model download; V4 is recommended, V5 uses ModelScope upstream, and V3/V4 use Hugging Face upstream or Gitee mirrors. Crop/enhancement never overwrite source files. E-Ink hardware refresh requires a supported device interface. See the [current scanned-document status and archived milestones](SCANNED_DOCUMENT_DEVELOPMENT.md).

The 2026-10-03 decision to cancel OCR, reflow and extraction was superseded by their later implementation before 1.2.0. Whole-book OCR, page export and the proposed comprehensive scanned-document bookmark/search/listening/annotation project were not restored by that decision. Existing reader features remain available within their implemented limits.

## Vector indexes stay on each device

WebDAV vector-index synchronization and its setting have been removed. Manual, automatic and scheduled sync do not upload or download vector indexes. The old setting is removed at startup and cannot be imported or exported in settings backups.

Local vectorization, existing indexes and AI retrieval remain available. Each device builds its own indexes as needed; semantic queries require the matching embedding model. Normal book, note, bookmark and reading-position synchronization continues. Sensitive model configuration follows the existing encrypted API-key sync setting.

Upgrading does not automatically delete local indexes or historical cloud files. If you choose to remove old cloud indexes, limit cleanup to `modu/knowledge-v1` under the configured WebDAV location, preserving book folders and the sync database. Disable index sync on older clients first to prevent them uploading again.

Large local indexes are parsed record by record, with limits of 1 GiB per file, 2 Mi characters per record, 250,000 chunks and 8192 dimensions. Older compact and newline-delimited JSON indexes remain readable. Retrieval still loads chunks and numeric vectors into memory; the file limit is not a low-memory-device guarantee.

## Quick-highlight menu

On mobile, quick-highlight mode offers a toolbar toggle to show the selection menu after saving a highlight. It is off by default and remembered locally. When off, releasing the selection only saves the highlight. When on, successful saving opens the menu for the actual saved annotation, including a cross-page merged annotation. Ordinary text-selection menus are unaffected.

## Background narration

Android media notifications expose play/pause, previous passage, next passage and stop. Cross-chapter text loading is separate from visible-page positioning, so narration does not wait for page layout; highlighting catches up on returning to the foreground. Background narration has its own saved position. Player cleanup errors during Stop do not prevent the remaining cleanup or the next start.

Recorded automated coverage includes cross-chapter navigation, avoiding background page rendering, stop races, player cleanup errors, notification state and the quick-highlight menu. Historical index-transfer code remains only for compatibility regressions and is not connected to app sync. Other regressions check removal of the old switch, rejection during backup restoration and the absence of index-transfer calls from sync. Long lock-screen sessions, vendor power management and notification interaction still need Android device verification.

## Historical: Stop Vectorization and startup queue (2026-10-03)

- The bookshelf background-vectorization bar and Settings → Vector Model gained Stop Vectorization.
- Stop first persists automatic vectorization as disabled, then cancels the active task and all queued tasks and waits for safe worker cleanup. Restart does not restore those automatic tasks. Completed indexes, models and books remain; atomic saving prevents partial output replacing an existing index.
- Automatic tasks gained origin tracking. Disabling automatic vectorization after import cancels automatic tasks and their queue, preserving manual tasks. Disabling the vector model cancels all tasks. Settings import/sync notifications apply the same cancellation rules.
- The previous scanner read the switch only when scanning began; disabling it did not cancel the in-memory queue. The implementation rechecks both switch and scan generation around every asynchronous index check, preventing a stopped scan from enqueueing later.
- Cancellation markers on removed queued tasks were fixed so that manual vectorization can be started again from a book menu.
- At this stage the user had paused packaging; these changes were developed and tested without a new installer.
- Recorded verification: 162 Flutter regressions passed across indexes, models, cancellation, Stop and reading focus; two opt-in network tests were skipped. Added cases covered preserving manual tasks, no automatic restart after Stop, stopping during scanning, manual retry and byte-for-byte preservation of old indexes.
- Standard Dart/Flutter analysis reported no errors or warnings in the relevant files; two existing asynchronous-context notices remained in the bookshelf file. The SDK was incompatible with the old custom_lint plugin, so standard analysis bypassed it in memory without changing repository configuration or claiming plugin validation.

## Historical: Hanvon Bluetooth page-turn pen reconnect (2026-10-03)

### Observations

The local debugging task supplied Hanvon N10Pro (`rk3576_ebook`) logs for `1.1.11+10072`: after Bluetooth pen disconnect/reconnect, the status bar appeared and visible rendering stopped. The UI tree could still open/close a translation dialog while screenshots remained on the old page. Logs repeatedly contained `EGL_BAD_ACCESS` and `Could not make the context current to acquire the frame`.

At 14:58:38.784 and 14:58:39.505, `Config changes=70` coincided with LaserPen removal/addition, navigation changing between none and dpad, and two MainActivity window relaunches. The manifest handled keyboard/keyboardHidden but omitted navigation, consistent with HID-triggered Activity recreation. EGL errors were already present when capture began; this log does not establish the first rendering failure or prove Activity recreation was the sole cause.

### Change and validation limits

- Added MainActivity's `navigation` configuration declaration while retaining Flutter configuration forwarding. See [Android configuration changes](https://developer.android.com/guide/topics/manifest/activity-element#config).
- Configuration changes clear held page-turn keys that may lack key-up; foreground return resynchronizes whether the current reader permits those keys.
- Native configuration/foreground recovery and closing a reading panel restore system-bar preferences only for an interactive reader with no focused input/keyboard and hidden-status-bar enabled. Ordinary temporary system-bar gestures remain available.
- Hardware acceleration and Impeller were retained; no global renderer disablement, FlutterEngine recreation or library/index/settings-data change was introduced.
- No Hanvon device was connected to the remote development task. Source checks and regressions do not replace repeatedly reconnecting the pen on-device and confirming no relaunch, no new EGL errors and continuing visible rendering.
- Three Android configuration/recovery contract checks and the pure-Java key disconnect/reconnect check passed. Nine Dart key/focus cases were included in the 162 tests above.
- An ARM64 preview containing only this stage was compiled before packaging was paused. It was not installed, distributed or released and did not contain the later Stop Vectorization changes.

### Subsequent Android preview packaging (2026-10-03)

The user later resumed packaging and requested a GitHub pre-release. `1.1.12-preview.3+10075`, tagged `android-1.1.12-preview.3`, included the Bluetooth and Stop Vectorization changes and supplied only an Android ARM64 APK and SHA-256. Signing, ARM64/16 KB ELF alignment for seven native libraries, ZIP alignment and ONNX JNI definitions were checked. It was not installed on a device and did not change the stable update manifest. See the [historical preview notes](releases/1.1.12-preview.3.md). Stable 1.2.0 now supersedes that preview baseline.
