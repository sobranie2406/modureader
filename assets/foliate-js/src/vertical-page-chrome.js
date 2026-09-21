// Reserve physical gutters on the renderer host, not the Flutter WebView.
// iframe DOM rectangles therefore still include the offset for selections,
// annotations and search hits; the WebView's coordinate origin never moves.
export function applyVerticalPageChrome(renderer, style = {}) {
  if (!renderer?.style) return false;
  const mode = style.writingMode === 'auto' || !style.writingMode
    ? renderer.writingMode : style.writingMode;
  const active = mode?.startsWith('vertical') && !!style.verticalPageInsets;
  const rules = active && style.verticalRedFrame === true ? 'true' : 'false';
  if (renderer.getAttribute('vertical-column-rules') !== rules)
    renderer.setAttribute('vertical-column-rules', rules);
  const safe = value => Math.min(240, Math.max(0, Number(value) || 0));
  const inset = style.verticalPageInsets ?? {};
  const padding = active
    ? `${safe(inset.top)}px ${safe(inset.right)}px ${safe(inset.bottom)}px ${safe(inset.left)}px`
    : '0px';
  renderer.style.boxSizing = 'border-box';
  if (renderer.style.padding !== padding) renderer.style.padding = padding;
  // The dedicated gutters replace the old (rotated) header/footer margins.
  for (const [name, value] of [
    ['top-margin', active ? 0 : (style.topMargin ?? 0)],
    ['bottom-margin', active ? 0 : (style.bottomMargin ?? 0)],
  ]) {
    const pixels = `${value}px`;
    if (renderer.getAttribute(name) !== pixels) renderer.setAttribute(name, pixels);
  }
  renderWebChrome(renderer, style, active);
  return !!active;
}

// macOS must not place a full-window Flutter paint layer over WKWebView:
// IgnorePointer only affects Flutter hit testing, not the native overlay.
// Keep decorations outside chapter documents (and therefore outside CFIs).
const chromeNodes = new WeakMap();
function renderWebChrome(renderer, style, active) {
  const data = style.verticalPageChrome;
  let nodes = chromeNodes.get(renderer);
  if (!active || !data || !renderer.shadowRoot) {
    nodes?.root.remove();
    chromeNodes.delete(renderer);
    return;
  }
  if (!nodes) {
    const make = (parent, css) => {
      const element = renderer.ownerDocument.createElement('div');
      element.style.cssText = css + ';pointer-events:none!important;box-sizing:border-box';
      parent.append(element);
      return element;
    };
    const root = make(renderer.shadowRoot,
      'position:absolute;inset:0;z-index:2;user-select:none;overflow:hidden');
    root.id = 'vertical-page-chrome';
    const outer = make(root, 'position:absolute;border:3px solid #c91c24');
    const inner = make(root, 'position:absolute;border:1px solid #c91c24');
    const left = make(root, 'position:absolute;border-left:1px solid #c91c24');
    const right = make(root, 'position:absolute;border-left:1px solid #c91c24');
    const title = make(root, 'position:absolute');
    const footer = make(root, 'position:absolute;display:flex;flex-direction:column;gap:12px');
    const remaining = make(footer, 'flex:1;min-height:0;display:flex;justify-content:center');
    const progress = make(footer, 'flex:1;min-height:0;display:flex;justify-content:center;align-items:flex-end');
    const label = parent => make(parent,
      'writing-mode:vertical-rl;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-height:100%;line-height:1.1;margin:auto');
    nodes = { root, outer, inner, left, right, title, footer,
      labels: [label(title), label(remaining), label(progress)] };
    nodes.labels[1].style.margin = '0';
    nodes.labels[2].style.margin = '0';
    chromeNodes.set(renderer, nodes);
  }
  const bounded = x => Math.min(240, Math.max(0, Number(x) || 0));
  const safe = Object.fromEntries(['top', 'right', 'bottom', 'left']
    .map(key => [key, bounded(data.safe?.[key])]));
  const insets = Object.fromEntries(['top', 'right', 'bottom', 'left']
    .map(key => [key, bounded(style.verticalPageInsets?.[key])]));
  for (const [box, offset] of [[nodes.outer, 8], [nodes.inner, 13]]) {
    for (const key of Object.keys(safe)) box.style[key] = `${safe[key] + offset}px`;
  }
  for (const [box, side] of [[nodes.left, 'left'], [nodes.right, 'right']]) {
    Object.assign(box.style, {top: `${safe.top + 13}px`, bottom: `${safe.bottom + 13}px`,
      [side]: `${insets[side] - 5}px`});
  }
  for (const box of [nodes.outer, nodes.inner, nodes.left, nodes.right])
    box.style.display = style.verticalRedFrame === true ? 'block' : 'none';
  for (const [box, side] of [[nodes.title, 'right'], [nodes.footer, 'left']]) {
    Object.assign(box.style, {top: `${insets.top + 8}px`, bottom: `${insets.bottom + 8}px`,
      [side]: `${safe[side] + 15}px`, width: `${Math.max(0, insets[side] - safe[side] - 23)}px`});
  }
  const texts = [data.title, data.remaining, data.progress];
  nodes.labels.forEach((label, i) => {
    const text = String(texts[i] ?? '');
    if (label.textContent !== text) label.textContent = text;
    Object.assign(label.style, {color: data.color || 'inherit',
      opacity: String(Math.min(1, Math.max(0, Number(data.opacity) || 0))),
      fontSize: `${Math.max(8, bounded(i === 0 ? data.headerFontSize : data.footerFontSize))}px`,
      textOrientation: data.chinese ? 'upright' : 'mixed'});
  });
}
