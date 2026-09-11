// Android may send selectionchange without pointercancel/pointerup when the
// native long-press handles take ownership. Observe the selection itself.
export function installSettledSelection(doc, { getRange, onSelection, delay = 200 }) {
  let timer;
  let previous;
  const same = (a, b) => a && b && a.startContainer === b.startContainer &&
    a.startOffset === b.startOffset && a.endContainer === b.endContainer &&
    a.endOffset === b.endOffset;
  const cancel = () => { clearTimeout(timer); timer = undefined; };
  const schedule = () => {
    cancel();
    if (!getRange()) { previous = undefined; return; }
    timer = setTimeout(() => {
      const range = getRange();
      if (!range || doc.__moduQuickMarkEnabled || same(previous, range)) return;
      previous = range.cloneRange();
      onSelection();
    }, delay);
  };
  const start = () => { cancel(); previous = undefined; };
  const menu = e => { e.preventDefault(); schedule(); };
  const listeners = [
    ['pointerdown', start], ['selectionchange', schedule],
    ['pointerup', schedule], ['touchend', schedule], ['contextmenu', menu],
  ];
  for (const [name, handler] of listeners) doc.addEventListener(name, handler);
  return () => {
    cancel();
    for (const [name, handler] of listeners) doc.removeEventListener(name, handler);
  };
}
