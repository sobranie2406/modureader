# Scanned-document development and release status

## Current: Modu 1.2.0+10082

This section describes the stable Modu release, using the publishing repository's `v1.2.0` commit `77dc238fb2ae2ce02455bd80c500ee9fd140f219`. Uncommitted application changes are not evidence for this guide. The dated development records below are translated in full, preserving their milestones and test results; no tests were run as part of this documentation update.

The 2026-10-03 cancellation of OCR, reflow and extraction was an earlier scope decision. Later development restored and implemented on-demand local OCR, reader reflow and extraction before the stable release. Earlier statements such as “cancelled”, “pending”, “Preview 3 only” and “not packaged or released” describe their recorded stages, not the current release. Whole-book OCR, page-image export and the proposed comprehensive scanned-document integration project are not implied by that restoration.

### Formats and classification

- PDFs use the document reading controls. EPUB, MOBI, AZW3 and FB2 use them when import classification or a manual bookshelf override identifies an image book. Ordinary text books, including books with covers or illustrations, retain their normal reader and menus; PDF controls do not apply to them.
- Import classification samples at most five body sections, excluding known covers, contents and non-body sections. It uses image/text evidence rather than a filename extension or fixed-layout flag alone. Results are stored per book and source fingerprint; opening a book reads that classification without new sampling or hashing. Uncertain or failed detection falls back to ordinary reading. Bookshelf actions can set a scanned image book or restore ordinary reading; replacing the source invalidates the old decision.
- Local import and remote-library import share classification. Downloading a missing bookshelf file through WebDAV can populate its local classification without adding another book, changing progress or starting vectorization. Older unclassified image books can be corrected manually.

### Original-page reading

The document panel provides 100%–1500% visible-region zoom, fit-page/fit-width, rotation, panning, single-page and continuous-scroll reading. Crop and split editing supports page/book/odd-even scopes, seven split layouts and reading order. Per-page automatic crop uses each page's own bounds and saved safety margin; uncertain pages retain the full page. Split navigation advances within the original page before moving to the next one. Original page identity and reading position are retained.

Image processing includes text darkening, contrast, darkening, bleaching, sharpening and conservative scanned-watermark fading. Crop and enhancement alter display and saved reading settings; they never overwrite the PDF or image-book source file. Watermark fading can leave marks or affect light artwork, so compare with the original. It does not reconstruct obscured text. Rendering and caches are bounded, but their pixel/file budgets are not guarantees of total process memory use.

### OCR, reader reflow and Extract

- OCR models are optional downloads, not bundled weights or automatic startup downloads. V4 Chinese/English is recommended (14.9 MiB); V5 Chinese/English is optional (20.5 MiB, upstream ModelScope); V3 Chinese/English (12.5 MiB) and V3 English (10.9 MiB), like V4, use Hugging Face upstream. Gitee mirrors are available. Pinned size and SHA-256 checks apply; source failure does not silently change the selected source. See [model downloads](MODEL_MIRROR.md).
- Text Reflow and OCR Reflow put selectable text directly into the reading area. They process the current original page, or the whole current page within its saved crop boundary. A split cell, zoom or visible viewport does not narrow that range. Text Reflow prefers an existing text layer and uses local OCR when needed; OCR Reflow forces recognition. Returning to the original page preserves its location.
- Only Extract opens the region-selection editor; it also offers whole-page extraction. Extracted text can be placed in the existing AI conversation's editable input without sending it. Sending requires the user's action. Reflow formatting does not rewrite the extraction draft. OCR runs locally; page images and model downloads are not sent to the AI service by extraction.
- The shared document text-style editor controls font, size, weight, line/letter spacing, margins and justification. Per-book styles and page reflow caches are separate from ordinary book styles and source files. Reflow annotations use original-page/text-version/range anchors rather than pretending to be original-page EPUB CFIs.
- Stop cancels the current recognition and discards its result; valid downloaded models remain for offline reuse. Work is page-based with bounded input and inference, not an automatically resumed whole-book task. Complex columns, vertical text, tables and inverted pages are not guaranteed to reconstruct faithfully.

### E-Ink and local indexing

Document refresh controls require E-Ink mode and a supported Android device refresh interface. Unsupported devices cannot perform the hardware action; the app does not simulate a full refresh or promise firmware waveform modes. Manual refresh and every-N-original-pages refresh are subject to capability and foreground/focus checks. No new physical-device acceptance is claimed here.

Vector indexes remain local. WebDAV vector-index synchronization and its setting are removed, while local indexing, retrieval and Stop Vectorization remain available. See [indexing and reading controls](INDEX_SYNC_AND_READING_CONTROLS.md).

### Release status and evidence limits

Stable `1.2.0+10082` supersedes the Android-only Preview 3/4 development baselines. Its release matrix has eight packages: Android ARM64, iOS ARM64, and ARM64/x64 for macOS, Windows and Linux; there is no Android x64 package. See [update mirror guidance](UPDATE_MIRROR.md) for source selection and the macOS browser-download boundary.

Historical test counts, build checks, device observations and performance samples below remain evidence of those stages only. They are not new release-wide testing, proof of every E-Ink device, or a claim that private book pages are published. Current public artwork rules are in [display assets](images/README.md).

## Archived development specification and milestones (2026-10-03–04)

The following specification and records are translated in full from the development document. Their scope decisions, proposed menus, matrices and stage-specific “current” labels are historical; the 1.2.0 release status above takes precedence. The older matrix is not the stable release completion matrix. Translation preserves recorded testing evidence without claiming new tests.

## Historical scanned PDF / image EPUB specification and completion matrix

## Authorization, baseline and evidence

- On 2026-10-03, the user confirmed “development is now allowed”; the baseline was published `android-1.1.12-preview.3` (`e13dd334`). Code/development-document changes were authorized, without packaging, publishing or installation.
- The reverted selection/page-turn change was not restored. Its separate issue record noted that the old `book.js` bottom-of-page `selectionchange` auto-turn timer did not finish on release/cancel; local Hanvon snapshots also showed selections crossing columns. The two snapshots could not yet establish a complete single event sequence.
- Reference: UI and read-only interface research on the USB-connected Hanvon N10Pro built-in reader `hanvon.aebr.hvreader` (2026-10-03). Entry points, groups, order and mode interactions informed Modu's own components; no Hanvon APK, proprietary .so or decompiled source was introduced.
- Responsibilities: this task maintained source, documents and automation; the local task collected logs and performed Hanvon device acceptance. The menu observations below do not establish Modu implementation or acceptance.

### Scope at the restoration stage: on-demand local OCR and extraction (2026-10-04)

The user explicitly restored region recognition, optional OCR-model downloads and extraction into AI. This superseded the corresponding historical cancellations below, without restoring whole-book OCR, page export or the comprehensive scanned-document integration project.

- Extract was added only to the PDF/import-confirmed image EPUB bottom toolbar. Ordinary text books, the bookshelf and global settings did not gain scanning controls at this stage. A later user request restored the PDF panel gear for OCR/extracted-text styles rather than original-image styling.
- The document-layout and extraction/reflow panels shared one OCR text-style editor: font, size, weight, line/letter spacing, side margins and justification, with live sample preview, Apply, Cancel and Reset. Per-book `documentTextStyles` were separate from ordinary BookStyle. Applying did not switch original-page mode, start OCR, change extracted source text or rewrite AI drafts. Existing reflow updated immediately, and reopening reused saved values.
- Hanvon references 07/14 informed original-page preview, region/whole-page recognition, draggable frame/four corner handles, local recognition, Stop and Extract. Responsive native black-and-white components were used, without proprietary code or unimplemented cloud-recognition buttons.
- Extraction preferred the selected page/region's existing text layer. Missing text prompted downloading PP-OCRv4 Chinese/English mobile weights; forced OCR was also available. Versions, sizes and SHA-256 were pinned. Files went to private application support, not installer assets, startup recovery or whole-book background tasks. The 14.9 MiB figure was download size, not peak memory.
- Recognition ran in a separate Dart isolate; Android native inference used a dedicated serial background queue. Each job had a 2MP input limit, detection long-edge limit of 960 and at most 300 text regions. Stop discarded results and closed model sessions while retaining verified weights for offline reuse.
- At this stage Text Reflow was a horizontal current-page/selected-region text preview with size/line-spacing controls and return to original. It did not alter the book or claim full pagination or semantic multi-column/table reconstruction. Complex columns required selecting one column; vertical/inverted pages were not guaranteed.
- Extract to AI Input opened the existing conversation, filled original extracted text, retained the conversation and did not send automatically. Reflow line joining did not rewrite the AI draft. Neither book-page images nor model downloads went to the AI service; only a subsequent Send action transmitted input.
- Earlier stages/menu tables/cancellation entries remained historical evidence. This restoration scope took precedence at that time, while other Preview 3 isolation requirements remained.
- Recorded verification: 55 Flutter and 79 JS regressions passed for ordinary-book menu isolation, optional model downloads, text-layer preference, forced OCR, region handles, cancellation/result discard, cross-page reflow and widths 320/844/1024/1440. Private real-book screenshots checked phone/desktop layouts.
- A separate macOS native check covered actual downloads, both SHA-256 checks, cancellation during recognition and retry. A gray-background English sample took about 0.7 seconds; a real Chinese scan took about 2.9 seconds, each a single local development-build sample rather than a cross-platform guarantee. Android ARM64 Kotlin compiled; no Android device was connected for acceptance. No installers were generated, installed or published at this stage.

### Historical scope reduction (2026-10-03, after stage six)

The user cancelled OCR, text reflow, extraction/export and comprehensive scanned-document bookmark/search/listening/annotation positioning. At that stage these were removed from development/acceptance, not deferred or counted as pending.

Original PDF/image EPUB reading, detection, zoom, rotation, single-page/scroll, crop/splits, enhancement, related preferences and device adaptation remained. Existing search, listening, annotations, copying, backup/export and text layers were retained. Stages one through six remained history, with older plans subject to this scope and the then-latest dependency order.

## 1. Historical goals and formats

### Hanvon device visual references (received 2026-10-04)

Fifteen original screenshots and accompanying XML were saved only in the local `references/hanvon-pdf/` directory, with `README.txt`, a screenshot index `index.html` and `manifest.json`. These private reference assets are not publishable, are not tracked in Git and remain local only. The historical filenames below identify the design evidence; they are not repository download links.
Received ZIP SHA-256: `749adaccf95022fe5b0d760867cb0437ddfcb48f1b97ac237b7d34aa3d6f9b21`; all 15 PNGs matched the local `manifest.json`.

| UI | Reference | Scope adopted at that stage |
| --- | --- | --- |
| Reader toolbar | `01-pdf-menu-open.png` | Keep text above an expanded bottom panel |
| Original-page layout | `02-pdf-layout-open.png` | Left-aligned labels, horizontal groups, monochrome contrast and inverted selected options |
| Separate crop editor | `03-pdf-study-crop.png` | Preview, mask, draggable frame, Cancel/Save |
| Five enhancements | `04-pdf-enhance.png` | Value, minus, slider, plus and reset for each |
| Reflow/spacing/OCR | `05-pdf-reflow-panel.png`, `06-pdf-spacing-panel.png`, `07-pdf-ocr-panel.png` | Historical reference; cancelled at this stage, with no new entry/implementation |
| More settings | `08-pdf-more-settings.png`, `09-pdf-more-bottom.png` | Separate detailed settings from the main panel |
| Page-turn/oversize options | `10-pdf-page-turn-options.png`, `11-pdf-oversize-options.png` | Connect existing original-page reading behavior |
| OCR direction | `12-pdf-ocr-options.png` | Cancelled then; reference only |
| Refresh | `13-pdf-refresh-menu.png` | Only with supported device interfaces, no placeholders |
| Extract | `14-pdf-extract-menu.png` | Cancelled then; reference only |
| Top More menu | `15-pdf-study-extra.png` | Reference hierarchy only, without expanding the project |

Original images 02/03/04 were inspected directly at that stage. Dedicated PDF/image EPUB quick-panel entry points were retained; existing gear styles and ordinary-book menus stayed at Preview 3. The reference package's `development-spec.txt` was historical material; scope decisions and direct user instructions took precedence. Screenshot text was not copied into the product, screenshots did not substitute for interactive UI, and reference assets were not publicly published.

The then-goal was improved original-page PDF reading and automatic recognition of scanned PDFs/image-dominant EPUBs through a shared image/display engine. Original pages were retained without new reflow/OCR under that reduced scope; text EPUBs kept their original reader. Detection was visible/manually correctable, and mixed documents were handled per page/chapter without forced text rasterization or whole-book PDF conversion.

## 2. Historical entry points and menu order

Tapping the center of the text showed top/bottom bars; tapping again returned to immersive reading.

The 2026-10-03 isolation requirement applied the new menu automatically to PDFs and only to EPUBs confirmed by body-image evidence, not extension/fixed-layout metadata alone. Ordinary text EPUB, TXT, Markdown, MOBI/AZW and other books retained Preview 3 menus, without detection, original-image, crop/split or enhancement entries. Old per-book image-mode preferences could not override that boundary. Later multi-format support is recorded below.

EPUB import sampled at most five dispersed body chapters during existing metadata parsing, excluding known covers, contents and nonlinear chapters. At least 60% needed measurable dominant-image coverage. Text chapters received lightweight text checks without image decoding. Detection had a four-second total deadline, parallel to cover loading, with original-menu fallback for failure, timeout or insufficient evidence; no network, OCR or full conversion. Per-book/content-fingerprint classification was cached; opening did not sample, inspect images or recalculate file hashes. Old unclassified EPUBs kept Preview 3 menus and could be reimported; old PDFs selected the new menu by file type without analysis. First confirmed detection enabled original-page reading by default while preserving explicit opt-out. Cover recovery and TXT/Markdown conversion did not run detection.

- Existing navigation/actions remained without dedicated scanned-document search/listening/bookmark/annotation integration.
- New/changed entries at that stage were limited to layout, crop/splits, enhancement, display settings and supported-device refresh; no Extract, OCR, reflow or page-export entry.

Original page numbers/positions remained compatible. A button's presence did not count as completion; unimplemented placeholders were excluded.

## 3. Historical original-page Layout panel order

1. Zoom: value, minus, slider, plus; 100%–1500%. High magnification required region/tile rendering, not a 15× full-page bitmap.
2. Mode: single page/scroll, fit screen/width/paper. Paper mode followed columns/regions before moving to the next original page, rather than merely fitting width.
3. Crop: automatic crop, safety-margin minus/value/plus, comic and custom. The reference margin range was 0–20, with 3 on the Hanvon device; units were unconfirmed and could not be labelled millimeters.
4. Enhancement overview: text darkening, contrast, darkening, bleaching and sharpening, with values and a shared enhancement panel.
5. Rotation: portrait, right 90°, left 90°.
6. More settings. Under this historical scope only original-page reading was offered, without original/reflow/OCR-reflow switching.

## 4. Crop and splits

A separate preview offered regular/odd-even mode, count, draggable frame, Reset/Cancel/Confirm. Counts: single, horizontal two, vertical two, four, horizontal six, vertical six and nine. Multi-cell layouts had corresponding horizontal left-to-right/right-to-left and vertical column orders; vertical two followed top-to-bottom. Normalized rectangles/order were tied to document/original page with page/book/odd-even scopes. Odd/even crops were independently previewed/saved. Comic was a crop/split preset, not text reflow. Cancel saved nothing; reset restored the original and never overwrote source files.

## 5. Image enhancement

Each row in a separate panel had value, minus/plus, slider and Reset, with return to Layout above:

- Text darkening 0–15: stroke enhancement on the page image.
- Contrast −100 to 100: contrast mapping.
- Darkening 0–100: gamma/shadow enhancement.
- Bleaching 0–200: background cleanup.
- Sharpening 0–100: edge sharpening.

The default darkening value 5 on some Hanvon Android 14 monochrome devices was not applied to every device. Algorithms had to be distinct and preserve thin lines/images. Slider requests were coalesced, thumbnails rendered first, refinement occurred after settling, and background work was cancellable without blocking UI.

## 6. Reflow/OCR cancellation at that stage

Under the reduced scope, text/OCR reflow, local/cloud OCR backends, model management and recognition tasks were not developed. Existing file text layers remained usable; detecting their presence was not OCR and was outside the cancellation. Later restoration/implementation superseded this restriction.

## 7. Historical More settings specification

Options covered left/right, reversed left/right, up/down and full-screen-next page turns; auto-turn; page/percentage/no progress; chapter/time/battery; hiding headers/footers; document/page borders; watermark hiding/page cleanup; tap-turn/scroll when oversized; swipe-up menus mutually exclusive with vertical swipe-turn and inactive in scroll/zoom mode; and 256-gray smoothing. Existing annotations/excerpts stayed, without dedicated scanning/OCR settings at this stage.

Contextual options distinguished global preferences and per-book overrides. Non-reader screens did not force immersion; keyboard/system gestures remained normal. Unsupported hardware options were not meaningless switches.

## 8. Historical refresh and extraction/export cancellation

- Proposed refresh choices were normal/clear/fast/fastest plus full refresh every N pages (50 on the observed device), contingent on capability probing and real interfaces. Ordinary devices would not show ineffective modes. App dithering did not imply increased native screen gray levels.
- Region screenshots, region/whole-page recognition and original/processed-page/OCR-text export were cancelled at this stage. Existing note export, settings/database backup remained. Recognition/extraction were later restored as recorded below; page export was not.

## 9. Detection specification

PDF analysis combined effective text/coordinates, page size and dominant-image coverage to distinguish text, scans, scans with OCR layers, mixed, blank and cover pages. Dispersed initial sampling and per-page correction avoided judging from the first page or any text alone.

EPUB analysis followed OPF spine rather than filenames, considering XHTML/SVG images, actual text and coverage; excluding covers/contents/decorations; handling img, SVG image, large-image pieces and mixed chapters. Fixed layout did not prove a scan. A shared source exposed original pages/images/existing text/coordinates without generating OCR, retaining spine index, document order and resource location.

## 10. Processing engine and boundaries

Pipeline: parsing/type detection → page/region decoding/rendering → coordinates/crop/splits → enhancement/cleanup → original-page display → cache/position.

Existing PDF.js was reviewed first; PDFium/pdfrx were alternatives only if needed and compatible with Flutter, Android ARM64, macOS and licenses, with an actual backend rather than interfaces alone. OCR backends were excluded at that historical stage. Hanvon HVPdfInterface/`libhvpdfparser.so` informed boundaries only; proprietary implementation was not imported.

Watermark handling distinguished PDF-object display filtering from light-background scan cleanup. It was not universal removal: only display/copies changed, original comparison remained available, and blanket whitening/thresholding could not destroy text/figures. Inseparable content stayed.

Tiled rendering, adjacent prefetch and bounded caches used document identity, original page, crop, rotation, scale and actual enhancement parameters. Background work supported cancellation/progress/recovery. Opening did not automatically process/upload/vectorize the entire book. Reversible coordinates retained existing selection/location without the cancelled comprehensive annotation/search/listening adaptation. Handle/thread lifecycles had to remain stable across HID reconnects.

## 11. Historical acceptance and completion matrix

Required samples: text/pure-scan/text-layer-scan/mixed PDF, blank/cover, two-column papers, Chinese vertical text and comics; SVG-wrapped/non-filename-order image EPUB, text EPUB with an image cover and mixed EPUB.

Checks covered detection/manual correction, region order, odd/even crops, cancel/reset, persistence, original restoration, original coordinates, text layers, high-zoom memory, long documents and Bluetooth-pen reconnect with full screen/dialogs. Enhancement, hardware refresh and Hanvon visual effects had separate acceptance. Then-cancelled items were excluded from remaining work.

| Module | Entry | Engine | Persistence | Automation | Physical device |
| --- | --- | --- | --- | --- | --- |
| Original PDF baseline | Existing | PDF.js | Original reading position | Existing regressions | Not tested at this stage |
| PDF page analysis/text/coordinates | On-demand detection in Style | Actual PDF.js operators/text, coverage and boxes | Per-book type markers; page-evidence memory LRU | Real PDF samples passed | Pending then |
| Image EPUB detection/manual correction | Same panel | Spine/img/SVG/text candidate analysis; actual coverage pending then | Type markers/restore automatic | Candidate/order/persistence checks passed | Pending then |
| Local zoom/bounded cache | Preview/split reader 100%–1500%, fit/rotation/two-finger/wheel pan | Visible-region PDF.js refinement/window redraw; separate original/reader ROI/preview caches | Per-book scale/orientation/fit; normalized viewport restored for matching page signature; preview does not alter position | Coordinates/cancellation/pixels/real entry/control checks passed | Pending then |
| Crop/splits/paper/comic | Style crop/split editor and split-reading switch | Draggable frame, separate odd/even drafts, seven layouts/four orders, fit-region navigation/original switch; auto-crop/comic preset pending then | Local per-book layout/region; page > odd/even > book; changes invalidate old region index | Model/editor/persistence/navigation/cancel/failure and real PDF entry checks passed | Pending then |
| Continuous scrolling | Single/continuous reader controls | Sequential pages/regions, at most seven nearby committed frames, add/recycle on scroll, retained text layer/refinement | Per-book mode/normalized position; legacy default single; outside global backup | Prepend/append/recycle/retry/close/window/mode/real-entry checks passed | Pending then |
| Five enhancements/cleanup | Pending then | Pending then | Pending then | Pending then | Pending then |
| Refresh/more settings | Pending then | Device probing needed | Pending then | Pending then | Pending then |

Removed from this matrix at that stage: reflow, local/cloud OCR, extraction/page export and comprehensive scanned bookmark/search/listening/annotation integration. The following records span scope changes; old pending descriptions are not renewed authorization.

### Initial source review

Existing `assets/foliate-js/src/pdf.js` used bundled local PDF.js for page rendering/text extraction, then with whole-page canvases and unbounded Blob-URL Maps. No directly reusable local OCR backend was found. PDF.js would first provide per-page analysis/coordinates, then the matrix would proceed without rebuilding book storage.

### Stage one (2026-10-03)

- Style → Document Type Detection connected the real JS engine. Opening that panel sampled at most five dispersed pages/chapters; opening a book did not start OCR/network/indexing. Cancel stopped subsequent stages/pages and discarded the result of an already-issued PDF.js parse.
- PDF analysis used actual text, coordinates, rotation, image-operator transform stacks and area unions. Normalized text boxes kept all four corners. Existing layers had no invented OCR confidence (`null`); `image-with-text` did not prove OCR origin. Cropped/skewed/unsupported image groups were conservatively uncertain.
- EPUB sampled existing OPF-spine sections while retaining document/image order and excluding known cover/toc landmarks/non-body sections. Without rendered coverage it reported image-chapter candidates, not completed automatic image EPUB integration.
- Local `documentTypeOverrides` saved per-book corrections/restore automatic, explicitly without changing reading mode then. It stayed outside global settings transfers and did not overwrite another device's markers. Per-book cross-device config sync was not integrated.
- PDF images gained LRU limits of eight pages and a 24 MiB encoded-Blob target, allowing the two most recent spread images to exceed that target to avoid revoking the left page while loading the right. This was not total process memory.
- Whole-page canvases were limited to 4,194,304 pixels/4096 per side and released after rendering/encoding; eviction released HTML/image URLs, closing released resources and invalidated old async work. This was not 1500% tiled zoom; original zoom interaction was unchanged then.
- Eleven JS engine/lifecycle tests were added, including actual bundled PDF.js parsing of an original in-memory PDF. With existing progress/style/narration/selection checks, 147 JS tests passed; Flutter detection/storage/global-settings regressions passed 25. These did not establish Hanvon or native Android WebView acceptance.
- The recorded PDF-skill visual check and isolated Playwright browser used the existing original public three-page PDF. The first page/second spread (Chinese text plus image) displayed correctly; detection returned real text counts/image areas. Incorrect layout caused by the test page's own `display:flex` override was fixed only in ignored test-page CSS, without changing production layout.
- Standard Dart analysis found no errors/warnings or new-file diagnostics; `epub_player.dart` retained nine missing-brace notices. Flutter analysis CLI encountered LSP encoding errors in the Chinese path; legacy analysis-server protocol/in-memory configuration bypassed incompatible old custom_lint without changing repository config or claiming plugin validation. Webpack succeeded with three existing async-syntax target warnings.
- No packaging/installation/publication occurred; Preview 3 tag/assets stayed. Crop/splits, five enhancements, text/OCR reflow, OCR backend, export and hardware refresh were still pending then, so this was not complete specification delivery.

### Stage two: local rendering and coordinates (2026-10-03)

- Continued under the user's development-document instruction without packaging/publication/installation, version/tag/remote-release changes or selection-logic changes.
- Added `document-regions.js` with normalized original-orientation coordinates and invertible extra 0/90/180/270° rotation/crop transforms, avoiding screen pixels as permanent annotation positions. Seven layouts and horizontal/vertical/left/right orders retained original page indices; page overrides took precedence over odd/even and whole book. Only model tests were connected then, without drag/apply/save UI.
- Added `pdf-region-renderer.js` using real PDF.js viewport/render transforms. Preview at 100%–1500% neither stretched low-resolution pages nor created 15× whole canvases. Output was bounded at 2,097,152 pixels/2048 per side, with one serial render/encode canvas released on completion/failure/cancel. PDF.js source decoding/object overhead remained, so this was not a process-memory limit.
- Instance-isolated caches keyed original page, visible rectangle, extra rotation, scale and output size, limited to four entries/8 MiB. Enhancement/OCR were not yet present, so no fictitious parameters were used; future integration required more keys. Rapid updates cancelled old RenderTasks, stale unstarted work created no canvas, and closing invalidated work/cleared caches. No background OCR/upload/whole-book prefetch was added.
- Style → Detection → PDF Local Preview appeared only for actual PDF results. It started at the current original page and offered zoom/minus/plus, pan, right rotation, original reset, previous/next page, retry/close. Inputs coalesced at 90 ms; stale bridge replies were ignored and window changes requested new images. This separate temporary preview neither replaced the reader nor supported selecting/annotating its image or changed progress/source/annotations.
- Twelve JS model/lifecycle tests brought the total to 159; four Flutter preview tests plus one PDF/EPUB visibility case brought detection/preview/storage/global-settings tests to 30. Cases covered rapid updates, stale replies, retry, close during request, narrow screens, zoom/pan bounds, rotation and original page indices.
- Recorded PDF/Playwright checks used isolated Chromium and the original three-page PDF. Region images at all four rotations matched corresponding whole-page crops pixel-for-pixel, maximum channel difference 0. Chinese/English 300% and local 1500% images were inspected; the latter output was 1130×1600, not a whole-page giant. Temporary pages/images in ignored `output/playwright/` were not native Android/Hanvon acceptance.
- Standard analysis had no new diagnostics/errors/warnings; nine existing brace notices and three Webpack target warnings remained. Legacy analysis protocol was retained without changing lint config. No test installer was generated/installed.
- The then-next stage was crop-frame/odd-even editing, split preview/confirm/cancel and per-document saving, followed by reader region navigation/image EPUB sources. Enhancement, reflow/OCR, export and hardware refresh were not marked complete.

### Stage three: crop/split editing and local saving (2026-10-03)

- Style → Detection → PDF Local Preview → Crop and Splits added a real original-page preview, four draggable corners/frame movement, seven layouts and four numbered orders. Original-page normalized coordinates were saved, without source overwrite or millimeter claims.
- Regular mode supported current page/whole book; odd/even mode retained independent drafts and real-page previews. Only Confirm saved; Cancel/Back discarded drafts and Reset restored the current draft to an original single page. Whole-book application cleared finer overrides. Odd/even application cleared page overrides only for that parity; only changed groups were saved, or the current group if neither changed.
- New `DocumentLayoutStore` saved local per-book `documentPageLayouts`. Serialized writes prevented simultaneous-book data loss; failures rolled back preference caches and kept drafts for retry. A corrupt full configuration was not overwritten/cleared silently. The key stayed outside global settings transfer; cross-device book config remained separate work.
- Preview applied saved layouts with previous/next region, cross-page navigation, rotation, 100%–1500% zoom and original comparison, retaining original indices through rotation. This still applied only to a separate preview, not the reader/progress/selection/annotations; restoring position after leaving a region was not implemented.
- Tests found/fixed corners visible outside parent hit areas but undraggable, and failed cross-page retry returning to the old page. Handles gained internal hit space; retry retained the actual target page/direction. Phone controls gained visible scrollbars; desktop controls aligned near the top.
- Recorded regressions: 48 Flutter cases for geometry, override scopes, concurrent saving, write failures, cancellation/stale replies, all corners, narrow portrait/landscape, navigation and global-settings isolation; 159 existing JS reader/narration/selection/document cases. Selection logic was unchanged.
- The PDF-skill visual check used the original PDF raster with actual Flutter editor components at 390×844 and 1100×760, inspecting crop, numbers, mask, controls and scrolling hints. One separate visual test passed. This was not native Android WebView/Hanvon acceptance; temporary output remained ignored.
- Standard analysis had no new errors/warnings using the existing legacy protocol, with no lint-config change. Documentation/matrix updated without packaging, installation, publication or Preview 3 changes.

### Stage four: split reading and region position (2026-10-03)

- PDF Style added Read with Crop and Splits and a direct editor entry without requiring detection. Initially off, it applied saved crops/parity/layout/order to the reader; disabling returned to the same original page's spread. Failed editing/application preserved the old config for retry.
- `FixedLayout` navigated regions before original pages, reversing into the prior page's last region. Contents/page jumps retained original indices and existing buttons/tap zones/desktop keys. This was fit-screen single-region reading; reader 100%–1500%, scrolling and complete scan menus remained pending, with high zoom only in preview then.
- A separate `readingRegionRenderer` rerendered visible crops rather than stretching low-resolution pages. Reader/preview cancellation and four-entry/8 MiB caches were separate; each canvas retained the 2,097,152-pixel/2048-side limit, not total memory. Original HTML/text reused the bounded whole-page cache; first entry still generated a whole-page base image.
- Original text/link DOM order and CFI remained, with image-source/viewport transformation only. Iframe clicks used real transforms; text CFI selected its containing region. A cropped-out target temporarily showed the full page without modifying saved crop. Existing PDF annotation/search overlay limits remained; navigation work was not comprehensive scanned annotation support.
- Per-book local `pdfReadingStates` retained enabled state, original CFI, region index and layout signature only after accepted progress saves. Reopen required matching CFI/page/signature/index. Layout/order changes started at the page's first region. Initial sync handshake preserved restored same-page regions; later remote jumps did not force old local positions. The key stayed outside global backup; cross-device region sync was absent.
- Candidate pages replaced visible frames/reported positions only after loading, rendering and decoding. Failure kept old frames/position, retry kept target and close/stale work could not overwrite. Iframe remount image loss was fixed; original switching also used candidate commits. Real entry checks found missing fixed-layout `writingMode` and added safe reads without restoring the reverted selection change.
- Recorded automation: 51 Flutter and 167 JS passed, adding three region-order/restore cases and five reader navigation/failure/stale/location cases. Node tests simulated shadow-root iframe loading unsupported by jsdom, not PDF pixel acceptance. No new analysis diagnostics; nine existing brace notices remained.
- PDF/Playwright checks in isolated Chromium used the original three-page PDF: 12 real `FixedLayout` assertions, production `index.html` → `book.js` restore/bridge events, initial/later sync, same-page region progress, text targets inside/outside crops and original-spread switching. Screenshots at 1100×800/390×844 were inspected, not Android/Hanvon/touch/Bluetooth device acceptance. Temporary QA output stayed ignored.
- Bundled JS was regenerated with three existing Webpack target warnings. No packaging, installation, publication, version or Preview 3 tag changes; documents/matrix updated.

### Stage five: high-zoom reader viewport and rotation (2026-10-03)

- With crop/split reading enabled, reader controls provided 100%–1500% slider/minus/plus, fit screen/width, left/right 90° rotation, fit reset and four-direction movement. Zoom was relative to the fit mode; fit width started at the region top, not an absolute physical paper size. Disabling returned to original without changing the default.
- `pdf-reading-viewport.js` unified crop/rotation/viewport/original-page affine transforms. High zoom requested only visible source rectangles within 2,097,152 pixels/2048 per side. A bounded base image displayed immediately during movement, followed by refinement after 100 ms coalescing. Failure retained the base and later adjustment retried rather than blanking the page. Window changes recalculated/refined.
- Text/link node order stayed. A noninteractive fine-image layer appended after body nodes preserved CFI paths; image/text rotated together. Fixed-layout clicks/selection-toolbar positions at 90°/270° were fixed through four-corner mapping rather than scale alone, without claiming complete PDF overlay adaptation.
- Two-finger pan and desktop-wheel pan retained single-finger selection/page turns. Two-finger input was intercepted until both fingers left, including one-finger tails/following clicks, to prevent accidental page turns. Direction buttons offered an alternative. Pinch zoom and reverted automatic selection turns were not added.
- `pdfReadingStates` added per-book viewport settings/normalized original-page center with validation, serialized merge, rollback and global-backup isolation. Restore required matching page/layout signature; new regions started at their beginning and text jumps centered on the target. Existing accepted-position saves retained viewport movement without changing original CFI encoding.
- Recorded regressions: 54 Flutter, 178 JS passed for rotations, 1500% visible rectangles, fit-width bounds, window/center, toolbar corners, gesture tails, stale fine images, concurrent viewport saving and control recovery. New-file analysis was clean; nine existing INFO notices remained. Old custom_lint validation was not claimed.
- PDF/Playwright checks used the original PDF through production `index.html` and a Flutter bridge simulation for all four rotations, 1500%, wheel pan without crossing pages, position events and 1100×800/390×844 redraw. Original text-layer reads worked in all rotations. At 1100×800, the 1500% fine image was 1100×799, not a full-page enlarged bitmap. Ignored output retained screenshots; real Flutter phone-width controls were also checked. These were not Android WebView/Hanvon device checks.
- Single-region viewport operations were complete then; continuous scrolling remained pending rather than equating pan with scrolling. Image EPUB, automatic crop, enhancement, reflow/OCR, export and refresh followed the then-plan. JS rebuilt without packaging, installation, publication, pushing or Preview 3 changes.

### Stage six: continuous scrolling across pages (2026-10-03)

- Reader PDF controls added single/continuous modes when crop/split reading was enabled. Original pages/splits formed a genuinely continuous sequence with adjacent pages visible, rather than instantaneous bottom-of-page switching. Old data defaulted to single; fit reset kept mode. Buttons moved 80% of viewport height and chapter jumps used original pages.
- `pdf-scroll-layout.js`/`pdf-scroll-reader.js` kept at most seven nearby committed frames, adding near edges, recycling distant frames and compensating scroll when prepending/removing. Current/selected frames were protected; candidate switching could temporarily add frames. This was not process-memory or PDF.js-resource limitation.
- Original text, links, numbering and CFI stayed. Bounded base images preceded serial visible-region refinement after 100 ms; no high-zoom whole-page bitmap. Neighbor prefetch could start during gestures. Long presses/selections were not forced into single-finger scroll. No inertia simulation, pinch zoom or reverted selection auto-turn was added.
- Failure retained content and stopped directional automatic retry until user retry. Mode changes prepared candidates first and rolled back on failure; close discarded incomplete loads. Previously announced frames did not duplicate listeners during recovery; background loading did not resend location events when unchanged.
- Per-book mode/original coordinates restored the same original page across modes. Window-resize drift from using the new viewport to infer the old location was fixed by recording original-page center then restoring it; scrollbar width was accounted for. Preferences remained local/outside global backup, without source changes.
- Recorded regressions: 55 Flutter, 187 JS passed for defaults/saving, mode changes, rotations/high zoom, prepending, seven-frame recycling, retry/close, split order, selection protection and resize. No new standard-analysis diagnostics; nine brace INFOs and three Webpack warnings remained.
- PDF/Playwright production-entry checks on the original three-page PDF covered scroll restore, cross-page CFI/position, chapter jumps and single-mode return; 1100×800/390×844 screenshots were inspected. Mapping the same three test sources to 50 logical pages checked seven-frame limits, sequence and resize through back-and-forth scrolling. This was window stress, not decoding performance for 50 distinct pages. Android touch/Bluetooth/Hanvon acceptance remained pending.
- JS regenerated without packaging, installation, publication, pushing or version changes. Preview 3 tag/remote assets stayed.

### Historical dependency order after stage six

This was the order at stage-six completion. Menu routing/import detection followed the later isolation supplement and section 2; opening-time automatic sampling was not to be restored.

1. Complete automatic crop, margins and comic presets on the existing crop/parity/split editor/storage.
2. Integrate actual EPUB image dimensions/coverage and shared original-image sources while preserving mixed chapters/text EPUB.
3. Implement five distinct enhancement algorithms, cancellable/coalesced preview and original comparison, without processed-page export.
4. Complete retained original-page preferences, UI/hardware capability probing and native touch/Bluetooth/long-document/sample-matrix acceptance.

OCR, reflow, extraction/export and comprehensive scan integration were cancelled at that time, outside the queue; publication still required separate authorization. The later restoration below superseded the corresponding OCR/reflow/extraction cancellations.

### Menu isolation supplement: import-time classification (2026-10-03)

- Review found `isImageEpub` only checked the EPUB extension, exposing image tools to ordinary books, while detection appeared for every format. Import classification then gated new entries to PDF/confirmed image EPUB; other styles stayed at Preview 3 and other reading-settings pages were unchanged.
- Detection joined the import WebView's `getBookMetadata` flow parallel to cover reading. `onMetadata` returned classification, saved to local `documentReadingModes` after successful import, including book identity, existing fingerprint and format version. It did not travel with global settings. Reimport updated it; changed fingerprints invalidated old classification.
- Reading only loaded preferences, without sampling/hash/rechecks. Unclassified EPUBs retained old menus; PDFs needed no analysis to choose original-page menus. First valid classification enabled the new mode while retaining explicit opt-out.
- TXT/Markdown conversion and cover recovery did not sample. Timeout/failure kept original menus without blocking valid imports; sources/content were neither modified nor uploaded.
- Recorded regressions: 207 JS, 51 Flutter passed; standard analysis had no errors/warnings apart from existing notices; bundled JS rebuilt with three target warnings. Isolated Chromium used original EPUB fixtures for import classification, cached opening, no-cache/no-detection, cover recovery and text books with image covers. No physical-device acceptance, testing, packaging, installation or publication occurred in that stage.

### Hanvon-inspired panel layout (2026-10-04)

- Reference assets were received/verified/saved as indexed in section 1. They stayed local, outside product packaging/public uploads.
- PDF/confirmed image EPUB bottom quick panels used a separate high-contrast monochrome theme, grouping zoom, mode, crop, layout, five-enhancement overview and rotation. Wide-screen labels aligned left; narrow/large-font layouts wrapped without horizontal scrolling.
- Only document style panels widened up to 1100 logical pixels, capped at 62% screen height with text visible above. Responsive panels avoided IntrinsicHeight measurement to prevent LayoutBuilder intrinsic-size errors. Ordinary-book layouts retained the previous 600-width path.
- Crop/margins/comic/paper columns remained in a separate confirmed preview, without ineffective quick toggles. Crop preview remained accessible after original-region reading was disabled.
- The bottom enhancement panel kept text above it and value/minus/slider/plus/reset per row; narrow resets used tooltip icons. Back/Cancel did not save; Confirm used existing store/rendering without altering original images.
- Returning from preview refreshed the overview, retaining async error messages, duplicate-action disabling and cancellation. Gear StyleSettings remained byte-identical to Preview 3 at this stage.
- Recorded 51 Flutter regressions passed for 320×740, 844×390, 1024×1366, 1440×900/large fonts, engine calls, enhancement reachability/save/cancel, crop and ordinary-book isolation. Reader-page analysis was clean and reader-control directories retained existing INFOs. No device checks, packaging, installation or publication occurred.

### Visual/pixel verification of enhancement (2026-10-04)

- The dedicated PDF/image EPUB quick-panel gear was removed at this stage; ordinary-book gear/Preview 3 advanced styles were unchanged. The later OCR-style gear restoration is recorded above.
- The PDF visual-verification workflow rendered page 30 of a user-supplied scan and synthetic gray-background/light-text/thin-line/color/blur samples. Inspection/pixel comparison showed stroke expansion, contrast separation, darker midtones, lighter paper and sharpened edges. Minimal bleaching on pure-white paper was expected; all-zero parameters preserved pixels.
- Existing algorithms were checked against OpenCV [morphological local minima](https://docs.opencv.org/4.13.0/db/df6/tutorial_erosion_dilatation.html) and [convolution sharpening](https://opencv.org/blog/image-filtering-using-convolution-in-opencv/), without new dependencies/copied third-party code.
- Isolated Chromium with bundled PDF.js, real Canvas and image EPUB sources checked original, five individual/combined enhancements and Reset across 16 groups. Pixels matched expectations and reset restored originals. The image EPUB used an original fixture, not native-installer end-to-end acceptance.
- Tests added parameter semantics/intensity, unchanged source pixels, cache reset, single/scroll/later-page parameter propagation and five-row increment/individual/all reset. Recorded 51 JS and 28 Flutter passed. Private pages/comparisons/scripts stayed in ignored `output`, without packaging, installation or publication.

### Per-page automatic crop (2026-10-04)

- Automatic crop became persistent rather than a one-time rectangle. Enabling defaulted to whole-book scope; each original page computed its own content bounds, shared by single/scroll and split order. Parity scopes/manual page overrides stayed.
- The editor added Per-page Automatic Crop, retaining margins and repreviewing the current page when reopened. Dragging switched to manual; all changes stayed drafts until confirmation.
- Bright-paper background estimation excluded only long peripheral dark borders/scan frames connected to the edge, retaining thin lines, footnotes and numbering. Blank/full-bleed/uncertain pages kept full bounds; failure never reused the previous page's crop.
- A separate low-resolution source avoided competing with reader refinement cancellation. At most 64 coordinate-bound groups were cached, without detection PNG encoding, OCR dependencies, DOM/CFI/source/ordinary-menu changes.
- Recorded 87 JS and 35 Flutter regressions passed; the existing raster scan sample changed from `uncertain-border` to valid content bounds. No packaging, installation or publication occurred.

### Text/OCR reflow inside the reader (2026-10-04)

- Text Reflow/OCR Reflow for PDF/confirmed image EPUB directly replaced reading-area content, without extraction/range dialogs. Text Reflow preferred existing layers and used local OCR when missing; OCR Reflow forced recognition.
- Processing used the current original page and, when cropping was enabled, that page's complete manual/automatic crop boundary. Split cells, viewport zoom and panning did not shrink scope to the visible cell. Moving pages resolved that page's crop; only Extract opened region selection.
- Reflow reused existing selection menus, user tool switches/order, custom AI templates, context options and highlight/underline deletion. The original WebView stayed mounted with auto-turn paused while hidden; return retained original positioning.
- Annotations used original-page + text-version + UTF-16 range anchors, never masquerading as original EPUB CFIs. Note jumps/export links recognized these anchors; mismatched text versions did not force old annotations.
- Local caches keyed book/page/mode/OCR-model-version/crop/watermark options and retained immutable text versions for notes. They were not source files or settings-sync content; missing results were reconstructed per page and text versions checked.
- Styles applied directly in the reading area, with return/previous/next page, Stop and model settings. Missing models prompted explicitly rather than background downloading, whole-book preprocessing or automatic AI sending. Selection narration read selected reflow text rather than hidden original content.
- Ordinary books retained their original reader/menu. No packaging, installation or publication occurred at this stage.

### Scanned-page watermark enhancement (2026-10-04)

- Existing `hideWatermarks` hid optional PDF content groups whose names matched `watermark` or the Chinese watermark label, not marks baked into images. The separate layer toggle remained.
- The five-enhancement panel gained a sixth control, Scanned Watermark Fading, 0–100/default 0 off. Preview/original comparison, increments, individual/all resets and Confirm/Cancel shared the existing flow; missing legacy fields defaulted to 0.
- The local raster algorithm estimated light paper, built grayscale/color masks, protected dark text/adjacent antialiasing and filtered connected components to exclude small light text, thin lines and large solid blocks before fading candidates toward paper color. Processing preceded darkening/sharpening and was shared by PDF/image EPUB/single/scroll.
- This conservative heuristic was neither semantic watermark recognition nor obscured-text reconstruction. Light large headings/artwork could be mistaken; dark/complex/overlapping marks could remain, with an original-comparison notice. No model, Python, OpenCV or runtime dependency was required, and sources/text layers stayed unchanged.
- Processing retained the 2,097,152-pixel rendering budget, yielded in batches and supported cancellation, committing only complete output. Cache keys included fading strength. A synthetic 1200×1600 Node sample took about 176 ms for this control alone, specific to that sample/environment.
- References informed foreground/background separation, color/threshold masks and masked repair; no referenced code, entire repair library or generative model was imported:
  - [ScanTailor Advanced](https://github.com/4lex4/scantailor-advanced)
  - [pdf-watermark-remover](https://github.com/banatibalazs/pdf-watermark-remover)
  - [OpenCV masked inpainting](https://docs.opencv.org/4.13.0/df/d3d/tutorial_py_inpainting.html)

### E-Ink document refresh toolbar (2026-10-04)

- PDF/image EPUB panels gained compact Hanvon-inspired Refresh Now and every-N-original-pages controls with ±1/±10. Zero was off/default; range 1–100. The group appeared only with E-Ink mode enabled; disabling hid it/cancelled pending refresh, preserving ordinary-book menus.
- Original-page transitions/`readingAction` drove counting. Initial load, same-page splits/zoom, style reflow and sync relocation did not count; a cross-page jump counted once. Rapid turns coalesced and waited for a stable page. Panels/background/hidden originals during reflow stopped automatic refresh; successful manual refresh reset counts.
- Android probing bound `android.os.EinkManager`/`eink` service's one-shot `sendOneFullFrame()`, requiring resumed Activity/window focus. It did not set system properties, request privileges, change persistent waveforms or simulate hardware refresh through Flutter repaint/black-white flashing. Missing/restricted interfaces disabled the action with system-refresh guidance; failures did not claim success.
- This did not establish support for every Hanvon firmware. Firmware determined actual waveforms; unverified normal/clear/fast/fastest modes were not fabricated. No E-Ink device was connected; recorded verification was automation/compilation only, without packaging/installation/publication.
- The page-count preference joined global settings backup/restore and validation; hardware-capability results did not.
- Interface reference: [KOReader RK35xxEPDController](https://github.com/koreader/android-luajit-launcher/blob/master/app/src/main/java/org/koreader/launcher/epd/rockchip/RK35xxEPDController.kt). The binding was independently written without copied implementation/vendor binaries.

### Multi-format image books and import classification (2026-10-04)

- EPUB, MOBI, AZW3 and FB2 shared image-book detection at import with at most five body sections. MOBI/KF8/FB2 reused already-parsed image resources, excluding cover/contents evidence. Opening read the saved result without new sampling.
- Remote-library import reused local classification; WebDAV downloads for existing bookshelf entries populated local results without duplicate books, position changes or new vectorization.
- Bookshelf actions Set as Scanned Image Book and Restore Ordinary Reading were added. Manual decisions overrode automatic results for the same source and expired on replacement. Scan mode used document menus/crop/enhancement; ordinary text books retained their interface.
- Scan reading did not bind image single-click preview, long-press options or image-footnote actions. JS event exits and Flutter image bridges intercepted those paths, leaving taps to existing page/menu behavior. Ordinary illustrations were unchanged.
- Recorded 25 JS and 37 Flutter targeted regressions passed for classification persistence/manual restoration, remote-library UI, scan image events and ordinary illustrations. No packaging/publication occurred.

### Automatic crop text-boundary correction (2026-10-04)

- A fixed paper-color-difference threshold was replaced with local contrast/connected-stroke bounds to avoid yellow paper/binding gradients inflating crops. Dark paper was supported, retaining full-page fallback for pure-black/uncertain full-bleed pages.
- Inset scan frames, peripheral broken thin borders and isolated noise were filtered; small punctuation near content stayed. Headers, page numbers, footnotes, thin separators and artwork contributed to bounds. Default margins/manual rules remained.
- The shared raster algorithm covered PDF/scanned image books with independent per-page computation/cache, without OCR/models/whole-book analysis. Batched cancellation and 2MP detection remained.
- Original pages 20/50/51/100 of the user's PDF were locally compared before/after crop. Page 51's old bounds nearly covered the full page; corrected bounds removed the broken left border/outer space while retaining header/footnotes. Private pages stayed in ignored local diagnostics, outside the repository.

### OCR model cards and local deletion (2026-10-04)

- OCR settings reused BGE settings groups, source selection, cards, recommended/current badges and buttons, listing all lightweight models with V4 recommended. Cards displayed size, actual upstream/mirror, verification state/progress, download/use, switching, reverification and cancellation.
- Confirmed deletion removed only that model's local incomplete/corrupt files, preserving books, reflow caches, recognized text, other models and selection. Afterwards it returned to optional-download state.
- Only manifest-listed model/temporary files were deleted, never recursively removing directories. Recognition/download/deletion were mutually exclusive, with state rechecks after failure. A completed older download could not overwrite a selection changed through settings import/sync during download.

### Image-book detection, crop entry and window resizing (2026-10-04)

- Fixed false negatives for fixed-size comic pages: a complete 650×904 image could not use empty space in a 1000×1200 detection iframe as its coverage denominator. Safely renderable pages without visible text used actual image-union bounds, retaining tile order/internal spacing. Decorations, text-bearing pages and unknown rendering effects stayed conservative.
- Image-book Crop and Splits shared PDF's direct editor, returning to the menu on Confirm/Cancel. Text/unsupported layouts retained original content and allowed explicit adjacent-page selection, without skipping chapters automatically.
- Removed forced `inset:0!important` base-image styling that overrode crop coordinates. Fine-image layers in single/scroll readers gained separate markers so original-illustration hiding did not hide them too.
- Originals/cropped regions fitted actual window, page/width mode and user zoom, recalculating on resize. Ordinary text books did not enter the adapter; import remained limited to five sections and opening did not redetect. Older false-negative caches could be corrected through the bookshelf action; new imports used the fixed detector.
- Recorded 77 JS and 41 Flutter tests passed. Two private AZW3 comics checked classification/display/crop. Real-browser checks covered original/cropped × three windows × two fit modes × two zooms (24 groups), plus scroll resizing/fine-layer visibility. Private diagnostics stayed ignored. Standard Dart analysis passed with the incompatible existing custom_lint disabled only in analyzer memory, without config changes; reader JS rebuilt.

### MOBI6 image-record reference detection (2026-10-04)

- Legacy MOBI raw body referenced `img[recindex]`, with `src` generated only after section loading. Earlier import checks for `src`/`href` treated these pages as blank. Valid positive record indices became candidates, then the existing loader decoded/checked dimensions, visibility and coverage; record IDs alone did not establish a scan.
- Import still sampled at most five sections; opening did not redetect. Text-bearing illustrated books, invalid records/load failures retained ordinary fallback. Existing classifications were not silently rewritten; manual bookshelf correction remained available.
- A private 255-section MOBI comic reproduced the issue and then classified/displayed through the image reader. Recorded 48 related JS tests passed and JS rebuilt. Source books/screenshots were not added; no new packaging occurred at this stage.

### Official candidate documentation

- [PDF.js API](https://mozilla.github.io/pdf.js/api/)
- [pdfrx](https://pub.dev/packages/pdfrx)
- [pdfrx_engine](https://pub.dev/packages/pdfrx_engine)
- [OpenCV thresholding](https://docs.opencv.org/4.12.0/d7/d4d/tutorial_py_thresholding.html)
