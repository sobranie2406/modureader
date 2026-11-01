const states = new WeakMap()
const blocks = 'p,li,blockquote,pre,td,th,h1,h2,h3,h4,h5,h6,div,section,article'
export function applyTextFilters(doc, rules = []) {
  const signature = JSON.stringify(rules)
  const previous = states.get(doc)
  if (previous?.signature === signature) return false
  for (const {node, runs} of previous?.replaced ?? []) {
    runs[0]?.replaceWith(node)
    for (const run of runs.slice(1)) run.remove()
  }
  for (const [el, value, priority] of previous?.hidden ?? []) {
    if (value) el.style.setProperty('display', value, priority)
    else el.style.removeProperty('display')
  }
  const state = {signature, replaced: [], hidden: []}
  states.set(doc, state)
  if (!rules.length || !doc.body) return !!previous
  const groups = new Map(), walker = doc.createTreeWalker(doc.body, 4)
  let node
  while ((node = walker.nextNode())) {
    if (node.parentElement?.closest('script,style,textarea,svg,math,rt,rp')) continue
    const owner = node.parentElement?.closest(blocks) ?? doc.body
    const group = groups.get(owner) ?? {text:'', nodes:[]}
    group.nodes.push({node, start:group.text.length})
    group.text += node.data
    groups.set(owner, group)
  }
  for (const [owner, group] of groups) {
    const title = !!owner.closest('h1,h2,h3,h4,h5,h6')
    const ranges = []
    let hide = false
    for (const rule of rules) {
      if (rule.scope === 'title' && !title || rule.scope === 'body' && title) continue
      for (const word of String(rule.pattern ?? '').slice(0,512).split(/\r?\n/).map(s=>s.trim()).filter(Boolean)) {
        let at = 0
        while ((at = group.text.indexOf(word, at)) >= 0) {
          if (rule.filterMode === 'paragraph') hide = true
          ranges.push([at, at + word.length]); at += word.length
        }
      }
    }
    if (hide) {
      state.hidden.push([owner, owner.style.getPropertyValue('display'), owner.style.getPropertyPriority('display')])
      owner.style.setProperty('display','none','important')
      continue
    }
    for (const {node, start} of group.nodes) {
      const matches = ranges.map(([a,b])=>[Math.max(0,a-start), Math.min(node.length,b-start)]).filter(([a,b])=>a<b)
      if (!matches.length) continue
      const edges = [...new Set([0,node.length,...matches.flat()])].sort((a,b)=>a-b)
      const runs = [], fragment = doc.createDocumentFragment()
      for (let i=0;i<edges.length-1;i++) {
        const text = doc.createTextNode(node.data.slice(edges[i], edges[i+1]))
        const run = doc.createElementNS('http://www.w3.org/1999/xhtml', 'span'); run.__moduTextFilter = true
        run.setAttribute('data-modu-text-filter',''); run.append(text)
        if (matches.some(([a,b])=>a<=edges[i]&&b>edges[i])) {
          run.style.setProperty('display','none','important')
        }
        runs.push(run);fragment.append(run)
      }
      node.replaceWith(fragment);state.replaced.push({node,runs})
    }
  }
  return true
}
