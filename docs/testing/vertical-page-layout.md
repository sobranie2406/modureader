# Vertical reading page layout

> Historical record of the implementation and checks described below. No release version or verification date was specified; this is not certification of the latest 1.2.0 release. See the [documentation index](../README.md).

## Usage

- Reader → Reading settings → Text direction: select “Vertical.” “Auto” also used vertical sidebars when the book itself was vertically typeset.
- A “Vertical red frame” switch was added in the same area, off by default. Enabling it displayed a red double frame, left/right sidebar separators and thin rules between body-text columns.
- Body text and both sidebars shared the full-page background color/image, including image blur and opacity. Body column rules were calculated from actual visible text positions and redrawn for font size, line spacing and page turns, without covering images spanning columns.
- Chapter titles moved to the right; remaining chapter pages and whole-book position moved to the left. Chinese interfaces used Chinese numerals, for example `本章剩余四十页` (“forty pages remaining in this chapter”) and `四十五·一千二百三十九` (“forty-five · one thousand two hundred thirty-nine”); Traditional Chinese used `剩餘` (“remaining”) and `頁` (“pages”).
- Whole-book position retained the reader's virtual page positions, not original printed page numbers. Long sidebar titles were truncated without covering body text.
- Horizontal writing retained existing headers/footers, with no red frame or reserved vertical-sidebar gaps. Fixed-layout content was outside this reflow change.
- Footnote popup dimensions followed the actual writing direction. Vertical writing swapped the horizontal width/height strategy; overlong content scrolled left/right without vertical drift, while horizontal writing retained vertical scrolling. Both retained a 25% screen-area limit, 80% body-text font size and trailing whitespace; short footnotes still shrank to fit.
- Footnote size was based on the actual normal-body CSS font size in the paragraph at the click position, not the reference number, superscript or reading-setting em value. Body spans with book-specific font sizes were included in measurement. Nested em/percentage/fixed sizes in the popup were normalized to 80% of that base, retaining bold, italic and the relative sizes of actual superscripts/subscripts. Nested footnotes reused the original body base without shrinking at every level.

## Implementation constraints

On Mac, frames and sidebars were drawn inside the WebView renderer's shadow root. All decorative nodes used `pointer-events:none`; no full-window Flutter paint layer was placed above WKWebView. `IgnorePointer` controls only Flutter hit testing and cannot ensure mouse-event passthrough over a macOS native view. Other platforms retained Flutter sidebars at the time: Windows / Linux plugins used Texture and Flutter Listener input forwarding, unlike macOS AppKitView.

The actual text area was inset using physical padding on the renderer host rather than by moving the WebView, so iframe DOM coordinates included the sidebar offset. Sidebars accounted for system safe areas and header/footer font sizes. Mac and other platforms shared Chinese-numeral and label formatting. Page-number changes updated only decorative nodes, without a full changeStyle, repagination or changes to chapter DOM or CFI.

Changing text direction updated both chapter iframe and paginator direction caches, laying out in place without navigating to another chapter to refresh, so it did not create additional reading history.

## Verification

- `flutter test test/widgets/vertical_page_chrome_test.dart`: Chinese numerals, Traditional Chinese, English, switch persistence, left/right sidebar positions and safe areas.
- `node --test test/vertical_page_chrome.test.mjs`: physical margins, horizontal restoration, automatic direction and headless rendering.
- `MODU_JSDOM_ROOT=<jsdom安装目录> node --test test/vertical_web_chrome.test.mjs`: mouse passthrough for all decorative nodes, safe title text, in-place page-number updates, red-frame switching and horizontal/headless cleanup. The historical placeholder means the jsdom installation directory.
- `test/reader_footnote_typography.test.mjs` and `test/fixtures/footnote-typography.html`: actual FootnoteHandler click paths, reference-number versus paragraph font size, nested small-font overrides and fresh measurement on every opening. WebKit verified that body text at 30px, reference numbers at 10px and original footnote styles at 9px produced an actual footnote size of 24px.
- `test/fixtures/vertical-input.html`: synthetic footnote-click and page-turn cases using the actual renderer/view. The macOS native comparison entry, `test/fixtures/mac_vertical_input_harness.dart`, did not initialize personal libraries or sync services.
- Regressions: reading navigation, search, selection styling, continuous chapters and TTS cursors.
- Isolated synthetic book pages in Playwright: verified right-to-left vertical writing, page turns and switching between horizontal/vertical writing in paginated/scrolling modes in a 390×780 viewport.
- The reader compatibility bundle was regenerated. Mac native synthetic-page comparison: with the old full-screen Flutter red-frame layer enabled, mouse clicks did not turn pages. With the old layer disabled and only WebView decorations retained, a click at the same position turned pages normally and footnote links opened popups. Windows/Linux device acceptance was not performed; mobile retained its original drawing approach.
