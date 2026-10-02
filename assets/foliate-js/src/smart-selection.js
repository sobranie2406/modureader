// Like a native reader's word-boundary iterator, Intl.Segmenter resolves the
// pressed word in its paragraph. Only the initial long press is normalized;
// native selection handles and ordinary mouse dragging keep their own ranges.
const interactive = 'a[href],button,input,textarea,select,[contenteditable]:not([contenteditable="false"]),[role="textbox"],img,svg,video,audio,rt';
const paragraphTags = 'p,li,dt,dd,blockquote,figcaption,pre,td,th,h1,h2,h3,h4,h5,h6';
const maxText = 65536;
const sameRange = (a, b) => a && b && a.startContainer === b.startContainer &&
  a.startOffset === b.startOffset && a.endContainer === b.endContainer && a.endOffset === b.endOffset;
const activeRange = doc => {
  const selection = doc.getSelection();
  return selection?.rangeCount && !selection.isCollapsed ? selection.getRangeAt(0) : null;
};
const blocked = element => element?.closest?.(interactive);
const hidden = element => {
  const css = element.ownerDocument.defaultView?.getComputedStyle(element);
  return element.hidden || element.getAttribute('aria-hidden') === 'true' ||
    css?.display === 'none' || css?.visibility === 'hidden' || css?.userSelect === 'none';
};
const isBlock = element => element.matches(paragraphTags) ||
  /^(block|list-item|table-cell|flex|grid)$/.test(element.ownerDocument.defaultView?.getComputedStyle(element).display);

function contextAt(doc, node, offset) {
  if (node?.nodeType !== 3 || !node.isConnected || !doc.body?.contains(node) || blocked(node.parentElement)) return null;
  let root = node.parentElement;
  while (root !== doc.body && !isBlock(root)) root = root.parentElement;
  // Stop at actual block/BR boundaries, but join inline spans (including
  // highlights, emphasis, ruby bases and visual highlighter wrappers).
  const parts = [], positions = [];
  let length = 0, anchor = -1, count = 0;
  const append = text => { parts.push(text); length += text.length; };
  const stack = [root];
  while (stack.length) {
    const current = stack.pop();
    if (++count > 20000 || length > maxText) return null;
    if (current.nodeType === 3) {
      if (current === node) anchor = length + Math.min(Math.max(offset, 0), current.length);
      positions.push({ node: current, start: length, end: length + current.length });
      append(current.data);
    } else if (current.nodeType === 1) {
      if (hidden(current)) continue;
      if (current.matches('rt,rp,script,style')) continue;
      if (blocked(current) || current.matches('iframe,object')) { append('\uFFFC'); continue; }
      if (current.localName === 'br') { append(root.matches(paragraphTags) ? '\n' : '\u2029'); continue; }
      if (current !== root && isBlock(current)) { append('\u2029'); continue; }
      stack.push(...Array.from(current.childNodes).reverse());
    }
  }
  return anchor < 0 || length > maxText ? null : { text: parts.join(''), positions, anchor };
}

export function wordBounds(text, offset, locale) {
  if (!text || !Number.isInteger(offset) || offset < 0 || offset > text.length) return null;
  const index = offset === text.length ? offset - 1 : offset;
  if (typeof Intl?.Segmenter === 'function') {
    let segmenter;
    try { segmenter = new Intl.Segmenter(locale || undefined, { granularity: 'word' }); }
    catch { segmenter = new Intl.Segmenter(undefined, { granularity: 'word' }); }
    for (const segment of segmenter.segment(text)) {
      if (segment.index <= index && index < segment.index + segment.segment.length)
        return segment.isWordLike ? [segment.index, segment.index + segment.segment.length] : null;
    }
    return null;
  }
  // Older engines retain their native CJK/Thai word selection. Never turn an
  // unsegmented Chinese sentence into one giant "word" as a regex fallback.
  const chars = Array.from(text), offsets = [];
  let total = 0;
  for (const char of chars) { offsets.push(total); total += char.length; }
  const word = char => char && /[\p{L}\p{M}\p{N}_]/u.test(char) &&
    !/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Thai}\p{Script=Lao}\p{Script=Khmer}\p{Script=Myanmar}]/u.test(char);
  const at = offsets.findIndex((start, i) => start <= index && index < start + chars[i].length);
  if (at < 0 || !word(chars[at])) return null;
  let start = at, end = at + 1;
  while (start > 0 && word(chars[start - 1])) start--;
  while (end < chars.length && word(chars[end])) end++;
  return [offsets[start], end === chars.length ? text.length : offsets[end]];
}

export function smartSelectionRange(doc, { node, offset }, { paragraph = false, locale } = {}) {
  const context = contextAt(doc, node, offset);
  if (!context) return null;
  const { text, positions, anchor } = context;
  let bounds;
  if (paragraph) {
    let start = text.lastIndexOf('\u2029', anchor - 1) + 1;
    let end = text.indexOf('\u2029', anchor);
    if (end < 0) end = text.length;
    while (start < end && /\s/u.test(text[start])) start++;
    while (end > start && /\s/u.test(text[end - 1])) end--;
    bounds = start < end ? [start, end] : null;
  } else bounds = wordBounds(text, anchor, locale);
  return rangeForBounds(doc, context, bounds, !paragraph);
}

function rangeForBounds(doc, { text, positions, anchor }, bounds, containsAnchor = true) {
  if (!Array.isArray(bounds) || bounds.length !== 2) return null;
  const [start, end] = bounds;
  const index = anchor === text.length ? anchor - 1 : anchor;
  if (!Number.isInteger(start) || !Number.isInteger(end) || start < 0 || start >= end || end > text.length ||
      (containsAnchor && (start > index || index >= end))) return null;
  const first = positions.find(p => p.start <= start && start < p.end);
  const last = positions.find(p => p.start < end && end <= p.end);
  if (!first || !last) return null;
  const range = doc.createRange();
  range.setStart(first.node, start - first.start);
  range.setEnd(last.node, end - last.start);
  return range;
}

function textHit(doc, x, y) {
  let caret;
  try {
    const position = doc.caretPositionFromPoint?.(x, y);
    const fallback = position ? null : doc.caretRangeFromPoint?.(x, y);
    caret = { node: position?.offsetNode ?? fallback?.startContainer,
      offset: position?.offset ?? fallback?.startOffset };
  } catch { return null; }
  if (caret.node?.nodeType !== 3 || !caret.node.isConnected || blocked(caret.node.parentElement) ||
      !Number.isInteger(caret.offset) || caret.offset < 0 || caret.offset > caret.node.length) return null;
  const probe = doc.createRange();
  probe.selectNodeContents(caret.node);
  const contains = r => x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
  if (![...probe.getClientRects()].some(contains)) return null; // Do not snap margins to text.
  if (caret.offset > 0) {
    const previous = Array.from(caret.node.data.slice(0, caret.offset)).at(-1);
    probe.setStart(caret.node, caret.offset - previous.length);
    probe.setEnd(caret.node, caret.offset);
    // Caret APIs return insertion points: a tap on the right half of a final
    // glyph must still target that glyph, not the following punctuation.
    if ([...probe.getClientRects()].some(contains)) caret.offset -= previous.length;
  }
  return caret;
}

export function isInitialSmartSelection(doc, range) {
  if (!doc.__moduInitialSmartSelectionRange) return false;
  if (sameRange(doc.__moduInitialSmartSelectionRange, range)) return true;
  delete doc.__moduInitialSmartSelectionRange;
  return false;
}

// Chromium clears ShouldShowHandle for script-created selections (including
// setBaseAndExtent and live Range edits). Supply touch handles only for ranges
// we expanded ourselves; ordinary native selections keep their native handles.
function installExpandedSelectionHandles(doc, { onDragStart }) {
  let host, controls = [], owned, drag, disposed = false;
  const win = doc.defaultView, listeners = [];
  const hide = () => {
    drag = null; owned = null;
    host?.remove(); host = null; controls = [];
  };
  const isHandle = event => host && event.composedPath().includes(host);
  const endpoint = (range, end) => {
    const node = end ? range.endContainer : range.startContainer;
    const offset = end ? range.endOffset : range.startOffset;
    if (node.nodeType !== 3 || !node.isConnected) return null;
    const probe = doc.createRange();
    // Use the boundary glyph, not the whole range's bounding box: wrapped and
    // vertical paragraphs can have their endpoints on different lines/columns.
    const previous = Array.from(node.data.slice(0, offset)).at(-1)?.length ?? 0;
    const next = Array.from(node.data.slice(offset))[0]?.length ?? 0;
    probe.setStart(node, end ? offset - previous : offset);
    probe.setEnd(node, end ? offset : offset + next);
    const rects = [...probe.getClientRects()];
    const rect = end ? rects.at(-1) : rects[0];
    if (!rect) return null;
    const css = win.getComputedStyle(node.parentElement);
    const vertical = /^(vertical|sideways)/.test(css.writingMode);
    const rtl = css.direction === 'rtl';
    return vertical
      ? { x: rect.left - 10, y: end ? rect.bottom : rect.top,
        hitX: (rect.left + rect.right) / 2, hitY: end ? rect.bottom : rect.top }
      : { x: end !== rtl ? rect.right : rect.left, y: rect.bottom + 10,
        hitX: end !== rtl ? rect.right : rect.left, hitY: (rect.top + rect.bottom) / 2 };
  };
  const paint = () => {
    if (!owned || !sameRange(owned, activeRange(doc))) { hide(); return; }
    controls.forEach((control, index) => {
      const point = endpoint(owned, index === 1);
      const visible = point && point.x >= -10 && point.x <= win.innerWidth + 10 &&
        point.y >= 0 && point.y <= win.innerHeight + 10;
      control.style.display = visible ? 'block' : 'none';
      if (!visible) return;
      control.style.left = `${Math.max(18, Math.min(win.innerWidth - 18, point.x))}px`;
      control.style.top = `${Math.max(18, Math.min(win.innerHeight - 18, point.y))}px`;
    });
  };
  const show = range => {
    hide();
    if (disposed) return;
    owned = range.cloneRange();
    host = doc.createElement('div');
    host.dataset.moduSelectionHandles = '';
    host.setAttribute('aria-hidden', 'true'); // Native selection stays accessible.
    host.style.cssText = 'all:initial!important;position:fixed!important;inset:0!important;pointer-events:none!important;z-index:2147483647!important;';
    const root = host.attachShadow({ mode: 'open' });
    const css = doc.createElement('style');
    css.textContent = `
      span { position:fixed; width:36px; height:36px; transform:translate(-50%,-50%);
        pointer-events:auto; touch-action:none; user-select:none; -webkit-user-select:none; }
      span::after { content:''; position:absolute; left:10px; top:10px; width:16px; height:16px;
        box-sizing:border-box; border:1px solid white; border-radius:50%; background:#1976d2;
        box-shadow:0 1px 3px #0006; }
    `;
    root.append(css);
    controls = ['start', 'end'].map(side => {
      const control = doc.createElement('span');
      control.dataset.selectionHandle = side;
      root.append(control);
      return control;
    });
    doc.documentElement.append(host);
    paint();
  };
  const consume = event => { event.preventDefault(); event.stopImmediatePropagation(); };
  const start = event => {
    if (!isHandle(event)) { hide(); return; }
    consume(event);
    if (event.isPrimary === false || event.button > 0) return;
    const control = controls.find(item => event.composedPath().includes(item));
    if (!control || !owned) return;
    const end = control === controls[1];
    const point = endpoint(owned, end);
    if (!point) return;
    onDragStart();
    // Keep the opposite endpoint fixed, but allow crossing it without snapping
    // to a word again. Preserve the finger-to-text offset below the handle.
    drag = { id: event.pointerId, control,
      node: end ? owned.startContainer : owned.endContainer,
      offset: end ? owned.startOffset : owned.endOffset,
      dx: point.hitX - event.clientX, dy: point.hitY - event.clientY };
    try { control.setPointerCapture(event.pointerId); } catch { /* Document listener is the fallback. */ }
  };
  const move = event => {
    if (!drag || event.pointerId !== drag.id) return;
    consume(event);
    if (!drag.node.isConnected || !sameRange(owned, activeRange(doc))) { hide(); return; }
    const x = event.clientX + drag.dx, y = event.clientY + drag.dy;
    // Remove our hit target for caret hit-testing, not the selection itself.
    host.style.setProperty('visibility', 'hidden', 'important');
    let caret;
    try {
      const position = doc.caretPositionFromPoint?.(x, y);
      const range = position ? null : doc.caretRangeFromPoint?.(x, y);
      caret = { node: position?.offsetNode ?? range?.startContainer,
        offset: position?.offset ?? range?.startOffset };
    } catch { return; }
    finally { host.style.removeProperty('visibility'); }
    if (!Number.isInteger(caret.offset) || caret.offset < 0 || caret.offset > caret.node?.length ||
        !contextAt(doc, caret.node, caret.offset)) return;
    const range = doc.createRange();
    range.setStart(drag.node, drag.offset); range.collapse(true);
    if (range.comparePoint(caret.node, caret.offset) < 0) range.setStart(caret.node, caret.offset);
    else range.setEnd(caret.node, caret.offset);
    if (range.collapsed) return;
    owned = range.cloneRange();
    doc.getSelection().setBaseAndExtent(range.startContainer, range.startOffset, range.endContainer, range.endOffset);
    paint();
    doc.dispatchEvent(new win.Event('selectionchange'));
  };
  const end = event => {
    if (!drag || event.pointerId !== drag.id) return;
    consume(event);
    const previous = drag; drag = null;
    try { previous.control.releasePointerCapture(previous.id); } catch { /* Already released. */ }
    doc.dispatchEvent(new win.Event('selectionchange'));
  };
  const on = (target, name, handler) => {
    target.addEventListener(name, handler, { capture: true, passive: false });
    listeners.push(() => target.removeEventListener(name, handler, true));
  };
  on(doc, 'pointerdown', start); on(doc, 'pointermove', move);
  on(doc, 'pointerup', end); on(doc, 'pointercancel', end);
  // Suppress compatibility touch/click events before they reach page flipping,
  // quick-mark, smart-selection or the native long-press recognizer.
  for (const name of ['touchstart', 'touchmove', 'touchend', 'click', 'contextmenu'])
    on(doc, name, event => { if (isHandle(event)) consume(event); });
  on(doc, 'selectionchange', paint);
  on(doc, 'scroll', paint); on(win, 'resize', paint);
  on(doc, 'visibilitychange', hide); on(win, 'pagehide', hide);
  return { show, hide, ownsSelection: () => owned && sameRange(owned, activeRange(doc)),
    destroy() { disposed = true; hide(); listeners.forEach(remove => remove()); } };
}

// Android owns touch selection and can publish its initial character after
// pointercancel, action-mode creation or scroll-to-selection. Do not compete
// with it using a caret hit/timer: normalize the actual, settled native range.
function installNativeTouchSelection(doc, { enabled, paragraph, locale, segmentWord, onAdjusted, now }) {
  let session = null, hadSelection = !!activeRange(doc), excluded = false;
  let disposed = false, touch = null, suppressClickUntil = 0;
  const listeners = [];
  const handles = installExpandedSelectionHandles(doc, { onDragStart: () => {
    session = null; touch = null; excluded = true; hadSelection = true;
    delete doc.__moduInitialSmartSelectionRange;
  } });
  const permitted = () => !disposed && enabled() && !doc.__moduQuickMarkEnabled;
  const capture = range => {
    if (!permitted() || !range || !contextAt(doc, range.startContainer, range.startOffset) ||
        blocked(range.endContainer.parentElement)) return;
    session = { seed: range.cloneRange(), anchor: { node: range.startContainer, offset: range.startOffset },
      finished: false, pending: null };
  };
  const change = () => {
    const range = activeRange(doc);
    if (!range) {
      // Handles can briefly cross/collapse without a DOM touch event. Only a
      // fresh physical press with no selection may arm normalization again.
      if (hadSelection) excluded = true;
      session = null; hadSelection = false;
      delete doc.__moduInitialSmartSelectionRange;
      return;
    }
    if (!hadSelection && !excluded) capture(range);
    hadSelection = true;
    if (session && !sameRange(session.seed, range) && !sameRange(session.normalized, range)) {
      session = null; // Native handle changes are never repeatedly expanded.
      excluded = true;
      delete doc.__moduInitialSmartSelectionRange;
    }
  };
  const cancel = ({ preserveActiveSelection = false } = {}) => {
    const range = activeRange(doc);
    if (preserveActiveSelection && handles.ownsSelection()) return;
    if (preserveActiveSelection && session && range &&
        (sameRange(session.seed, range) || sameRange(session.normalized, range))) return;
    session = null; touch = null;
    handles.hide();
    hadSelection = !!range; excluded = true;
    delete doc.__moduInitialSmartSelectionRange;
  };
  const beforeSelection = () => {
    change();
    const current = session;
    if (!current || current.finished || !permitted()) return Promise.resolve();
    if (current.pending) return current.pending;
    const mode = paragraph(), language = locale();
    const context = contextAt(doc, current.anchor.node, current.anchor.offset);
    if (!context || !sameRange(current.seed, activeRange(doc))) return Promise.resolve();
    current.pending = (async () => {
      let range;
      if (mode) range = smartSelectionRange(doc, current.anchor, { paragraph: true, locale: language });
      else {
        // Use Android's local ICU boundaries even on a WebView whose own
        // Segmenter/native selection only recognizes one Chinese character.
        if (segmentWord) {
          try {
            const bounds = await segmentWord({ text: context.text, offset: context.anchor, locale: language });
            range = rangeForBounds(doc, context, bounds);
          } catch { /* Local browser segmentation is the non-network fallback. */ }
        }
        range ??= smartSelectionRange(doc, current.anchor, { locale: language });
      }
      const live = contextAt(doc, current.anchor.node, current.anchor.offset);
      if (session !== current || !permitted() || mode !== paragraph() || language !== locale() ||
          !sameRange(current.seed, activeRange(doc)) || live?.text !== context.text ||
          live?.anchor !== context.anchor) return;
      current.finished = true;
      if (!range || !range.startContainer.isConnected || !range.endContainer.isConnected) return;
      current.normalized = range.cloneRange();
      doc.__moduInitialSmartSelectionRange = range.cloneRange();
      suppressClickUntil = now() + 600;
      if (sameRange(current.seed, range)) return;
      const selection = doc.getSelection();
      if (selection.setBaseAndExtent)
        selection.setBaseAndExtent(range.startContainer, range.startOffset, range.endContainer, range.endOffset);
      else { selection.removeAllRanges(); selection.addRange(range); }
      handles.show(range);
      onAdjusted(range);
      doc.dispatchEvent(new doc.defaultView.Event('selectionchange'));
    })();
    return current.pending;
  };
  const nativeLongPress = () => {
    if (!permitted()) return;
    // Android recreates its menu while the user drags native handles, sometimes
    // without DOM touch events. A menu callback is NOT a new long press. Never
    // re-arm a finished session, even if the user selects the seed character.
    change();
    doc.dispatchEvent(new doc.defaultView.Event('selectionchange'));
  };
  const start = e => {
    const point = e.touches?.[0] ?? e;
    const isTouch = e.type === 'touchstart' || e.pointerType === 'touch' || e.pointerType === 'pen';
    if (!isTouch || e.touches?.length > 1 || e.isPrimary === false || e.button > 0 ||
        blocked(e.target) || !permitted()) { cancel(); return; }
    // Browsers dispatch both pointerdown and touchstart for one contact.
    if (touch && now() - touch.at < 50 &&
        Math.hypot(point.clientX - touch.x, point.clientY - touch.y) < 2) return;
    session = null;
    hadSelection = !!activeRange(doc); excluded = hadSelection;
    touch = { x: point.clientX, y: point.clientY, at: now(), handles: hadSelection };
    delete doc.__moduInitialSmartSelectionRange;
  };
  const move = e => {
    if (touch && (e.touches?.length > 1 ||
        Math.hypot((e.touches?.[0] ?? e).clientX - touch.x, (e.touches?.[0] ?? e).clientY - touch.y) > 8)) cancel();
  };
  const menu = () => nativeLongPress();
  const click = e => {
    if (now() < suppressClickUntil) { e.preventDefault(); e.stopImmediatePropagation(); }
  };
  const on = (target, name, handler) => {
    target?.addEventListener(name, handler, { capture: true });
    listeners.push(() => target?.removeEventListener(name, handler, true));
  };
  for (const [name, handler] of Object.entries({ pointerdown: start, touchstart: start,
    pointermove: move, touchmove: move, selectionchange: change, contextmenu: menu, click,
    keydown: () => cancel(), scroll: () => cancel({ preserveActiveSelection: true }),
    visibilitychange: () => cancel() })) on(doc, name, handler);
  on(doc.defaultView, 'pagehide', () => cancel());
  // Do not discard the range when the native action mode steals DOM focus.
  return { cancel, beforeSelection, nativeLongPress,
    destroy() { disposed = true; cancel(); handles.destroy(); for (const remove of listeners) remove(); } };
}

export function installSmartSelection(doc, {
  enabled = () => true, paragraph = () => false, locale = () => undefined,
  segmentWord, nativeTouchSelection = false,
  onAdjusted = () => {}, delay = 600, nativeDelay = 250, now = Date.now,
  setTimer = setTimeout, clearTimer = clearTimeout,
} = {}) {
  if (nativeTouchSelection)
    return installNativeTouchSelection(doc, { enabled, paragraph, locale, segmentWord, onAdjusted, now });
  let gesture = null, timer, expiry, suppressClickUntil = 0;
  const listeners = [];
  const cancelTimers = () => { clearTimer(timer); clearTimer(expiry); timer = expiry = undefined; };
  const cancel = () => { cancelTimers(); gesture = null; };
  const apply = () => {
    const current = gesture;
    if (!current || current.applied || !enabled() || doc.__moduQuickMarkEnabled || !current.anchor.node.isConnected) return;
    const native = activeRange(doc);
    // Native handles stay authoritative. In particular, never replace an
    // unrelated existing range, e.g. after a right-click or selection drag.
    if (native && !native.isPointInRange(current.anchor.node, current.anchor.offset)) return;
    // Mobile WebViews do not always create/report a native range. A stationary
    // full long press can create it, just like the desktop path. A released or
    // cancelled pointer must only adjust a subsequently reported native range.
    if (!native && (current.awaitingNative || now() - current.started < delay)) return;
    // An asynchronous system boundary must not overwrite a handle adjustment
    // that happened while it was pending.
    if (current.waitingRange && !sameRange(current.waitingRange, native)) { cancel(); return; }
    let range = smartSelectionRange(doc, current.anchor, { paragraph: paragraph(), locale: locale() });
    if (!range && !paragraph() && current.nativeWord?.locale === locale()) {
      const context = contextAt(doc, current.anchor.node, current.anchor.offset);
      if (context?.text === current.nativeWord.text && context.anchor === current.nativeWord.anchor)
        range = rangeForBounds(doc, context, current.nativeBounds);
      if (!range && native && !current.waitingRange) current.waitingRange = native.cloneRange();
    }
    if (!range) return;
    current.applied = true;
    cancelTimers();
    doc.__moduInitialSmartSelectionRange = range.cloneRange();
    const selection = doc.getSelection();
    if (!sameRange(native, range)) {
      if (selection.setBaseAndExtent) selection.setBaseAndExtent(range.startContainer, range.startOffset, range.endContainer, range.endOffset);
      else { selection.removeAllRanges(); selection.addRange(range); }
    }
    suppressClickUntil = now() + 600;
    onAdjusted(range);
    doc.dispatchEvent(new doc.defaultView.Event('selectionchange'));
  };
  const start = e => {
    if (e.touches?.length > 1 || e.isPrimary === false) { cancel(); return; }
    const point = e.touches?.[0] ?? e;
    const kind = e.touches ? 'touch' : (e.pointerType || 'mouse');
    if (gesture?.kind === kind && Math.hypot(point.clientX - gesture.x, point.clientY - gesture.y) < 2 && now() - gesture.started < 50) return;
    cancel();
    delete doc.__moduInitialSmartSelectionRange;
    if (!enabled() || doc.__moduQuickMarkEnabled || blocked(e.target) ||
        e.button > 0 || e.detail > 1 || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return;
    const anchor = textHit(doc, point.clientX, point.clientY);
    if (!anchor) return;
    const old = activeRange(doc);
    if (old?.isPointInRange(anchor.node, anchor.offset)) return; // Handle adjustment, not a new press.
    gesture = { anchor, kind, x: point.clientX, y: point.clientY, started: now(), applied: false };
    const current = gesture;
    if (!paragraph() && typeof Intl?.Segmenter !== 'function' && segmentWord) {
      const context = contextAt(doc, anchor.node, anchor.offset);
      if (context) {
        current.nativeWord = { text: context.text, anchor: context.anchor, locale: locale() };
        // Start local segmentation before the long-press deadline, so an older
        // Android WebView does not add a second wait to the gesture.
        Promise.resolve().then(() => {
          if (gesture !== current) return null;
          return segmentWord({ text: context.text, offset: context.anchor, locale: current.nativeWord.locale });
        }).then(bounds => {
          if (gesture !== current || current.applied) return;
          current.nativeBounds = bounds;
          if (now() - current.started >= nativeDelay) apply();
        }).catch(() => {}); // Preserve native selection if the bridge is unavailable.
      }
    }
    timer = setTimer(apply, delay);
  };
  const move = e => {
    if (!gesture) return;
    const point = e.touches?.[0] ?? e;
    if (e.touches?.length > 1 || Math.hypot(point.clientX - gesture.x, point.clientY - gesture.y) > 8) cancel();
  };
  const awaitNative = (nativeOnly = true) => {
    cancelTimers();
    gesture.awaitingNative = gesture.awaitingNative || nativeOnly;
    // Selection may be reported before our minimum native long-press delay.
    // Recheck it once at that boundary, without synthesizing an abandoned touch.
    timer = setTimer(apply, Math.max(0, nativeDelay - (now() - gesture.started)));
    expiry = setTimer(cancel, 1000);
  };
  const finish = () => {
    if (!gesture) return;
    if (gesture.applied) { suppressClickUntil = now() + 600; cancel(); }
    else if (gesture.kind !== 'mouse' && now() - gesture.started >= nativeDelay) {
      apply();
      // Some WebViews publish the first native range only after touchend.
      if (gesture.applied) { suppressClickUntil = now() + 600; cancel(); }
      else awaitNative(now() - gesture.started < delay);
    } else cancel();
  };
  const interrupted = () => {
    if (gesture?.applied) { suppressClickUntil = now() + 600; cancel(); }
    else if (gesture && gesture.kind !== 'mouse') {
      // Android/WebView2 may take the pointer or blur the chapter before the
      // long-press delay, and only later report selectionchange. Keep the hit
      // point briefly, but never create a selection for a cancelled gesture.
      awaitNative();
    } else cancel();
  };
  const change = () => {
    if (gesture && !gesture.applied && gesture.kind !== 'mouse' && now() - gesture.started >= nativeDelay) apply();
  };
  const menu = () => change();
  const click = e => {
    if (now() < suppressClickUntil) { e.preventDefault(); e.stopImmediatePropagation(); }
  };
  const on = (target, type, fn) => {
    target?.addEventListener(type, fn, { capture: true });
    listeners.push(() => target?.removeEventListener(type, fn, true));
  };
  for (const [type, fn] of Object.entries({ pointerdown: start, touchstart: start,
    pointermove: move, touchmove: move, pointerup: finish, touchend: finish,
    pointercancel: interrupted, touchcancel: interrupted, selectionchange: change,
    contextmenu: menu, click, scroll: cancel, visibilitychange: cancel })) on(doc, type, fn);
  on(doc.defaultView, 'pagehide', cancel);
  on(doc.defaultView, 'blur', interrupted);
  return {
    cancel,
    destroy() { cancel(); delete doc.__moduInitialSmartSelectionRange; for (const remove of listeners) remove(); },
  };
}
