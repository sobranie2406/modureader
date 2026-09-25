// Match in a parent-origin worker, never in the book iframe (script-src 'none').
// No DOM wrapping/splitting: CFI, annotations, selection and TTS retain their nodes.
export const matcherSource = `
self.onmessage = ({data}) => {
  const matches = [], errors = [];
  for (let r = 0; r < data.rules.length; r++) {
    const rule = data.rules[r];
    let regex;
    try { regex = new RegExp(rule.pattern, 'gu'); }
    catch (_) { errors.push(r); continue; }
    for (let g = 0; g < data.groups.length; g++) {
      const group = data.groups[g];
      if (rule.scope === 'title' && !group.title || rule.scope === 'body' && group.title) continue;
      regex.lastIndex = 0;
      let match;
      while ((match = regex.exec(group.text)) !== null) {
        if (match[0].length) matches.push([r, g, match.index, match.index + match[0].length]);
        else {
          const cp = group.text.codePointAt(regex.lastIndex);
          regex.lastIndex += cp > 65535 ? 2 : 1;
        }
        if (matches.length >= 2000) { self.postMessage({matches, errors, limited: true}); return; }
      }
    }
  }
  self.postMessage({matches, errors});
};`;

const states = new WeakMap();
const properties = ['color', 'background-color', 'text-decoration-line',
  'text-decoration-style', 'text-decoration-color', 'text-decoration-thickness'];
const heading = 'h1,h2,h3,h4,h5,h6,[role="heading"]';
const block = `${heading},p,li,blockquote,pre,td,th,div,section,article`;
const skip = 'script,style,noscript,svg,math,textarea,select,rt,rp,[hidden],[aria-hidden="true"],[role="doc-footnote"],[role="doc-endnote"],[role="doc-endnotes"],[role="doc-noteref"]';

export function highlightDeclarations(doc, css) {
  const style = doc.createElement('span').style;
  style.cssText = String(css ?? '');
  return properties.map(p => {
    const value = style.getPropertyValue(p);
    // These properties require no external resources. Disallow custom property
    // indirection and CSS token escapes from imported declarations as well.
    return value && !/[{}\\]|url\s*\(|var\s*\(/i.test(value) ? `${p}:${value};` : '';
  }).join('');
}

export function collectHighlightGroups(doc) {
  const root = doc.body;
  if (!root) return {groups: [], limited: false};
  const walker = doc.createTreeWalker(root, 4);
  const groups = [];
  let group, node, size = 0, visited = 0, limited = false;
  const excluded = new WeakMap();
  const invisible = el => {
    if (!el || el === root.parentElement) return false;
    if (excluded.has(el)) return excluded.get(el);
    const epubType = el.getAttribute('epub:type') ?? '';
    const css = doc.defaultView.getComputedStyle(el);
    const hidden = el.matches(skip) || /\b(footnotes?|endnotes?|noteref)\b/.test(epubType) ||
      css.display === 'none' || css.visibility === 'hidden' || invisible(el.parentElement);
    excluded.set(el, hidden);
    return hidden;
  };
  while ((node = walker.nextNode())) {
    if (++visited > 20000 || size >= 500000) return {groups, limited: true};
    const el = node.parentElement;
    if (!el || invisible(el)) { group = null; continue; }
    const owner = el.closest(block) ?? root;
    if (!group || group.owner !== owner) {
      group = {owner, title: !!el.closest(heading), text: '', nodes: []};
      groups.push(group);
    }
    const text = node.data.slice(0, 500000 - size);
    limited ||= text.length < node.data.length;
    group.nodes.push({node, start: group.text.length, end: group.text.length + text.length});
    group.text += text;
    size += text.length;
  }
  return {groups, limited};
}

export function clearCustomHighlights(doc) {
  const state = states.get(doc);
  if (!state) return;
  state.cancel();
  state.style?.remove();
  for (const name of state.names) doc.defaultView?.CSS?.highlights?.delete(name);
  doc.defaultView?.removeEventListener('pagehide', state.cleanup);
  states.delete(doc);
}

export async function applyCustomHighlights(doc, input, {onStatus = () => {}, timeout = 1200} = {}) {
  clearCustomHighlights(doc);
  const rules = (Array.isArray(input) ? input : []).slice(0, 8).filter(r =>
    typeof r.pattern === 'string' && r.pattern.length > 0 && r.pattern.length <= 512);
  if (!rules.length) return;
  const win = doc.defaultView;
  if (!win?.CSS?.highlights || !win.Highlight || typeof Worker === 'undefined') {
    onStatus('unsupported'); return;
  }
  const state = {names: [], style: null, cancel: () => {}, cleanup: () => clearCustomHighlights(doc)};
  states.set(doc, state);
  win.addEventListener('pagehide', state.cleanup, {once: true});
  let worker, url;
  try {
    const {groups, limited} = collectHighlightGroups(doc);
    url = URL.createObjectURL(new Blob([matcherSource], {type: 'text/javascript'}));
    worker = new Worker(url);
    const result = await new Promise(resolve => {
      const finish = value => { clearTimeout(timer); resolve(value); };
      const timer = setTimeout(() => finish({timeout: true}), timeout);
      state.cancel = () => { worker.terminate(); finish(null); };
      worker.onmessage = e => finish(e.data);
      worker.onerror = () => finish({error: true});
      worker.postMessage({rules, groups: groups.map(({text, title}) => ({text, title}))});
    });
    worker.terminate();
    if (!result || states.get(doc) !== state) return;
    if (result.timeout || result.error) { onStatus(result.timeout ? 'timeout' : 'error'); return; }
    const highlights = rules.map(() => new win.Highlight());
    for (const [r, g, start, end] of result.matches) {
      const nodes = groups[g].nodes;
      const first = nodes.find(n => n.start <= start && n.end > start);
      const last = nodes.find(n => n.start < end && n.end >= end);
      if (!first || !last || !first.node.isConnected || !last.node.isConnected) continue;
      const range = doc.createRange();
      range.setStart(first.node, start - first.start);
      range.setEnd(last.node, end - last.start);
      highlights[r].add(range);
    }
    state.style = doc.createElement('style');
    state.style.textContent = rules.map((rule, i) => {
      const name = `modu-custom-rule-${i}`;
      state.names.push(name);
      // Keep search/interactive highlights (default priority 0) on top.
      highlights[i].priority = -100 + i;
      win.CSS.highlights.set(name, highlights[i]);
      return `::highlight(${name}){${highlightDeclarations(doc, rule.css)}}`;
    }).join('\n');
    (doc.head ?? doc.documentElement).append(state.style);
    if (result.errors.length) onStatus('invalid');
    else if (limited || result.limited) onStatus('limited');
  } catch (_) {
    if (states.get(doc) === state) onStatus('error');
  } finally {
    worker?.terminate();
    if (url) URL.revokeObjectURL(url);
  }
}
