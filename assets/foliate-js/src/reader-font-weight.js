const marker = '/* modu-reader-font-weight */';
const preserved = 'h1, h2, h3, h4, h5, h6, [role="heading"], b, strong, svg, math, script, style';
const savedWeights = new WeakMap();
const imageWrappers = new Set(['img', 'span', 'a', 'b', 'strong', 'i', 'em', 'u',
  's', 'small', 'sup', 'sub', 'br', 'wbr', 'picture', 'source', 'modu-page-run']);

function prepareReaderImages(doc) {
  for (const el of doc.body.querySelectorAll('[data-modu-image-paragraph], [data-modu-inline-image]')) {
    el.removeAttribute('data-modu-image-paragraph');
    el.removeAttribute('data-modu-inline-image');
  }
  const textBlocks = new Map();
  const hidden = el => {
    for (let parent = el; parent; parent = parent.parentElement) {
      if (parent.matches('script,style,template,[hidden]') || parent.style?.display === 'none') return true;
    }
    return false;
  };
  const hasText = block => {
    if (textBlocks.has(block)) return textBlocks.get(block);
    const walker = doc.createTreeWalker(block, 4);
    let text = false;
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (/[^\s\u200b-\u200d\u2060\ufeff]/u.test(node.data) &&
          !node.parentElement?.closest('svg,math') && !hidden(node.parentElement)) {
        text = true;
        break;
      }
    }
    textBlocks.set(block, text);
    return text;
  };
  for (const img of doc.body.querySelectorAll('img')) {
    if (img.closest('svg,math')) continue;
    const block = img.closest('p,div') ?? doc.body;
    img.toggleAttribute('data-modu-inline-image', hasText(block));
  }
  for (const [block, text] of textBlocks) {
    // Text nodes count too; :only-child ignores prose around an embedded glyph.
    // Structural containers keep their publisher dimensions, even without text.
    if (block !== doc.body && !text &&
        [...block.querySelectorAll('*')].every(el => imageWrappers.has(el.localName) || hidden(el))) {
      block.setAttribute('data-modu-image-paragraph', '');
    }
  }
}

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
  const css = `${marker}
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
  if ((globalThis.CSS?.supports?.('selector(:where(*))') ?? true)) return css;
  return css.replace(/body :where\(:not\([\s\S]*?\)\)/g, 'body [data-modu-reader-weight]')
    .replace(/body :where\([^)]*\)/g, 'body [data-modu-preserved-weight]');
}

// Publisher inline !important beats any stylesheet. Temporarily remove only
// the ordinary text's weight (including the weight component of a font
// shorthand), leaving its size/family/italics and all text nodes untouched.
// Restore it when following book styles again. Never modify the source file.
export function prepareReaderFontWeight(doc, styles) {
  if (!doc?.body) return;
  prepareReaderImages(doc);
  // Old WebViews discard an entire selector list containing :has/:where.
  // Attribute markers keep the same matching rules without changing text/CFIs.
  if (!doc.defaultView?.CSS?.supports?.('selector(:has(*))')) {
    for (const el of doc.body.querySelectorAll('div,p')) {
      el.toggleAttribute('data-modu-paragraph', el.localName === 'div' &&
        !el.querySelector(':not(b):not(a):not(em):not(i):not(strong):not(u):not(span):not(modu-page-run)'));
    }
  }
  if (!doc.defaultView?.CSS?.supports?.('selector(:where(*))')) {
    for (const el of doc.body.querySelectorAll('*')) {
      el.toggleAttribute('data-modu-reader-weight', !el.matches(preserved) && !el.closest('svg,math'));
      el.toggleAttribute('data-modu-preserved-weight', el.matches(preserved));
      el.toggleAttribute('data-modu-reader-color', el.matches('h1,h2,h3,h4,h5,h6,span,b,strong,em,i,u,small,cite,q,sup,sub') && !el.closest('a,svg,pre,code'));
      el.toggleAttribute('data-modu-eink-color', !el.closest('svg,img,canvas,video'));
      el.toggleAttribute('data-modu-reader-line-height',
        el.matches('span,b,strong,em,i,u,small,cite,q,font') &&
        !el.closest('table,pre,code,ruby,math,svg,sup,sub'));
    }
  }
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
