// Only the mobile Flutter host enables this reflowable-book adaptation.
const originals = new WeakMap();
const properties = ['width', 'height', 'min-width', 'min-height', 'max-width',
  'max-height', 'object-fit', 'box-sizing', 'break-inside', 'page-break-inside', 'overflow'];
const remember = el => {
  if (!originals.has(el)) originals.set(el, properties.map(name =>
    [name, el.style.getPropertyValue(name), el.style.getPropertyPriority(name)]));
};
const restore = el => {
  for (const [name, value, priority] of originals.get(el) ?? [])
    value ? el.style.setProperty(name, value, priority) : el.style.removeProperty(name);
};
const set = (el, values) => {
  for (const [name, value] of Object.entries(values)) el.style.setProperty(name, value, 'important');
};
const positive = (n, fallback) => Number.isFinite(n) && n > 0 ? n : fallback;

export function mobileImageBounds(layout, vertical = false) {
  const width = positive(layout.width, 1), height = positive(layout.height, 1);
  const inset = Math.max(0, Number(layout.topMargin) || 0) + Math.max(0, Number(layout.bottomMargin) || 0);
  const gap = Math.max(0, Number(layout.gap) || 0);
  const scrolled = layout.flow === 'scrolled';
  return {
    width: Math.max(1, vertical ? width - (scrolled ? 0 : inset)
      : Math.min(positive(layout.columnWidth, width), width - (scrolled ? gap * 2 : gap))),
    height: Math.max(1, vertical
      ? Math.min(positive(layout.columnWidth, height), height - (scrolled ? gap * 2 : gap))
      : height - (scrolled ? 0 : inset)),
  };
}

export function fitMobileImages(doc, layout, vertical = false) {
  if (layout.mobileImageFit !== true || !doc?.body) return;
  const bounds = mobileImageBounds(layout, vertical);
  // Nested SVG shapes must keep their own viewBox geometry.
  const media = [...doc.body.querySelectorAll('img, svg, video')]
    .filter(el => !el.parentElement?.closest('svg'));
  const wrappers = new Set();
  for (const el of media) {
    for (let parent = el.parentElement; parent && parent !== doc.body; parent = parent.parentElement) {
      // Do not resize general text containers or tables. Figure captions are
      // allowed; fixed figure boxes otherwise crop the image even after fitting.
      if (!['DIV', 'P', 'SPAN', 'A', 'FIGURE', 'PICTURE'].includes(parent.tagName)) break;
      const walker = doc.createTreeWalker(parent, doc.defaultView.NodeFilter.SHOW_TEXT);
      let hasText = false;
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (node.textContent.trim() && !node.parentElement?.closest('svg,video,figcaption')) {
          hasText = true; break;
        }
      }
      if (hasText) break;
      wrappers.add(parent);
    }
  }
  for (const el of [...wrappers, ...media]) { remember(el); restore(el); }
  for (const el of wrappers) set(el, {
    'width': 'auto', 'height': 'auto', 'min-width': '0', 'min-height': '0',
    'max-width': `min(100%, ${bounds.width}px)`, 'max-height': 'none',
    'overflow': 'visible', 'box-sizing': 'border-box',
  });
  for (const el of media) {
    const css = doc.defaultView.getComputedStyle(el);
    const naturalWidth = el.naturalWidth || el.videoWidth || el.viewBox?.baseVal?.width;
    const naturalHeight = el.naturalHeight || el.videoHeight || el.viewBox?.baseVal?.height;
    const width = positive(parseFloat(css.width), positive(naturalWidth, bounds.width));
    const height = positive(parseFloat(css.height), positive(naturalHeight, bounds.height));
    const ratio = naturalWidth > 0 && naturalHeight > 0 ? naturalWidth / naturalHeight : width / height;
    const preferredWidth = Math.min(width, height * ratio);
    const marginX = Math.max(0, parseFloat(css.marginLeft) || 0) + Math.max(0, parseFloat(css.marginRight) || 0);
    const marginY = Math.max(0, parseFloat(css.marginTop) || 0) + Math.max(0, parseFloat(css.marginBottom) || 0);
    const parentWidth = positive(el.parentElement?.clientWidth, bounds.width);
    const maxWidth = Math.max(1, Math.min(bounds.width, parentWidth) - marginX);
    const maxHeight = Math.max(1, bounds.height - marginY);
    const fittedWidth = Math.min(preferredWidth, maxWidth, maxHeight * ratio);
    set(el, {
      'width': `${fittedWidth}px`, 'height': `${fittedWidth / ratio}px`,
      'min-width': '0', 'min-height': '0', 'max-width': `min(100%, ${maxWidth}px)`,
      'max-height': `${maxHeight}px`, 'object-fit': 'contain', 'box-sizing': 'border-box',
      'break-inside': 'avoid', 'page-break-inside': 'avoid',
    });
  }
}
