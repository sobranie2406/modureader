// Merge actual glyph bands rather than guessing a grid from the preferred font
// size: headings, paragraph margins and mixed Latin text need different spacing.
export function columnSeparators(rects, width) {
  const bands = rects.filter(r => r.right > 0 && r.left < width &&
    Number.isFinite(r.left) && Number.isFinite(r.right) && r.right > r.left)
    .map(r => ({ left: r.left, right: r.right }))
    .sort((a, b) => a.left - b.left);
  const merged = [];
  for (const band of bands) {
    const last = merged[merged.length - 1];
    if (last && band.left <= last.right + 1) last.right = Math.max(last.right, band.right);
    else merged.push(band);
  }
  return merged.slice(1).flatMap((band, index) => {
    const previous = merged[index];
    const x = (previous.right + band.left) / 2;
    return band.left - previous.right >= 2 && x > 0 && x < width ? [x] : [];
  });
}

// A noninteractive overlay outside chapter documents: no inserted book nodes,
// no CFI/selection changes and no extra line boxes affecting pagination.
export class VerticalColumnRules {
  constructor(renderer, layer, container) {
    this.renderer = renderer;
    this.layer = layer;
    this.container = container;
    this.svg = layer.ownerDocument.createElementNS('http://www.w3.org/2000/svg', 'svg');
    this.svg.setAttribute('aria-hidden', 'true');
    this.svg.setAttribute('data-vertical-column-rules', '');
    Object.assign(this.svg.style, { position: 'absolute', inset: '0', width: '100%',
      height: '100%', pointerEvents: 'none', userSelect: 'none', overflow: 'hidden', zIndex: '1' });
    layer.append(this.svg);
    this.schedule = () => {
      if (this.frame || this.destroyed) return;
      this.frame = requestAnimationFrame(() => { this.frame = null; this.draw(); });
    };
    renderer.addEventListener('relocate', this.schedule);
    renderer.addEventListener('load', this.schedule);
    container.addEventListener('scroll', this.schedule, { passive: true });
    this.resize = new ResizeObserver(this.schedule);
    this.resize.observe(layer);
    this.attributes = new MutationObserver(this.schedule);
    this.attributes.observe(renderer, { attributes: true, attributeFilter: ['vertical-column-rules'] });
  }

  draw() {
    const enabled = this.renderer.vertical && this.renderer.getAttribute('vertical-column-rules') === 'true';
    this.svg.style.display = enabled ? 'block' : 'none';
    if (!enabled) { this.svg.replaceChildren(); return; }
    const viewport = this.layer.getBoundingClientRect();
    const width = this.layer.clientWidth;
    const height = this.layer.clientHeight;
    if (viewport.width <= 0 || viewport.height <= 0 || width <= 0 || height <= 0) return;
    // DOM rectangles are screen-scaled; SVG coordinates are local CSS pixels.
    // Opening animations must not bake their temporary scale into the lines.
    const toLocalX = width / viewport.width;
    const toLocalY = height / viewport.height;
    const glyphs = [], media = [];
    for (const { doc } of this.renderer.getContents()) {
      const frame = doc.defaultView?.frameElement;
      if (!frame || !doc.body) continue;
      const origin = frame.getBoundingClientRect();
      const sx = origin.width / frame.clientWidth || 1;
      const sy = origin.height / frame.clientHeight || 1;
      const project = r => ({ left: (origin.left + r.left * sx - viewport.left) * toLocalX,
        right: (origin.left + r.right * sx - viewport.left) * toLocalX,
        top: (origin.top + r.top * sy - viewport.top) * toLocalY,
        bottom: (origin.top + r.bottom * sy - viewport.top) * toLocalY });
      const visible = r => r.right > 0 && r.left < width &&
        r.bottom > 0 && r.top < height;
      const range = doc.createRange();
      // Prune offscreen blocks before measuring their text. Work is restricted
      // to the visible page, not all paragraphs of a long chapter.
      const walker = doc.createTreeWalker(doc.body, 5, {
        acceptNode: node => {
          if (node.nodeType === 1) {
            if (/^(SCRIPT|STYLE|SVG|IMG|VIDEO|CANVAS|RT|RP)$/.test(node.tagName)) return 2;
            const rect = node.getBoundingClientRect();
            return rect.width && rect.height && !visible(project(rect)) ? 2 : 3;
          }
          return node.textContent.trim() ? 1 : 2;
        },
      });
      for (let node; (node = walker.nextNode());) {
        range.selectNodeContents(node);
        for (const rect of range.getClientRects()) {
          const r = project(rect);
          if (rect.width > 0 && rect.height > 0 && visible(r)) glyphs.push(r);
        }
      }
      for (const image of doc.querySelectorAll('img,svg,video,canvas')) {
        const rect = project(image.getBoundingClientRect());
        if (visible(rect)) media.push(rect);
      }
    }
    const lines = columnSeparators(glyphs, width)
      .filter(x => !media.some(r => x >= r.left && x <= r.right))
      .map(x => {
        const line = this.svg.ownerDocument.createElementNS(this.svg.namespaceURI, 'line');
        for (const [key, value] of Object.entries({ x1: x, x2: x, y1: 0,
          // Follow the live SVG viewport even before a resize redraw runs.
          y2: '100%', stroke: '#c91c24', 'stroke-width': 0.7, 'stroke-opacity': 0.65 }))
          line.setAttribute(key, String(value));
        return line;
      });
    this.svg.replaceChildren(...lines);
  }

  destroy() {
    this.destroyed = true;
    if (this.frame) cancelAnimationFrame(this.frame);
    this.renderer.removeEventListener('relocate', this.schedule);
    this.renderer.removeEventListener('load', this.schedule);
    this.container.removeEventListener('scroll', this.schedule);
    this.resize.disconnect();
    this.attributes.disconnect();
    this.svg.remove();
  }
}
