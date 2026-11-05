import { annotationRangeRects } from './annotation-geometry.js';

// Like a native reader's word-boundary iterator, Intl.Segmenter resolves the
// pressed word in its paragraph. Only the initial long press is normalized;
// handle adjustments and ordinary mouse dragging keep their own ranges.
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
    // Reader-owned layout runs must not consume the publisher-DOM safety budget.
    if (!current.__moduPageRun && !current.parentElement?.__moduPageRun) count++;
    if (count > 20000 || length > maxText) return null;
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
// setBaseAndExtent and live Range edits). Use one set of reader touch handles
// for mobile text selections, without the native drag magnifier.
function installExpandedSelectionHandles(doc, { onDragStart, textSelectionHighlight, selectionNavigation }) {
  let host, highlight, selectionStyle, controls = [], owned, drag, disposed = false;
  const win = doc.defaultView, listeners = [];
  const hide = () => {
    if (drag) selectionNavigation?.stop();
    drag = null; owned = null;
    host?.remove(); host = null; controls = [];
    selectionStyle?.remove(); selectionStyle = null;
    highlight?.remove(); highlight = null;
  };
  const isHandle = event => host && event.composedPath().includes(host);
  const endpoint = (range, end) => {
    let node = end ? range.endContainer : range.startContainer;
    let offset = end ? range.endOffset : range.startOffset;
    const boundary = selectionNavigation?.handleBoundary(end);
    // A page can begin at a paragraph boundary, not a text-node caret.
    if (node.nodeType === 1) {
      const after = offset > 0 && ((boundary ?? end) || offset === node.childNodes.length);
      const child = node.childNodes[after ? offset - 1 : offset];
      if (!child) return null;
      const walker = doc.createTreeWalker(child, win.NodeFilter.SHOW_TEXT, {
        acceptNode: text => text.data.trim() && !blocked(text.parentElement)
          ? win.NodeFilter.FILTER_ACCEPT : win.NodeFilter.FILTER_REJECT,
      });
      node = child.nodeType === 3 ? child : after ? walker.lastChild() : walker.nextNode();
      if (!node) return null;
      offset = after ? node.length : 0;
    }
    if (node.nodeType !== 3 || !node.isConnected) return null;
    const probe = doc.createRange();
    // Use the boundary glyph, not the whole range's bounding box: wrapped and
    // vertical paragraphs can have their endpoints on different lines/columns.
    const previous = Array.from(node.data.slice(0, offset)).at(-1)?.length ?? 0;
    const next = Array.from(node.data.slice(offset))[0]?.length ?? 0;
    const after = boundary ?? (end && previous > 0 || !next);
    probe.setStart(node, after ? offset - previous : offset);
    probe.setEnd(node, after ? offset : offset + next);
    const rects = [...probe.getClientRects()];
    const rect = end ? rects.at(-1) : rects[0];
    if (!rect) return null;
    const css = win.getComputedStyle(node.parentElement);
    const vertical = /^(vertical|sideways)/.test(css.writingMode);
    const rtl = css.direction === 'rtl';
    return vertical
      ? { x: rect.left - 10, y: after ? rect.bottom : rect.top,
        hitX: (rect.left + rect.right) / 2, hitY: after ? rect.bottom : rect.top }
      : { x: after !== rtl ? rect.right : rect.left, y: rect.bottom + 10,
        hitX: after !== rtl ? rect.right : rect.left, hitY: (rect.top + rect.bottom) / 2 };
  };
  const paintHighlight = range => {
    // Native line boxes include leading; paint text fragments even before handles take over.
    const rects = range && textSelectionHighlight ? annotationRangeRects(range, true) : [];
    if (!rects.length) {
      highlight?.remove(); highlight = null;
      selectionStyle?.remove(); selectionStyle = null;
      return;
    }
    if (!highlight) {
      highlight = doc.createElement('div');
      highlight.dataset.selectionHighlight = '';
      highlight.setAttribute('aria-hidden', 'true');
      highlight.style.cssText = 'all:initial!important;position:fixed!important;top:0!important;right:0!important;bottom:0!important;left:0!important;pointer-events:none!important;z-index:2147483646!important;';
      highlight.attachShadow({ mode: 'open' });
      doc.documentElement.append(highlight);
    }
    highlight.shadowRoot.textContent = '';
    highlight.shadowRoot.append(...rects.map(rect => {
      const box = doc.createElement('i');
      box.style.cssText = `position:fixed;left:${rect.left}px;top:${rect.top}px;width:${rect.width}px;height:${rect.height}px;background:rgba(64,156,255,.35);pointer-events:none;`;
      return box;
    }));
    if (rects.length && !selectionStyle) {
      selectionStyle = doc.createElement('style');
      selectionStyle.textContent = 'html { -webkit-touch-callout:none!important; } ::selection { background-color:transparent!important; } ::selection:window-inactive { background-color:transparent!important; }';
      doc.head.append(selectionStyle);
    }
  };
  const paint = () => {
    if (!owned || !sameRange(owned, activeRange(doc))) { hide(); return; }
    paintHighlight(owned);
    const bounds = selectionNavigation?.handleBounds() ?? {
      left: 0, top: 0, right: win.innerWidth, bottom: win.innerHeight,
    };
    const safe = bounds.safe ?? bounds;
    controls.forEach((control, index) => {
      const point = endpoint(owned, index === 1);
      const visible = point && point.x >= bounds.left - 10 && point.x <= bounds.right + 10 &&
        point.y >= bounds.top && point.y <= bounds.bottom + 10;
      control.style.display = visible ? 'block' : 'none';
      if (!visible) return;
      // Keep re-grabbable controls outside mobile system edge gestures, even
      // when the chapter iframe spans many horizontally paginated screens.
      control.style.left = `${Math.max(safe.left + 32, Math.min(safe.right - 32, point.x))}px`;
      // iOS still reserves touches immediately below the top safe inset.
      const topGap = safe.top > bounds.top ? 36 : 18;
      control.style.top = `${Math.max(safe.top + topGap, Math.min(safe.bottom - 18, point.y))}px`;
    });
  };
  const show = range => {
    hide();
    if (disposed) return;
    owned = range.cloneRange();
    host = doc.createElement('div');
    host.dataset.moduSelectionHandles = '';
    host.setAttribute('aria-hidden', 'true'); // Native selection stays accessible.
    host.style.cssText = 'all:initial!important;position:fixed!important;top:0!important;right:0!important;bottom:0!important;left:0!important;pointer-events:none!important;z-index:2147483647!important;';
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
    if (event.isPrimary === false || event.button > 0) {
      selectionNavigation?.stop(); drag = null; return;
    }
    const control = controls.find(item => event.composedPath().includes(item));
    if (!control || !owned) return;
    const end = control === controls[1];
    const point = endpoint(owned, end);
    if (!point) return;
    onDragStart();
    // Keep the opposite endpoint fixed, but allow crossing it without snapping
    // to a word again. Preserve the finger-to-text offset within the hit target.
    drag = { id: event.pointerId, control,
      node: end ? owned.startContainer : owned.endContainer,
      offset: end ? owned.startOffset : owned.endOffset,
      dx: point.hitX - event.clientX, dy: point.hitY - event.clientY };
    const anchor = { node: drag.node, offset: drag.offset };
    selectionNavigation?.begin({ anchor, backwards: !end,
      point: { x: point.hitX, y: point.hitY }, write: range => {
        owned = range.cloneRange();
        const backwards = range.endContainer === anchor.node && range.endOffset === anchor.offset;
        if (!sameRange(range, activeRange(doc)))
          doc.getSelection().setBaseAndExtent(anchor.node, anchor.offset,
            backwards ? range.startContainer : range.endContainer,
            backwards ? range.startOffset : range.endOffset);
        paint();
      }, extend: point => extend(point.x, point.y) });
    try { control.setPointerCapture(event.pointerId); } catch { /* Document listener is the fallback. */ }
  };
  const extend = (x, y) => {
    if (!drag) return;
    if (!drag.node.isConnected || !sameRange(owned, activeRange(doc))) { hide(); return; }
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
    doc.getSelection().setBaseAndExtent(drag.node, drag.offset, caret.node, caret.offset);
    paint();
    doc.dispatchEvent(new win.Event('selectionchange'));
  };
  const move = event => {
    if (!drag || event.pointerId !== drag.id) return;
    consume(event);
    const point = { x: event.clientX + drag.dx, y: event.clientY + drag.dy };
    if (selectionNavigation?.move(point, { x: event.clientX, y: event.clientY })) return;
    extend(point.x, point.y);
  };
  const end = event => {
    if (!drag || event.pointerId !== drag.id) return;
    consume(event);
    selectionNavigation?.stop();
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
  on(doc, 'keydown', hide);
  on(doc, 'visibilitychange', hide); on(win, 'pagehide', hide);
  return { show, hide, paintHighlight, ownsSelection: () => owned && sameRange(owned, activeRange(doc)),
    destroy() { disposed = true; hide(); listeners.forEach(remove => remove()); } };
}

// Android owns touch selection and can publish its initial character after
// pointercancel, action-mode creation or scroll-to-selection. Do not compete
// with it using a caret hit/timer: normalize the actual, settled native range.
function installNativeTouchSelection(doc, { enabled, paragraph, locale, segmentWord, segmentParagraph, onAdjusted, now, textSelectionHighlight, selectionNavigation, setTimer, clearTimer }) {
  let session = null, hadSelection = !!activeRange(doc), excluded = false;
  let disposed = false, touch = null, suppressClickUntil = 0;
  let touchHandlesAllowed = true;
  let pendingPenSelection = false;
  let wordCache = null;
  const listeners = [];
  const handles = installExpandedSelectionHandles(doc, { textSelectionHighlight, selectionNavigation, onDragStart: () => {
    session = null; touch = null; excluded = true; hadSelection = true;
    delete doc.__moduInitialSmartSelectionRange;
  } });
  const permitted = () => !disposed && enabled() && !doc.__moduQuickMarkEnabled;
  const containsHit = (range, hit) => hit?.node.isConnected &&
    hit.offset >= 0 && hit.offset <= hit.node.length &&
    range.isPointInRange(hit.node, hit.offset) &&
    !(range.endContainer === hit.node && range.endOffset === hit.offset);
  const prepareWords = (context, language) => {
    if (!context || !segmentParagraph) return null;
    if (wordCache?.text === context.text && wordCache.language === language) return wordCache;
    const entry = wordCache = { text: context.text, language, words: null };
    // A single paragraph, keyed by text rather than DOM nodes: repagination cannot stale offsets.
    if (typeof Intl?.Segmenter === 'function') {
      let segmenter;
      try { segmenter = new Intl.Segmenter(language || undefined, { granularity: 'word' }); }
      catch { segmenter = new Intl.Segmenter(undefined, { granularity: 'word' }); }
      entry.words = [...segmenter.segment(context.text)].filter(part => part.isWordLike)
        .map(part => [part.index, part.index + part.segment.length]);
    }
    Promise.resolve().then(() => !disposed && wordCache === entry
      ? segmentParagraph({ text: entry.text, locale: language }) : null).then(words => {
      if (disposed || wordCache !== entry || !Array.isArray(words) || words.length > entry.text.length) return;
      let previousEnd = 0;
      for (const word of words) {
        if (!Array.isArray(word) || word.length !== 2 || !word.every(Number.isInteger) ||
            word[0] < previousEnd || word[0] >= word[1] || word[1] > entry.text.length) return;
        previousEnd = word[1];
      }
      entry.words = words; // Cache only; late results never move an existing selection.
    }).catch(() => {});
    return entry;
  };
  const capture = range => {
    if (!permitted() || !range || !contextAt(doc, range.startContainer, range.startOffset) ||
        blocked(range.endContainer.parentElement)) return;
    session = { seed: range.cloneRange(), anchor: containsHit(range, touch?.anchor)
      ? touch.anchor : { node: range.startContainer, offset: range.startOffset },
      finished: false, pending: null };
  };
  const change = (normalize = true, confirmPress = false) => {
    const range = activeRange(doc);
    handles.paintHighlight(touchHandlesAllowed && !disposed && !doc.__moduQuickMarkEnabled && range &&
      contextAt(doc, range.startContainer, range.startOffset) &&
      contextAt(doc, range.endContainer, range.endOffset) ? range : null);
    if (!range) {
      // Handle collapse alone must not re-arm expansion; a fresh physical press is required.
      if (hadSelection) excluded = true;
      session = null; hadSelection = false;
      delete doc.__moduInitialSmartSelectionRange;
      return;
    }
    // A fresh press on a glyph is not a handle adjustment, even if the old range still exists.
    if (touch?.restart && (touch.endedAt ?? now()) - touch.at >= 250 &&
        containsHit(range, touch.anchor) && (confirmPress || !sameRange(touch.previous, range))) {
      touch.restart = false;
      session = null; hadSelection = false; excluded = false;
    }
    const initial = !hadSelection && !excluded;
    if (initial) capture(range);
    hadSelection = true;
    if (session && !sameRange(session.seed, range) && !sameRange(session.normalized, range)) {
      session = null; // Native handle changes are never repeatedly expanded.
      excluded = true;
      delete doc.__moduInitialSmartSelectionRange;
    }
    if (initial && normalize && segmentParagraph && session) {
      normalizeSelection();
      adoptHandles();
    }
  };
  const cancel = ({ preserveActiveSelection = false } = {}) => {
    const range = activeRange(doc);
    if (preserveActiveSelection && handles.ownsSelection()) return;
    if (preserveActiveSelection && pendingPenSelection && range) return;
    if (preserveActiveSelection && session && range &&
        (sameRange(session.seed, range) || sameRange(session.normalized, range))) return;
    session = null; touch = null;
    pendingPenSelection = false;
    touchHandlesAllowed = false;
    handles.hide();
    hadSelection = !!range; excluded = true;
    delete doc.__moduInitialSmartSelectionRange;
  };
  const normalizeSelection = () => {
    change(false);
    const current = session;
    if (!current || current.finished || !permitted()) return Promise.resolve();
    if (current.pending) return current.pending;
    const mode = paragraph(), language = locale();
    const context = contextAt(doc, current.anchor.node, current.anchor.offset);
    if (!context || !sameRange(current.seed, activeRange(doc))) return Promise.resolve();
    current.pending = (async () => {
      let range;
      if (mode) range = smartSelectionRange(doc, current.anchor, { paragraph: true, locale: language });
      else if (segmentParagraph) {
        const cached = prepareWords(context, language);
        const index = context.anchor === context.text.length ? context.anchor - 1 : context.anchor;
        range = rangeForBounds(doc, context, cached?.words?.find(([start, end]) => start <= index && index < end));
        range ??= smartSelectionRange(doc, current.anchor, { locale: language });
      } else {
        // Use Android's local ICU boundaries even on a WebView whose own
        // Segmenter/native selection only recognizes one Chinese character.
        if (segmentWord) {
          let timeout;
          try {
            // Bound the entire JS bridge, not only the native ICU call inside Flutter.
            const bounds = await Promise.race([
              segmentWord({ text: context.text, offset: context.anchor, locale: language }),
              new Promise(resolve => { timeout = setTimer(() => resolve(null), 120); }),
            ]);
            range = rangeForBounds(doc, context, bounds);
          } catch { /* Local browser segmentation is the non-network fallback. */ }
          finally { clearTimer(timeout); }
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
      onAdjusted(range);
      doc.dispatchEvent(new doc.defaultView.Event('selectionchange'));
    })();
    return current.pending;
  };
  const adoptHandles = () => {
    const range = activeRange(doc);
    if (disposed || !touchHandlesAllowed || doc.__moduQuickMarkEnabled ||
        handles.ownsSelection() || !range ||
        !contextAt(doc, range.startContainer, range.startOffset) ||
        !contextAt(doc, range.endContainer, range.endOffset)) return;
    // Reset even an unchanged native word/paragraph: otherwise Chromium keeps
    // its OEM-coloured handles and magnifier alongside the reader controls.
    const selection = doc.getSelection(), owned = range.cloneRange();
    selection.removeAllRanges();
    selection.addRange(owned);
    handles.show(owned);
    pendingPenSelection = false;
  };
  const beforeSelection = async () => {
    const previous = activeRange(doc)?.cloneRange();
    // Show usable handles before waiting for the Android word-boundary bridge.
    adoptHandles();
    await normalizeSelection();
    const range = activeRange(doc);
    if (sameRange(previous, range) || sameRange(session?.normalized, range)) adoptHandles();
  };
  const nativeLongPress = () => {
    if (!permitted()) return;
    // Android recreates its menu while the user drags native handles, sometimes
    // without DOM touch events. A menu callback alone must never re-arm expansion;
    // a fresh physical press on a glyph is required to replace an old selection.
    change(true, true);
    doc.dispatchEvent(new doc.defaultView.Event('selectionchange'));
  };
  const start = e => {
    const point = e.touches?.[0] ?? e;
    const isTouch = e.type === 'touchstart' || e.pointerType === 'touch' || e.pointerType === 'pen';
    if (!isTouch || e.touches?.length > 1 || e.isPrimary === false || e.button > 0 ||
        blocked(e.target) || disposed || doc.__moduQuickMarkEnabled) { cancel(); return; }
    // Browsers dispatch both pointerdown and touchstart for one contact.
    if (touch && now() - touch.at < 50 &&
        Math.hypot(point.clientX - touch.x, point.clientY - touch.y) < 2) return;
    session = null;
    pendingPenSelection = false;
    touchHandlesAllowed = true;
    hadSelection = !!activeRange(doc); excluded = hadSelection;
    const anchor = permitted() ? textHit(doc, point.clientX, point.clientY) : null;
    touch = { x: point.clientX, y: point.clientY, at: now(), handles: hadSelection,
      pen: e.pointerType === 'pen', anchor, restart: !!anchor && hadSelection,
      previous: activeRange(doc)?.cloneRange() };
    delete doc.__moduInitialSmartSelectionRange;
    if (permitted() && !paragraph() && segmentParagraph) {
      if (anchor) prepareWords(contextAt(doc, anchor.node, anchor.offset), locale());
    }
  };
  const move = e => {
    if (touch && (e.touches?.length > 1 ||
        Math.hypot((e.touches?.[0] ?? e).clientX - touch.x, (e.touches?.[0] ?? e).clientY - touch.y) > 8)) {
      // Pen dragging chooses an exact range, not a word/paragraph or a scroll.
      const penSelection = touch.pen && !(e.touches?.length > 1);
      cancel();
      touchHandlesAllowed = penSelection;
      pendingPenSelection = penSelection;
    }
  };
  const menu = () => nativeLongPress();
  const end = () => { if (touch) touch.endedAt ??= now(); };
  const click = e => {
    if (now() < suppressClickUntil) { e.preventDefault(); e.stopImmediatePropagation(); }
  };
  const on = (target, name, handler) => {
    target?.addEventListener(name, handler, { capture: true });
    listeners.push(() => target?.removeEventListener(name, handler, true));
  };
  for (const [name, handler] of Object.entries({ pointerdown: start, touchstart: start,
    pointerup: end, touchend: end,
    pointermove: move, touchmove: move, selectionchange: change, contextmenu: menu, click,
    keydown: () => cancel(), scroll: () => { cancel({ preserveActiveSelection: true }); change(); },
    visibilitychange: () => cancel() })) on(doc, name, handler);
  on(doc.defaultView, 'pagehide', () => cancel());
  on(doc.defaultView, 'resize', change);
  // Do not discard the range when the native action mode steals DOM focus.
  return { cancel, beforeSelection, nativeLongPress,
    destroy() { disposed = true; wordCache = null; cancel(); handles.destroy(); for (const remove of listeners) remove(); } };
}

export function installSmartSelection(doc, {
  enabled = () => true, paragraph = () => false, locale = () => undefined,
  segmentWord, segmentParagraph, nativeTouchSelection = false, textSelectionHighlight = true,
  selectionNavigation,
  onAdjusted = () => {}, delay = 600, nativeDelay = 250, now = Date.now,
  setTimer = setTimeout, clearTimer = clearTimeout,
} = {}) {
  if (nativeTouchSelection)
    return installNativeTouchSelection(doc, { enabled, paragraph, locale, segmentWord, segmentParagraph, onAdjusted, now, textSelectionHighlight, selectionNavigation, setTimer, clearTimer });
  let gesture = null, timer, expiry, suppressClickUntil = 0;
  let touchHandlesAllowed = false;
  const listeners = [];
  const cancelTimers = () => { clearTimer(timer); clearTimer(expiry); timer = expiry = undefined; };
  const cancel = () => { cancelTimers(); gesture = null; };
  const handles = selectionNavigation ? installExpandedSelectionHandles(doc, {
    textSelectionHighlight, selectionNavigation, onDragStart: () => {
      cancel(); delete doc.__moduInitialSmartSelectionRange;
    },
  }) : null;
  const adoptHandles = () => {
    const range = activeRange(doc);
    if (!handles || !touchHandlesAllowed || !enabled() || doc.__moduQuickMarkEnabled ||
        handles.ownsSelection() || !range || !contextAt(doc, range.startContainer, range.startOffset) ||
        !contextAt(doc, range.endContainer, range.endOffset)) return;
    const owned = range.cloneRange(), selection = doc.getSelection();
    selection.removeAllRanges(); selection.addRange(owned);
    handles.show(owned);
  };
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
    adoptHandles();
    doc.dispatchEvent(new doc.defaultView.Event('selectionchange'));
  };
  const start = e => {
    if (e.touches?.length > 1 || e.isPrimary === false) { cancel(); return; }
    const point = e.touches?.[0] ?? e;
    const kind = e.touches ? 'touch' : (e.pointerType || 'mouse');
    touchHandlesAllowed = kind !== 'mouse';
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
    beforeSelection: adoptHandles,
    cancel({ preserveActiveSelection = false } = {}) {
      cancel();
      if (!preserveActiveSelection) { touchHandlesAllowed = false; handles?.hide(); }
    },
    destroy() { cancel(); handles?.destroy(); delete doc.__moduInitialSmartSelectionRange; for (const remove of listeners) remove(); },
  };
}
