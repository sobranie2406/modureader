// Keep the final line (including custom-font descenders) inside the iframe's
// measured flow, with scrollable end space rather than clipped overflow.
export const footnoteLayoutCSS = `
html, body { min-height: 0 !important; height: auto !important; }
body { display: flow-root !important; padding-block-end: 1em !important; }
`;

// All sizes are outer border-box CSS pixels. The cap is AREA, not 25% of
// both dimensions (which would leave only 6.25% of the screen).
export function footnoteBoxSize({ width, height, textLength = 0, fontSize = 16,
  contentHeight = Infinity, chromeHeight = 18, desktop = false, measureHeight }) {
  const w = Math.max(1, Number(width) || 1), h = Math.max(1, Number(height) || 1);
  const inset = Math.min(12, w / 10, h / 10);
  const area = w * h * 0.25;
  // Desktop notes need more visible lines, not an increasingly wide strip.
  // Keep mobile geometry unchanged and fit small desktop windows as well.
  const maxWidth = Math.min(w - inset * 2, Math.sqrt(area * (desktop ? 1.15 : 2)));
  const preferred = Math.sqrt(Math.max(1, textLength) * fontSize ** 2 * 2.1) + 24;
  const minWidth = desktop && textLength >= 80 ? 360 : 200;
  const boxWidth = Math.max(1, Math.floor(Math.min(maxWidth, Math.max(Math.min(minWidth, maxWidth), preferred))));
  const maxHeight = Math.max(1, Math.floor(Math.min(h - inset * 2,
    desktop ? h * 0.6 : Infinity, area / boxWidth)));
  // Medium/long desktop notes get comfortable reading space; one-line notes
  // still shrink to their contents. The area cap always takes precedence.
  const minHeight = desktop && textLength >= 80
    ? Math.max(240, fontSize * 1.5 * 6 + chromeHeight) : 0;
  const boxHeight = Math.max(1, Math.floor(Math.min(maxHeight,
    Math.max(minHeight, fontSize * 1.4 + chromeHeight, contentHeight + chromeHeight))));
  if (desktop && measureHeight) {
    // Try actual wrapped text at several widths. Prefer a fully visible note
    // over a fixed aspect ratio; only overflow if no candidate fits the cap.
    const widths = [...new Set([boxWidth, ...[1, 1.4, 2, 2.8, 4].map(ratio =>
      Math.max(1, Math.floor(Math.min(w - inset * 2, Math.sqrt(area * ratio)))) )])];
    const candidates = widths.map(candidate => {
      const limit = Math.max(1, Math.floor(Math.min(h - inset * 2, h * .75, area / candidate)));
      const needed = Math.ceil(measureHeight(candidate) + chromeHeight + 2);
      return {width:candidate, height:Math.min(limit, Math.max(1, needed)),
        maxHeight:limit, needed};
    }).filter(candidate => Number.isFinite(candidate.needed));
    const fits = candidates.filter(candidate => candidate.needed <= candidate.maxHeight);
    // Smallest fitting area avoids a huge empty popup for a short annotation.
    const ranked = fits.length ? fits.sort((a,b) => a.width*a.height-b.width*b.height)
      : candidates.sort((a,b) => b.height/b.needed-a.height/a.needed);
    if (ranked.length) {
      const {needed, ...best} = ranked[0];
      return best;
    }
  }
  return { width: boxWidth, height: boxHeight, maxHeight };
}

export function attachFootnoteSizing(dialog, doc, { desktop = false } = {}) {
  const win = dialog.ownerDocument.defaultView;
  const viewport = win.visualViewport;
  let frame = 0, disposed = false;
  const px = value => Math.max(0, parseFloat(value) || 0);
  const set = (name, value) => {
    const next = `${value}px`;
    if (dialog.style[name] !== next) dialog.style[name] = next;
  };
  const update = () => {
    frame = 0;
    if (disposed || !doc.body) return;
    const bodyStyle = doc.defaultView.getComputedStyle(doc.body);
    const rootStyle = doc.defaultView.getComputedStyle(doc.documentElement);
    const boxStyle = win.getComputedStyle(dialog);
    const range = doc.createRange();
    range.selectNodeContents(doc.body);
    // The iframe/body may retain the previous long note's expanded viewport
    // height. Measure the content range, not scrollHeight, so short notes shrink.
    const contentHeight = range.getBoundingClientRect().height
      + px(bodyStyle.marginTop) + px(bodyStyle.marginBottom)
      + px(bodyStyle.paddingTop) + px(bodyStyle.paddingBottom)
      + px(rootStyle.paddingTop) + px(rootStyle.paddingBottom);
    const width = viewport?.width || win.innerWidth;
    const height = viewport?.height || win.innerHeight;
    let measureHeight;
    if (desktop) {
      // Measure in the same document to retain the book's font and paragraph
      // styles, without resizing the visible note through multiple candidates.
      const clone = doc.body.cloneNode(true);
      clone.setAttribute('aria-hidden', 'true');
      const paddingRatio = (px(rootStyle.paddingLeft) + px(rootStyle.paddingRight))
        / Math.max(1, doc.defaultView.innerWidth);
      const chromeWidth = px(boxStyle.paddingLeft) + px(boxStyle.paddingRight)
        + px(boxStyle.borderLeftWidth) + px(boxStyle.borderRightWidth);
      for (const [name,value] of Object.entries({position:'absolute',visibility:'hidden',
        'pointer-events':'none',left:'0',top:'0',height:'auto','min-height':'0',
        'max-height':'none','max-width':'none',margin:'0','box-sizing':'border-box'}))
        clone.style.setProperty(name,value,'important');
      doc.documentElement.append(clone);
      measureHeight = candidate => {
        clone.style.setProperty('width', `${Math.max(1,(candidate-chromeWidth)*(1-Math.min(.8,paddingRatio)))}px`, 'important');
        return clone.getBoundingClientRect().height
          + px(rootStyle.paddingTop) + px(rootStyle.paddingBottom);
      };
      measureHeight.dispose = () => clone.remove();
    }
    const size = footnoteBoxSize({ width, height,
      textLength: doc.body.textContent.length,
      fontSize: px(bodyStyle.fontSize) || 16,
      desktop,
      measureHeight,
      chromeHeight: px(boxStyle.paddingTop) + px(boxStyle.paddingBottom)
        + px(boxStyle.borderTopWidth) + px(boxStyle.borderBottomWidth),
      contentHeight,
    });
    measureHeight?.dispose();
    set('width', size.width);
    set('height', size.height);
    set('left', (viewport?.offsetLeft || 0) + width / 2);
    set('top', (viewport?.offsetTop || 0) + height / 2);
  };
  const schedule = () => { if (!disposed && !frame) frame = win.requestAnimationFrame(update); };
  const observer = new win.ResizeObserver(schedule);
  observer.observe(doc.body);
  const mutations = new win.MutationObserver(schedule);
  mutations.observe(doc.body, { childList: true, subtree: true, characterData: true });
  win.addEventListener('resize', schedule);
  viewport?.addEventListener('resize', schedule);
  viewport?.addEventListener('scroll', schedule);
  doc.addEventListener('load', schedule, true);
  doc.fonts?.ready.then(schedule);
  dialog.style.display = 'block';
  update();
  schedule(); // The renderer will have laid out the new width on the next frame.
  return { destroy() {
    disposed = true;
    win.cancelAnimationFrame(frame);
    observer.disconnect(); mutations.disconnect();
    win.removeEventListener('resize', schedule);
    viewport?.removeEventListener('resize', schedule);
    viewport?.removeEventListener('scroll', schedule);
    doc.removeEventListener('load', schedule, true);
  } };
}
