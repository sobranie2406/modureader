# Cross-chapter annotation alignment

## Reproduction and cause

`test/fixtures/annotation-scroll-alignment.html` runs the actual reader with
twelve synthetic chapters, persisted-in-memory highlight CFIs and newly added
underlines. No personal book or database is used.

Before the fix, crossing from chapter 4 into chapter 5 produced an approximately
32 px upward offset for restored highlights and new marks. Crossing backward
into chapter 3 produced the same offset. The size corresponded to the chapter
padding. The initial chapter's overlay was aligned because it underwent another
layout pass; newly activated preloaded chapters attached overlays after layout,
without initializing their dimensions and margins.

Range rectangles were also treated as SVG coordinates even though they came
from the child iframe's viewport. Internal scrolling could invalidate cached
rectangles without a resize. The user's progressively growing backward drift
was not reproduced as growing drift in Chrome; the coordinate and scroll
invalidation paths are now covered explicitly in unit tests.

## Fix

- Initialize overlay layout on attachment, without recursively notifying chapter
  activation through the layout callback.
- Convert chapter viewport coordinates through the actual iframe and SVG
  transforms for drawing and hit testing.
- Recalculate marks on cached-chapter activation and coalesce iframe/inner
  scrolling redraws per animation frame.
- Hit-test current ranges even before a queued redraw; remove listeners and
  pending redraws when a chapter is destroyed.
- Keep annotation CFIs, saved text and existing highlight/underline styling.

## Verification (2026-09-15)

- 156 reader JavaScript tests passed, including coordinate transforms, padding,
  parent-scroll invariance, internal scrolling, hit testing and lifecycle cleanup.
- Browser checks: 8 page turns forward, add an underline, 20 page turns backward,
  add another underline, change font size, leave and reopen the chapter.
- 33 checked states; all measured offsets below 1 CSS pixel. Up to 22 loaded
  annotations were checked per state, across chapters 1–5.
- Screenshots: `output/playwright/annotation-before-fix.png`,
  `annotation-after-fix-forward.png`, `annotation-after-fix-backward.png`.
- Reader bundle rebuilt. These are isolated Chrome reader tests; installed
  Android/iOS/macOS/Windows apps were not tested or rebuilt in this change.

Run the suite with:

```sh
MODU_JSDOM_ROOT=/path/to/jsdom-project node --test test/reader_*.test.mjs
```
