// Mobile WebViews may send selectionchange without pointercancel/pointerup when the
// native long-press handles take ownership. Observe the selection itself.
export function installSettledSelection(doc, { getRange, onSelection, beforeSelection, delay = 200 }) {
  let timer, generation = 0, disposed = false;
  let previous;
  const same = (a, b) => a && b && a.startContainer === b.startContainer &&
    a.startOffset === b.startOffset && a.endContainer === b.endContainer &&
    a.endOffset === b.endOffset;
  const cancel = () => { generation++; clearTimeout(timer); timer = undefined; };
  const schedule = () => {
    cancel();
    if (!getRange()) { previous = undefined; return; }
    const scheduled = generation;
    timer = setTimeout(async () => {
      let range = getRange();
      if (!range || doc.__moduQuickMarkEnabled) return;
      try { await beforeSelection?.(); } catch { /* Keep the native range on failure. */ }
      if (disposed || generation !== scheduled) return;
      range = getRange();
      if (!range || doc.__moduQuickMarkEnabled || same(previous, range)) return;
      previous = range.cloneRange();
      onSelection();
    }, delay);
  };
  const start = () => { cancel(); previous = undefined; };
  const menu = e => { e.preventDefault(); schedule(); };
  const listeners = [
    ['pointerdown', start], ['touchstart', start], ['selectionchange', schedule],
    ['pointerup', schedule], ['touchend', schedule], ['contextmenu', menu],
  ];
  for (const [name, handler] of listeners) doc.addEventListener(name, handler);
  return () => {
    disposed = true;
    cancel();
    for (const [name, handler] of listeners) doc.removeEventListener(name, handler);
  };
}
