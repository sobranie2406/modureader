// Native WebViews can keep DOM focus after a Flutter AI panel opens. Handle
// reader input at its source instead of depending only on Flutter's Focus node.
const interactive = event => (event.composedPath?.() ?? [event.target]).some(
  node => node?.isContentEditable || node?.matches?.(
    'input, textarea, select, button, a[href], [role="textbox"], [role="slider"], [role="button"]'));

export function desktopPageKey(event) {
  if (event.defaultPrevented || event.isComposing || event.altKey ||
      event.ctrlKey || event.metaKey || event.shiftKey || interactive(event)) return 0;
  if (['ArrowRight', 'ArrowDown', 'PageDown', ' '].includes(event.key)) return 1;
  if (['ArrowLeft', 'ArrowUp', 'PageUp'].includes(event.key)) return -1;
  return 0;
}

export function desktopDragDirection(dx, dy) {
  if (![dx, dy].every(Number.isFinite)) return 0;
  const distance = Math.max(Math.abs(dx), Math.abs(dy));
  if (distance < 48 || Math.abs(Math.abs(dx) - Math.abs(dy)) < distance * .2) return 0;
  return (Math.abs(dx) > Math.abs(dy) ? dx : dy) < 0 ? 1 : -1;
}

export function installDesktopPageInput(doc, { enabled, turnPage, hasSelection,
  dragEnabled = enabled, focusOnPointerDown = () => false }) {
  let pointer = null;
  let turning = false;
  let suppressClickUntil = 0;
  const listeners = [];
  const selected = () => hasSelection?.() || !!doc.getSelection()?.toString();
  const on = (target, type, listener) => {
    if (!target) return;
    const options = { capture: true };
    target.addEventListener(type, listener, options);
    listeners.push(() => target.removeEventListener(type, listener, options));
  };
  const consume = e => { e.preventDefault(); e.stopImmediatePropagation(); };
  const cancel = () => { pointer = null; };
  const turn = direction => {
    if (turning) return;
    turning = true;
    cancel();
    Promise.resolve().then(() => turnPage(direction))
      .catch(() => console.warn('Reader page navigation failed'))
      .finally(() => { turning = false; });
  };
  on(doc, 'keydown', e => {
    if (!enabled() || selected()) return;
    const direction = desktopPageKey(e);
    if (!direction) return;
    consume(e); // Suppress native scrolling even during an in-flight page turn.
    turn(direction);
  });
  on(doc, 'pointerdown', e => {
    cancel();
    // Restore the chapter frame's focus before WebKit starts its native
    // selection. Never clear/re-add ranges or cancel the default mouse action.
    // Only a reader mouse gesture may take focus from an AI/editor overlay.
    if (enabled() && focusOnPointerDown() && e.pointerType === 'mouse' &&
        e.button === 0 && !interactive(e) && !doc.hasFocus?.())
      doc.defaultView?.focus();
    if (!dragEnabled() || e.pointerType !== 'mouse' || e.button !== 0 ||
        e.altKey || e.ctrlKey || e.metaKey || e.shiftKey ||
        selected() || interactive(e)) return;
    pointer = { id: e.pointerId, x: e.clientX, y: e.clientY };
    // Do NOT capture/prevent pointerdown or pointermove: native word selection
    // must be allowed to start before we decide this was a page gesture.
  });
  on(doc, 'selectionchange', () => { if (selected()) cancel(); });
  on(doc, 'pointerup', e => {
    const start = pointer;
    cancel();
    if (!start || e.pointerId !== start.id || e.button !== 0 ||
        !dragEnabled() || selected() || interactive(e)) return;
    const direction = desktopDragDirection(e.clientX - start.x, e.clientY - start.y);
    if (!direction) return;
    consume(e);
    suppressClickUntil = Date.now() + 400;
    turn(direction);
  });
  on(doc, 'click', e => { if (Date.now() < suppressClickUntil) consume(e); });
  on(doc, 'dragstart', e => {
    // An image's native drag preview must not steal an unselected page gesture.
    if (pointer && !selected() && !interactive(e)) e.preventDefault();
  });
  on(doc, 'pointercancel', cancel);
  on(doc, 'mouseleave', cancel);
  on(doc.defaultView, 'blur', cancel);
  return { cancel, destroy() { cancel(); listeners.forEach(remove => remove()); } };
}
