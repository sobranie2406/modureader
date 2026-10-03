/// Reflow inside the WebView's viewport, independently of the surrounding
/// reader/popup. No app bridge, book data or provider credentials are exposed.
String popupPageLayoutScript(int percent) {
  final scale = percent.clamp(50, 200) / 100;
  return '''
(() => {
  const root = document.documentElement;
  if (!root) return;
  root.style.setProperty('zoom', '$scale', 'important');
  // CSS zoom enlarges content, not the layout viewport. Compensate its width
  // so 200% means larger text that wraps, not a page twice as wide.
  root.style.setProperty('width', '${100 / scale}vw', 'important');
  root.style.setProperty('max-width', '${100 / scale}vw', 'important');
  root.style.setProperty('min-width', '0', 'important');
  root.style.setProperty('-webkit-text-size-adjust', '100%', 'important');
  root.style.setProperty('text-size-adjust', '100%', 'important');
  const head = document.head || root;
  let viewport = document.querySelector('meta[name="viewport"]');
  if (!viewport) {
    viewport = document.createElement('meta');
    viewport.name = 'viewport';
    head.appendChild(viewport);
  }
  viewport.content = 'width=device-width, initial-scale=1';
  let style = document.getElementById('modu-popup-page-layout');
  if (!style) {
    style = document.createElement('style');
    style.id = 'modu-popup-page-layout';
    style.textContent = `
      html { overflow-x: hidden !important; overflow-y: auto !important; }
      body { width: auto !important; margin-left: 0 !important; margin-right: 0 !important;
        overflow-x: clip !important; }
      body, body :where(div, main, section, article, header, footer, nav, form,
        fieldset, figure, aside, p, ul, ol, li, table, pre, textarea, input,
        [contenteditable]) {
        min-width: 0 !important; max-width: 100% !important;
        box-sizing: border-box !important; overflow-wrap: anywhere !important;
      }
      body :where(div, main, section, article, header, footer, nav, form) {
        flex-wrap: wrap !important;
      }
      body :where(p, li, td, th) { white-space: normal !important; }
      body :where(pre, textarea, [contenteditable]) {
        white-space: pre-wrap !important; overflow-wrap: anywhere !important;
      }
      body :where(img, video, canvas, svg, iframe) { max-width: 100% !important; }
      body img { height: auto !important; }
      body table { table-layout: fixed !important; width: 100% !important; }
      [data-modu-popup-grid] { grid-template-columns: minmax(0, 1fr) !important; }
      [data-modu-popup-grid] > * { grid-column: auto !important; }
    `;
    head.appendChild(style);
  }
  // Fixed desktop grids can still overflow after their container has shrunk.
  // Stack only overflowing grids; responsive layouts keep their own columns.
  if (window.__moduPopupLayout) {
    window.__moduPopupLayout();
    return;
  }
  let queued = false;
  const schedule = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      document.querySelectorAll('[data-modu-popup-grid]')
        .forEach(el => el.removeAttribute('data-modu-popup-grid'));
      for (const el of document.querySelectorAll('div, main, section, article, form')) {
        if (getComputedStyle(el).display === 'grid' && el.clientWidth > 0
            && el.scrollWidth > el.clientWidth + 1) {
          el.setAttribute('data-modu-popup-grid', '');
        }
      }
    });
  };
  window.__moduPopupLayout = schedule;
  new MutationObserver(schedule).observe(root, {childList: true, subtree: true});
  window.addEventListener('resize', schedule);
  document.fonts?.ready.then(schedule);
  schedule();
})();
''';
}

// Request compact site layouts consistently, including desktop WebViews whose
// native content-mode option does not change the User-Agent (e.g. Windows).
const popupWebUserAgent =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
