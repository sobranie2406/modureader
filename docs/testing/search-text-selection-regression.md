# Search text-range regression

## Change

Search results now paint the actual chapter DOM ranges with CSS custom
highlights instead of parent-frame SVG boxes. The fallback for older WebViews
paints clipped text-node fragments inside the chapter document without borders
or extra padding. Neither path changes book text nodes or takes over the real
selection used by annotations, translation and TTS.

The matcher now preserves original UTF-16 offsets, handles exclusive end
boundaries and overlapping matches, segments across inline tags, and preserves
source offsets while normalizing whitespace. Excerpts no longer confuse node
indices with text values. Search cancellation clears all live chapter marks
synchronously; closing a book invalidates pending search results.

## Automated checks

```sh
MODU_JSDOM_ROOT=/path/to/jsdom-project node --test test/reader_*.test.mjs
```

`reader_search_ranges.test.mjs` covers exact text, nested inline nodes, empty
nodes, chapter-end hits, overlapping results, repeated equal text nodes,
Unicode offsets, whitespace, whole words, CFI round trips, native range
registration, preserving manual selections, and fallback cleanup/geometry.

## Browser verification (2026-09-15)

Serve the repository locally and open
`test/fixtures/search-text-selection.html`. This uses the actual View and
Paginator with three synthetic chapters containing six matches each.

Checked in an isolated Chrome browser through Playwright:

- All 18 results and their registered ranges contain exactly `革命`.
- Next through all three chapters, previous result, and returning to cached
  chapters preserve correct ranges.
- Font-size changes, width changes, CSS zoom and dark theme keep native
  highlights attached to text; no outline is drawn.
- A manual selection of `革命` remains usable while search is active, and
  closing search does not clear that manual selection.
- Closing search removes marks from all loaded chapters.
- `?fallback` disables the native Highlight constructor for the test: checked
  text fragments, scrolling, pagination, zoom, and cleanup with screenshots.

Local screenshots: `output/playwright/search-selection-*.png` (not release
assets). This is browser-level verification of reader code, not an installed
Android, iOS, Windows or macOS application test. No new APK/app was built or
installed for this change.
