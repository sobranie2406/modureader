// Direct-touch marking is enabled explicitly by the mobile Flutter host.
// No native Selection is created: this avoids Android/iOS selection handles,
// selectionchange auto-page timers and the ordinary selection action menu.
const blocked = 'a,button,input,textarea,select,[contenteditable="true"],rt,[data-modu-quick-mark="preview"]';

export const rangeBetween = (doc, a, b) => {
  const first = doc.createRange();
  first.setStart(a.node, a.offset);
  first.collapse(true);
  const last = doc.createRange();
  last.setStart(b.node, b.offset);
  last.collapse(true);
  const backwards = first.compareBoundaryPoints(0, last) > 0;
  const range = doc.createRange();
  const start = backwards ? b : a, end = backwards ? a : b;
  range.setStart(start.node, start.offset);
  range.setEnd(end.node, end.offset);
  return range;
};

export const caretAt = (doc, x, y, requireTextHit = false) => {
  const caret = doc.caretPositionFromPoint?.(x, y);
  const fallback = caret ? null : doc.caretRangeFromPoint?.(x, y);
  const node = caret?.offsetNode ?? fallback?.startContainer;
  const offset = caret?.offset ?? fallback?.startOffset;
  if (node?.nodeType !== 3 || !node.isConnected ||
      !doc.body.contains(node) || node.parentElement?.closest(blocked) ||
      !node.textContent.trim()) return null;
  if (requireTextHit) {
    const probe = doc.createRange();
    probe.selectNodeContents(node);
    // Caret APIs can snap a touch in a page margin to nearby text. Leave
    // margin taps/swipes to the normal reader, rather than marking by mistake.
    if (![...probe.getClientRects()].some(r =>
      x >= r.left - 3 && x <= r.right + 3 && y >= r.top - 3 && y <= r.bottom + 3)) return null;
  }
  return { node, offset };
};

export function installQuickMark(doc, { onCommit, onTap, onError = () => {} }) {
  let enabled = false, color = '#ffd54f', gesture = null, busy = false;
  let swallowClickUntil = 0;
  const layer = doc.createElement('div');
  layer.dataset.moduQuickMark = 'preview';
  layer.setAttribute('aria-hidden', 'true');
  layer.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:2147483646;';
  const sheet = doc.createElement('style');
  sheet.textContent = 'html[data-modu-quick-mark="on"]{touch-action:none!important} html[data-modu-quick-mark="on"] body{-webkit-touch-callout:none!important}';
  const stop = e => { if (e.cancelable) e.preventDefault(); e.stopImmediatePropagation(); };
  const clear = () => { gesture = null; layer.replaceChildren(); layer.remove(); };
  const paint = range => {
    layer.replaceChildren();
    for (const rect of [...range.getClientRects()].slice(0, 1000)) {
      const mark = doc.createElement('div');
      Object.assign(mark.style, { position: 'absolute', left: `${rect.left}px`,
        top: `${rect.top}px`, width: `${rect.width}px`, height: `${rect.height}px`,
        backgroundColor: color, opacity: '0.4', pointerEvents: 'none' });
      layer.append(mark);
    }
    if (!layer.isConnected) doc.body.append(layer);
  };
  const start = e => {
    if (!enabled) return;
    if (busy) { stop(e); return; }
    if (e.touches.length !== 1) {
      if (gesture) { stop(e); clear(); }
      return;
    }
    const touch = e.touches[0];
    const anchor = caretAt(doc, touch.clientX, touch.clientY, true);
    if (!anchor) return;
    stop(e);
    doc.getSelection()?.removeAllRanges();
    gesture = { id: touch.identifier, anchor, x: touch.clientX, y: touch.clientY,
      range: null, moved: false };
  };
  const move = e => {
    if (!gesture) return;
    stop(e);
    if (!gesture.anchor.node.isConnected) { clear(); return; }
    if (e.touches.length !== 1) { clear(); return; }
    const touch = [...e.touches].find(t => t.identifier === gesture.id);
    if (!touch) { clear(); return; }
    gesture.moved ||= Math.hypot(touch.clientX - gesture.x, touch.clientY - gesture.y) >= 6;
    const end = caretAt(doc, touch.clientX, touch.clientY);
    if (!end) return;
    const range = rangeBetween(doc, gesture.anchor, end);
    if (range.toString().length > 100000) { clear(); return; }
    gesture.range = range;
    if (gesture.moved) paint(range);
  };
  const finish = async e => {
    if (!gesture) return;
    stop(e);
    const active = gesture;
    // A second finger or an interrupted OS gesture must never save a note.
    if (e.touches.length || ![...e.changedTouches].some(t => t.identifier === active.id)) {
      clear(); return;
    }
    gesture = null;
    swallowClickUntil = Date.now() + 600;
    const range = active.range;
    if (range && (!range.startContainer.isConnected || !range.endContainer.isConnected)) {
      clear(); return;
    }
    if (!active.moved || !range || range.collapsed || !range.toString().trim()) {
      clear();
      if (!active.moved) onTap?.();
      return;
    }
    busy = true;
    try { await onCommit(range.cloneRange()); }
    catch { onError(); }
    finally { busy = false; clear(); }
  };
  const cancel = e => { if (gesture) { stop(e); clear(); } };
  const blockNative = e => {
    if (enabled && (gesture || busy || e.type === 'contextmenu' || e.type === 'selectstart')) stop(e);
  };
  const click = e => { if (Date.now() < swallowClickUntil) stop(e); };
  const reset = () => clear();
  const listeners = { touchstart: start, touchmove: move, touchend: finish,
    touchcancel: cancel, pointerup: blockNative, contextmenu: blockNative,
    selectstart: blockNative, click };
  for (const [name, listener] of Object.entries(listeners))
    doc.addEventListener(name, listener, { capture: true, passive: false });
  doc.addEventListener('visibilitychange', reset);
  doc.defaultView?.addEventListener('pagehide', reset);
  return {
    setEnabled(value, nextColor = color) {
      enabled = value === true;
      color = /^#[0-9a-f]{6,8}$/i.test(nextColor) ? nextColor : '#ffd54f';
      clear();
      doc.__moduQuickMarkEnabled = enabled;
      if (enabled) {
        doc.documentElement.dataset.moduQuickMark = 'on';
        (doc.head ?? doc.documentElement).append(sheet);
        doc.getSelection()?.removeAllRanges();
      } else {
        delete doc.documentElement.dataset.moduQuickMark;
        sheet.remove();
      }
    },
    cancel: reset,
    destroy() {
      this.setEnabled(false);
      for (const [name, listener] of Object.entries(listeners))
        doc.removeEventListener(name, listener, true);
      doc.removeEventListener('visibilitychange', reset);
      doc.defaultView?.removeEventListener('pagehide', reset);
    },
  };
}
