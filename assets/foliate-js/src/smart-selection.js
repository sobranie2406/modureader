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

// Android owns touch selection and can publish its initial character after
// pointercancel, action-mode creation or scroll-to-selection. Do not compete
// with it using a caret hit/timer: normalize the actual, settled native range.
function installNativeTouchSelection(doc, { enabled, paragraph, locale, segmentWord, onAdjusted, now }) {
  let session = null, hadSelection = !!activeRange(doc), excluded = false;
  let disposed = false, touch = null, lastAdjustment = null, suppressClickUntil = 0;
  const listeners = [];
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
      session = null; hadSelection = false;
      if (touch?.handles) { touch.handles = false; excluded = false; }
      delete doc.__moduInitialSmartSelectionRange;
      return;
    }
    if (!hadSelection && !excluded) capture(range);
    hadSelection = true;
    if (session && !sameRange(session.seed, range) && !sameRange(session.normalized, range)) {
      session = null; // Native handle changes are never repeatedly expanded.
      delete doc.__moduInitialSmartSelectionRange;
    }
  };
  const cancel = ({ preserveActiveSelection = false } = {}) => {
    const range = activeRange(doc);
    if (preserveActiveSelection && session && range &&
        (sameRange(session.seed, range) || sameRange(session.normalized, range))) return;
    session = null; touch = null; lastAdjustment = null;
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
      lastAdjustment = { seed: current.seed.cloneRange(), normalized: range.cloneRange(), at: now() };
      suppressClickUntil = now() + 600;
      if (sameRange(current.seed, range)) return;
      const selection = doc.getSelection();
      if (selection.setBaseAndExtent)
        selection.setBaseAndExtent(range.startContainer, range.startOffset, range.endContainer, range.endOffset);
      else { selection.removeAllRanges(); selection.addRange(range); }
      onAdjusted(range);
      doc.dispatchEvent(new doc.defaultView.Event('selectionchange'));
    })();
    return current.pending;
  };
  const nativeLongPress = () => {
    if (!permitted()) return;
    const range = activeRange(doc);
    if (session && (sameRange(session.seed, range) || sameRange(session.normalized, range))) {
      if (session.finished && !excluded && sameRange(session.seed, range) &&
          !sameRange(session.seed, session.normalized)) capture(range);
      // Already pending/expanded. A repeated native menu callback must not
      // produce another bridge request or an action-mode/selection loop.
    } else if (range && !excluded && lastAdjustment && now() - lastAdjustment.at < 1500 &&
        sameRange(lastAdjustment.seed, range)) capture(range);
    else if (!touch?.handles) {
      excluded = false;
      if (range) capture(range);
    }
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
    session = null; lastAdjustment = null;
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
    destroy() { disposed = true; cancel(); for (const remove of listeners) remove(); } };
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
