const positive = value => Number.isFinite(value) && value > 0;
const excluded = 'a, sup, sub, rt, rp, script, style, nav, aside, h1, h2, h3, h4, h5, h6, [role="doc-footnote"], [hidden]';

// Measure ordinary text in the source paragraph, not the clicked noteref or
// the reader preference (EPUB paragraphs/spans may override the root size).
export function sourceBodyFontSize(reference) {
  const doc = reference?.ownerDocument;
  const win = doc?.defaultView;
  if (!win) return null;
  // Nested footnotes keep the original reading-context baseline: no 80%^n.
  if (positive(doc.__footnoteSourceFontSize)) return doc.__footnoteSourceFontSize;
  const styles = new Map();
  const computed = element => {
    if (!styles.has(element)) styles.set(element, win.getComputedStyle(element));
    return styles.get(element);
  };
  const ordinary = element => {
    for (let node = element; node && node !== doc.documentElement; node = node.parentElement) {
      if (node.matches(excluded) || node === reference) return false;
      const css = computed(node);
      if (css.display === 'none' || css.visibility === 'hidden' || css.visibility === 'collapse') return false;
      if (['super', 'sub'].includes(css.verticalAlign) ||
          (Number.isFinite(parseFloat(css.verticalAlign)) && parseFloat(css.verticalAlign) !== 0)) return false;
    }
    return true;
  };
  for (let block = reference.parentElement; block; block = block.parentElement) {
    const display = computed(block).display;
    if (!block.matches('p, li, dd, dt, td, blockquote, body') &&
        !['block', 'list-item', 'table-cell', 'flex', 'grid'].includes(display)) continue;
    const weights = new Map();
    const walker = doc.createTreeWalker(block, 4 /* SHOW_TEXT */);
    let node, visited = 0;
    while ((node = walker.nextNode()) && ++visited <= 2048) {
      const length = node.textContent.replace(/\s/g, '').length;
      if (!length || !ordinary(node.parentElement)) continue;
      const size = parseFloat(computed(node.parentElement).fontSize);
      if (positive(size)) weights.set(size, (weights.get(size) || 0) + length);
    }
    if (weights.size) return [...weights].sort((a, b) => b[1] - a[1])[0][0];
    if (block === doc.body) break;
  }
  // No ordinary text (e.g. an image-only page): use the document baseline,
  // never the superscript/sequence number's computed font.
  for (const root of [doc.body, doc.documentElement]) {
    if (!root) continue;
    const size = parseFloat(computed(root).fontSize);
    if (positive(size)) return size;
  }
  return null;
}

export function applyFootnoteTypography(doc, sourceFontSize) {
  if (!doc?.body || !positive(sourceFontSize)) return;
  doc.__footnoteSourceFontSize = sourceFontSize;
  const size = sourceFontSize * .8;
  // Inline !important also beats author inline !important sizes. Normalize
  // each text container, so nested .8em / small / px rules cannot shrink again.
  // Only font size changes: italics, bold, font family and links are preserved.
  for (const node of [doc.documentElement, doc.body, ...doc.body.querySelectorAll('*')]) {
    if (node.closest('svg, math, img, canvas, video, script, style')) continue;
    const relative = node.closest('rt, rp') ? .6 : node.closest('sup, sub') ? .75 : 1;
    node.style.setProperty('font-size', `${size * relative}px`, 'important');
  }
}
