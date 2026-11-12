// Native WebViews can keep DOM focus after a Flutter AI panel opens. Handle
// reader input at its source instead of depending only on Flutter's Focus node.
const interactive = event => (event.composedPath?.() ?? [event.target]).some(
  node => node?.isContentEditable || node?.matches?.(
    'input, textarea, select, button, a[href], [role="textbox"], [role="slider"], [role="button"]'));

export function desktopPageKey(event, ctrlBrackets = false) {
  if (event.defaultPrevented || event.isComposing || event.altKey ||
      event.metaKey || event.shiftKey || interactive(event)) return 0;
  if (event.ctrlKey) {
    if (!ctrlBrackets) return 0;
    if (event.key === '[' || event.code === 'BracketLeft') return -1;
    if (event.key === ']' || event.code === 'BracketRight') return 1;
    return 0;
  }
  if (['ArrowRight', 'ArrowDown', 'PageDown', ' '].includes(event.key)) return 1;
  if (['ArrowLeft', 'ArrowUp', 'PageUp'].includes(event.key)) return -1;
  return 0;
}

export function readerShortcutAction(event, bindings) {
  if (event.defaultPrevented || event.isComposing || interactive(event)) return null;
  let key = event.key === ' ' ? 'space' : event.key?.toLowerCase();
  if (key?.length === 1 && !/^[a-z0-9\[\]]$/.test(key)) {
    if (/^(Key[A-Z]|Digit[0-9])$/.test(event.code ?? '')) key = event.code.slice(-1).toLowerCase();
    else if (event.code === 'BracketLeft') key = '[';
    else if (event.code === 'BracketRight') key = ']';
  }
  const modifiers = (event.ctrlKey ? 1 : 0) | (event.shiftKey ? 2 : 0) |
    (event.altKey ? 4 : 0) | (event.metaKey ? 8 : 0);
  return bindings?.[`${modifiers}:${key}`] ?? null;
}

export function desktopDragDirection(dx, dy) {
  if (![dx, dy].every(Number.isFinite)) return 0;
  const distance = Math.max(Math.abs(dx), Math.abs(dy));
  if (distance < 48 || Math.abs(Math.abs(dx) - Math.abs(dy)) < distance * .2) return 0;
  return (Math.abs(dx) > Math.abs(dy) ? dx : dy) < 0 ? 1 : -1;
}

export function desktopWheelZoomDirection(event, modifier = 'ctrl') {
  if (event.defaultPrevented || event.altKey || event.shiftKey || interactive(event) ||
      !Number.isFinite(event.deltaY) || event.deltaY === 0 ||
      Math.abs(event.deltaX || 0) > Math.abs(event.deltaY)) return 0;
  const pressed = modifier === 'meta'
    ? event.metaKey && !event.ctrlKey : event.ctrlKey && !event.metaKey;
  return pressed ? (event.deltaY < 0 ? 1 : -1) : 0;
}

export function installDesktopPageInput(doc, { enabled, turnPage, hasSelection,
  dragEnabled = enabled, nativeKeysEnabled = enabled,
  zoomEnabled = enabled, zoomModifier = () => 'ctrl', onZoom = () => {},
  focusOnPointerDown = () => false, ctrlBrackets = () => false,
  shortcuts = () => null, onAction = () => {}, panArrow = () => false }) {
  let pointer = null;
  let turning = false;
  let suppressClickUntil = 0;
  let zoomTimer = null, pendingZoom = 0;
  const listeners = [];
  const selected = () => hasSelection?.() || !!doc.getSelection()?.toString();
  const on = (target, type, listener) => {
    if (!target) return;
    const options = { capture: true, passive: false };
    target.addEventListener(type, listener, options);
    listeners.push(() => target.removeEventListener(type, listener, options));
  };
  const consume = e => { e.preventDefault(); e.stopImmediatePropagation(); };
  const cancel = () => { pointer = null; };
  const cancelZoom = () => {
    clearTimeout(zoomTimer);
    zoomTimer = null;
    pendingZoom = 0;
  };
  const flushZoom = () => {
    zoomTimer = null;
    const direction = pendingZoom;
    pendingZoom = 0;
    if (direction && zoomEnabled() && !selected()) {
      onZoom(direction);
      zoomTimer = setTimeout(flushZoom, 80);
    }
  };
  on(doc, 'wheel', e => {
    if (!zoomEnabled() || selected()) return;
    const direction = desktopWheelZoomDirection(e, zoomModifier());
    if (!direction) return;
    consume(e);
    cancel();
    if (zoomTimer == null) {
      onZoom(direction);
      zoomTimer = setTimeout(flushZoom, 80);
    } else pendingZoom = direction;
  });
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
    if (!e.defaultPrevented && !e.isComposing && !e.ctrlKey && !e.shiftKey && !e.altKey && !e.metaKey &&
        !interactive(e) && panArrow(e.key?.toLowerCase())) { consume(e); return; }
    const bindings = shortcuts();
    if (bindings != null) {
      const action = readerShortcutAction(e, bindings);
      if (!action) return;
      consume(e);
      if (action === 'previous' || action === 'next') {
        turn(action === 'next' ? 1 : -1);
      } else if (!e.repeat) {
        onAction(action);
      }
      return;
    }
    const direction = desktopPageKey(e, ctrlBrackets());
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
    if (!dragEnabled() || doc.pdfZoomGestureActive?.() || e.pointerType !== 'mouse' || e.button !== 0 ||
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
        !dragEnabled() || doc.pdfZoomGestureActive?.() || selected() || interactive(e)) return;
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
  on(doc.defaultView, 'blur', cancelZoom);
  return { cancel,
    panFromKeyboard(key) {
      return nativeKeysEnabled() && !selected() && !interactive({target: doc.activeElement}) && panArrow(key);
    },
    actionFromKeyboard(action) {
      const narration = ['playPause', 'previousPassage', 'nextPassage'].includes(action);
      if (!nativeKeysEnabled() || (!narration && selected()) || interactive({ target: doc.activeElement })) return false;
      onAction(action);
      return true;
    },
    // Windows texture focus can deliver the key to Flutter instead of the DOM.
    // Reuse the DOM selection/editor guards without moving native focus.
    turnFromKeyboard(direction) {
      if (![1, -1].includes(direction) || !nativeKeysEnabled() || selected() ||
          interactive({ target: doc.activeElement })) return false;
      turn(direction);
      return true;
    },
    destroy() { cancel(); cancelZoom(); listeners.forEach(remove => remove()); } };
}
