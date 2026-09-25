// Wait for requested faces; on an actual failure use the browser's generic
// serif font only for affected text. A slow font is not a failed font.
const fallbacks = new WeakMap();
const waits = new WeakMap();

// A new user style/font choice must not be masked by a previous fallback.
export function clearReaderFontFallback(doc) {
  waits.delete(doc);
  for (const [el, original] of fallbacks.get(doc) ?? []) {
    if (original.value) el.style.setProperty('font-family', original.value, original.priority);
    else el.style.removeProperty('font-family');
  }
  fallbacks.delete(doc);
}

function useGenericFont(doc, elements) {
  if (!elements.length || elements.some(el => !el?.style?.setProperty)) return false;
  let saved = fallbacks.get(doc);
  if (!saved) { saved = new Map(); fallbacks.set(doc, saved); }
  for (const el of elements) {
    if (!saved.has(el)) saved.set(el, {
      value: el.style.getPropertyValue('font-family'),
      priority: el.style.getPropertyPriority('font-family'),
    });
    // Unquoted CSS generic family: no font file or network request required.
    // Inline !important also wins over publisher !important declarations.
    el.style.setProperty('font-family', 'serif', 'important');
  }
  doc.body?.getBoundingClientRect();
  return true;
}

export async function waitForReaderFonts(doc, signal) {
  if (signal?.aborted) return false;
  if (!doc.fonts) return true;
  const token = waits.get(doc) ?? {};
  waits.set(doc, token);
  const active = () => !signal?.aborted && waits.get(doc) === token;
  doc.body?.getBoundingClientRect();
  // A chapter using only system fonts (or already decoded faces) needs no
  // per-text-node discovery. Force layout above so requested faces are known.
  // Do not take this path with unloaded/error faces: subset fonts and the
  // failure fallback still need the actual text coverage below.
  if (doc.fonts.status === 'loaded' && doc.fonts[Symbol.iterator] &&
      [...doc.fonts].every(face => face.status === 'loaded')) return active();
  const requests = new Map();
  if (doc.createTreeWalker && doc.defaultView && doc.fonts.load && doc.body) {
    const walker = doc.createTreeWalker(doc.body, 4); // SHOW_TEXT
    const styles = new WeakMap();
    for (let node; (node = walker.nextNode());) {
      const el = node.parentElement;
      if (!el || !node.textContent.trim() || el.closest('script, style, template, [hidden]')) continue;
      let font = styles.get(el);
      if (font === undefined) {
        const style = doc.defaultView.getComputedStyle(el);
        font = style.display === 'none' || style.visibility === 'hidden' || !el.getClientRects().length
          ? null : `${style.fontStyle || 'normal'} ${style.fontWeight || '400'} ${style.fontSize || '16px'} ${style.fontFamily}`;
        styles.set(el, font);
      }
      if (!font) continue;
      if (!requests.has(font)) requests.set(font, {chars: new Set(), elements: new Set()});
      const request = requests.get(font);
      request.elements.add(el);
      for (const char of node.textContent) request.chars.add(char);
    }
  }
  let cancel;
  try {
    const ready = requests.size
      ? Promise.all([...requests].map(async ([font, {chars, elements}]) => {
        try {
          const text = [...chars].join('');
          if (!doc.fonts.check?.(font, text)) await doc.fonts.load(font, text);
          return active();
        } catch {
          return active() && useGenericFont(doc, [...elements]);
        }
      })).then(results => results.every(Boolean))
      : (doc.createTreeWalker ? Promise.resolve(true) : Promise.resolve(doc.fonts.ready)
        .then(() => true, () => active() && useGenericFont(doc,
          [doc.documentElement, doc.body, ...(doc.body?.querySelectorAll?.('*') ?? [])].filter(Boolean))));
    return await Promise.race([ready.then(result => {
      if (signal?.aborted) return false;
      // A style change during initial chapter loading invalidates the old
      // request, not the chapter. Recheck the newly selected font instead.
      if (waits.get(doc) !== token) return waitForReaderFonts(doc, signal);
      return result;
    }, () => false),
      new Promise(resolve => {
        cancel = () => resolve(false);
        signal?.addEventListener('abort', cancel, { once: true });
      })]);
  } catch {
    return false;
  } finally {
    if (cancel) signal?.removeEventListener('abort', cancel);
  }
}
