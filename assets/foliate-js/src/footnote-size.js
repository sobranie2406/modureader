// All sizes are outer border-box CSS pixels. The cap is AREA, not 25% of
// both dimensions (which would leave only 6.25% of the screen).
export function footnoteBoxSize({ width, height, textLength = 0, fontSize = 16,
  contentHeight = Infinity, chromeHeight = 18 }) {
  const w = Math.max(1, Number(width) || 1), h = Math.max(1, Number(height) || 1);
  const inset = Math.min(12, w / 10, h / 10);
  const area = w * h * 0.25;
  const maxWidth = Math.min(w - inset * 2, Math.sqrt(area * 2));
  const preferred = Math.sqrt(Math.max(1, textLength) * fontSize ** 2 * 2.1) + 24;
  const boxWidth = Math.max(1, Math.floor(Math.min(maxWidth, Math.max(Math.min(200, maxWidth), preferred))));
  const maxHeight = Math.max(1, Math.floor(Math.min(h - inset * 2, area / boxWidth)));
  const boxHeight = Math.max(1, Math.floor(Math.min(maxHeight,
    Math.max(fontSize * 1.4 + chromeHeight, contentHeight + chromeHeight))));
  return { width: boxWidth, height: boxHeight, maxHeight };
}

export function attachFootnoteSizing(dialog, doc) {
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
    const size = footnoteBoxSize({ width, height,
      textLength: doc.body.textContent.length,
      fontSize: px(bodyStyle.fontSize) || 16,
      chromeHeight: px(boxStyle.paddingTop) + px(boxStyle.paddingBottom)
        + px(boxStyle.borderTopWidth) + px(boxStyle.borderBottomWidth),
      contentHeight,
    });
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
