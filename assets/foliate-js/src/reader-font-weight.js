const marker = '/* modu-reader-font-weight */';
const preserved = 'h1, h2, h3, h4, h5, h6, [role="heading"], b, strong, svg, math, script, style';
const savedWeights = new WeakMap();

// Change ordinary text through inheritance, not a blanket numeric override:
// spans inside headings/emphasis and later user CSS keep their own weight.
export function readerFontWeightCSS({ fontWeight = 400, simulateBold = false, useBookStyles, pdf } = {}) {
  if (useBookStyles || pdf) return '';
  const value = Number(fontWeight);
  const weight = Number.isFinite(value) ? Math.min(900, Math.max(100, value)) : 400;
  // A fixed bold file may ignore every requested CSS weight. Add a real text
  // stroke instead of asking the browser to synthesize another bold face.
  // Keep ordinary weight at 400 in this mode to avoid double-bold jumps in
  // system/variable fonts. A stroke cannot thin a fixed outline below 1.0.
  const simulated = simulateBold === true;
  const stroke = (Math.max(0, Math.min(1, weight / 400 - 1)) * 0.035).toFixed(4);
  const strokeCSS = simulated && Number(stroke) > 0 ? `
    body {
      -webkit-text-stroke-width: ${stroke}em !important;
      -webkit-text-stroke-color: currentColor !important;
    }
    body :where(:not(${preserved})) {
      -webkit-text-stroke-width: inherit !important;
      -webkit-text-stroke-color: currentColor !important;
    }
    body :where(${preserved}) {
      -webkit-text-stroke-width: 0 !important;
    }` : '';
  return `${marker}
    body {
      font-weight: ${simulated ? 400 : weight} !important;
      font-synthesis: weight style !important;
    }
    body :where(:not(h1, h2, h3, h4, h5, h6, [role="heading"], b, strong,
        svg, svg *, math, math *, script, style)) {
      font-weight: inherit !important;
      font-synthesis: inherit !important;
    }
    ${strokeCSS}`;
}

// Publisher inline !important beats any stylesheet. Temporarily remove only
// the ordinary text's weight (including the weight component of a font
// shorthand), leaving its size/family/italics and all text nodes untouched.
// Restore it when following book styles again. Never modify the source file.
export function prepareReaderFontWeight(doc, styles) {
  if (!doc?.body) return;
  if (!String(styles).includes(marker)) {
    for (const [el, { value, priority }] of savedWeights.get(doc) ?? []) {
      el.style.setProperty('font-weight', value, priority);
    }
    savedWeights.delete(doc);
    return;
  }
  let saved = savedWeights.get(doc);
  if (!saved) { saved = new Map(); savedWeights.set(doc, saved); }
  for (const el of [doc.body, ...doc.body.querySelectorAll('[style]')]) {
    if (!el.style || el.closest(preserved)) continue;
    const value = el.style.getPropertyValue('font-weight');
    if (!value) continue;
    if (!saved.has(el)) saved.set(el, {
      value, priority: el.style.getPropertyPriority('font-weight'),
    });
    el.style.removeProperty('font-weight');
  }
}
