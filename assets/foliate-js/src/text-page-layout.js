// Stable inline runs let each page distribute its own spare vertical space.
// They are transparent to EPUB CFIs and are never recreated on a page turn.
const documents = new WeakMap()
const scrollLines = new WeakMap()
const spacingStyles = new WeakMap()
const excluded = 'script, style, template, table, pre, ruby, math, svg, figure, [data-modu-text-filter]'
const noteSelector = 'sup, sub, [role="doc-noteref"], [epub\\:type~="noteref"], img[zy-footnote], img.epub-footnote, img.epub-footnote1'
const isNote = el => el.closest(noteSelector)
const runStyle = 'display:inline!important;position:relative!important;top:0px!important;padding:0!important;margin:0!important;border:0!important;font:inherit!important;'

// Moving glyphs independently separates publisher decorations from their text.
function publisherBlocks(doc) {
  const blocks = new Set(doc.body.querySelectorAll('h1, h2, h3, h4, h5, h6'))
  for (const el of doc.body.querySelectorAll(':not(modu-page-run)')) {
    if (el.closest(excluded) || isNote(el)) continue
    const style = doc.defaultView.getComputedStyle(el)
    const bordered = ['Top', 'Right', 'Bottom', 'Left'].some(side =>
      parseFloat(style[`border${side}Width`]) > 0 &&
      !['none', 'hidden', ''].includes(style[`border${side}Style`]))
    if (!bordered && (!style.cssFloat || style.cssFloat === 'none') &&
      !['absolute', 'fixed'].includes(style.position)) continue
    // Include the containing paragraph/title, not just its floating number.
    let block = el
    while (block !== doc.body && !block.matches('h1, h2, h3, h4, h5, h6, p, li, blockquote, dd, div'))
      block = block.parentElement
    blocks.add(block)
  }
  return blocks
}

function insidePublisherBlock(el, blocks) {
  for (; el; el = el.parentElement) if (blocks.has(el)) return true
  return false
}

export function preparePageRuns(doc) {
  if (documents.has(doc)) return documents.get(doc)
  // ponytail: bound chapter preparation on mobile; complex publisher layouts keep native spacing.
  if (!doc.body || doc.body.textContent.length > 50000 || !globalThis.Intl?.Segmenter) return null
  const protectedBlocks = publisherBlocks(doc)
  const walker = doc.createTreeWalker(doc.body, 4), nodes = []
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (!node.textContent.trim() || node.parentElement.closest(excluded) || isNote(node.parentElement)) continue
    if (insidePublisherBlock(node.parentElement, protectedBlocks)) continue
    nodes.push(node)
  }
  const graphemes = new Intl.Segmenter(undefined, { granularity: 'grapheme' })
  const words = new Intl.Segmenter(undefined, { granularity: 'word' })
  const runs = []
  const template = doc.createElementNS('http://www.w3.org/1999/xhtml', 'modu-page-run')
  template.setAttribute('style', runStyle)
  for (const node of nodes) {
    const fragment = doc.createDocumentFragment()
    // Keep joined scripts/Latin words intact; CJK can break between graphemes.
    for (const word of words.segment(node.data)) {
      const segments = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u.test(word.segment)
        ? graphemes.segment(word.segment) : [word]
      for (const { segment } of segments) {
        const run = template.cloneNode(false)
        run.__moduPageRun = true
        run.textContent = segment
        fragment.append(run)
        runs.push(run)
      }
    }
    node.replaceWith(fragment)
  }
  // Move atomic note markers with their text line without changing their font/baseline.
  const notes = [...doc.body.querySelectorAll(noteSelector)].filter(el =>
    !el.parentElement.closest(noteSelector) && !insidePublisherBlock(el, protectedBlocks))
  const noteStyles = notes.map(el => [el, ['position', 'top'].map(name =>
    [name, el.style.getPropertyValue(name), el.style.getPropertyPriority(name)])])
  const state = { runs, notes, noteStyles, protectedBlocks }
  documents.set(doc, state)
  return state
}

export function resetPageAlignment(doc) {
  invalidateScrollLines(doc)
  for (const [el, value, priority] of spacingStyles.get(doc) ?? []) {
    if (value) el.style.setProperty('line-height', value, priority)
    else el.style.removeProperty('line-height')
  }
  spacingStyles.delete(doc)
  const state = documents.get(doc)
  if (!state) return
  for (const run of state.runs)
    if (run.style.top !== '0px' || run.style.getPropertyPriority('top') !== 'important')
      run.style.setProperty('top', '0px', 'important')
  for (const [el, styles] of state.noteStyles)
    for (const [name, value, priority] of styles) {
      if (value) el.style.setProperty(name, value, priority)
      else el.style.removeProperty(name)
    }
}

export function fittedLineHeight(requested, glyphHeight, viewport) {
  const minimum = glyphHeight + 2
  const natural = Math.max(requested || minimum, minimum)
  if (!(viewport > glyphHeight)) return natural
  const available = viewport - glyphHeight - 1
  const intervals = Math.min(Math.round(available / natural), Math.floor(available / minimum))
  if (intervals < 3) return natural
  const fitted = available / intervals
  return Math.abs(fitted - natural) <= Math.min(8, natural * .2) ? fitted : natural
}

// Generated adjacent runs can share one range without changing font/line coverage.
function selectTextRuns(range, node, walker) {
  let last = node.parentElement
  if (last.__moduPageRun && last.childNodes.length === 1) {
    // Reader-owned runs share inline typography; measure their full range once.
    while (last.nextSibling?.__moduPageRun && last.nextSibling.childNodes.length === 1 &&
      last.nextSibling.firstChild.nodeType === 3) last = last.nextSibling
    range.setStartBefore(node.parentElement)
    range.setEndAfter(last)
    walker.currentNode = last.lastChild
  } else range.selectNodeContents(node)
}

// Measure the actual font after it loads, before the chapter becomes visible.
// CSS line-height may be smaller than the font's range boxes (even zero).
export function fitTextLineSpacing(doc, viewport = 0) {
  if (!doc?.body || doc.defaultView.getComputedStyle(doc.documentElement)
    .getPropertyValue('--modu-align-pages').trim() !== '1') return
  const protectedBlocks = publisherBlocks(doc)
  const blocks = new Map(), styles = new Map(), range = doc.createRange()
  const styleOf = el => {
    if (!styles.has(el)) styles.set(el, doc.defaultView.getComputedStyle(el))
    return styles.get(el)
  }
  const walker = doc.createTreeWalker(doc.body, 4)
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (!node.textContent.trim() || node.parentElement.closest(excluded) || isNote(node.parentElement)) continue
    if (insidePublisherBlock(node.parentElement, protectedBlocks)) continue
    let block = node.parentElement
    while (block !== doc.body && (block.__moduPageRun || styleOf(block).display === 'inline')) block = block.parentElement
    if (!['block', 'list-item'].includes(styleOf(block).display)) continue
    selectTextRuns(range, node, walker)
    let height = 0
    for (const rect of range.getClientRects())
      if (rect.width > 0 && rect.height > 0) height = Math.max(height, rect.height)
    if (!height) continue
    const item = blocks.get(block) ?? { height: 0, requested: parseFloat(styleOf(block).lineHeight) }
    item.height = Math.max(item.height, height)
    blocks.set(block, item)
  }
  const originals = []
  for (const [el, { height, requested }] of blocks) {
    const fitted = fittedLineHeight(requested, height, viewport)
    if (Number.isFinite(requested) && Math.abs(fitted - requested) < .01) continue
    originals.push([el, el.style.getPropertyValue('line-height'), el.style.getPropertyPriority('line-height')])
    el.style.setProperty('line-height', `${fitted}px`, 'important')
  }
  spacingStyles.set(doc, originals)
}

export function pageLineOffsets(rows, top, bottom, last) {
  if (!rows.length) return []
  const start = top - rows[0].top
  if (last) return rows.map(() => start)
  if (rows.length < 2) return null
  const extra = bottom - rows.at(-1).bottom - start
  const step = extra / (rows.length - 1)
  // Like Legado's page-finalization step, distribute spare height between
  // already-measured lines. The caller excludes explicit breaks/media rather
  // than guessing whether a browser column is full from paragraph margins.
  if (rows.some((row, i) => i && row.top - rows[i - 1].bottom + step < 1)) return null
  return rows.map((_, i) => start + step * i)
}

export function alignPaginatedText(doc, { height, topMargin, bottomMargin, columnWidth, gap }, vertical, timing, measureExtent) {
  if (vertical || doc.defaultView.getComputedStyle(doc.documentElement)
    .getPropertyValue('--modu-align-pages').trim() !== '1' ||
    !(height > topMargin + bottomMargin && columnWidth > 0)) return
  const preparing = Date.now()
  const state = preparePageRuns(doc)
  timing?.('layout_runs', preparing)
  if (!state) return
  const measuring = Date.now()
  const stride = columnWidth + gap
  const pageOf = r => Math.max(0, Math.floor((r.left - gap / 2 + 1) / stride))
  const pages = new Map()
  const pageAt = index => {
    if (!pages.has(index)) pages.set(index, { runs: [], notes: [], unsafe: false, headingBottom: null })
    return pages.get(index)
  }
  // Read all geometry before writing offsets: no repeated forced layouts.
  for (const el of state.runs) {
    if (!el.textContent.trim()) continue
    const rects = [...el.getClientRects()].filter(r => r.width > 0 && r.height > 0)
    for (const r of rects) {
      const page = pageAt(pageOf(r))
      if (rects.length !== 1) page.unsafe = true
      else page.runs.push({ el, r })
    }
  }
  // Recheck styles after resize/settings changes; retain originally unwrapped blocks.
  const protectedBlocks = new Set([...state.protectedBlocks, ...publisherBlocks(doc)])
  // Translations added after run preparation must flow with their source, not
  // collide with independently shifted source glyphs. Hidden translations have no rects.
  for (const el of [...doc.body.querySelectorAll('img, svg, table, pre, ruby, math, video, figure, .translated-text'), ...protectedBlocks]) {
    if (isNote(el)) continue
    const rects = [...el.getClientRects()].filter(r => r.width > 0 && r.height > 0)
    for (const r of rects) {
      const index = pageOf(r), page = pageAt(index)
      // Keep opening titles intact without disabling alignment of the prose below.
      if (index === 0 && rects.length === 1 && el.matches('h1,h2,h3,h4,h5,h6'))
        page.headingBottom = Math.max(page.headingBottom ?? -Infinity, r.bottom)
      else page.unsafe = true
    }
  }
  for (const el of state.notes) {
    const r = el.getBoundingClientRect()
    if (r.width > 0 && r.height > 0) pageAt(pageOf(r)).notes.push({ el, r,
      oldTop: parseFloat(doc.defaultView.getComputedStyle(el).top) || 0 })
  }
  const last = Math.max(...pages.keys())
  const forced = new Set()
  const forcedBreak = value => /^(always|page|column|left|right|recto|verso)$/.test(value)
  const transformed = style => (style.transform && style.transform !== 'none') ||
    (style.rotate && style.rotate !== 'none')
  let stableExtent = !transformed(doc.defaultView.getComputedStyle(doc.documentElement)) &&
    !transformed(doc.defaultView.getComputedStyle(doc.body))
  // Do not stretch a dedication/heading page before a publisher-forced break.
  for (const el of doc.body.querySelectorAll(':not(modu-page-run)')) {
    const style = doc.defaultView.getComputedStyle(el)
    if (transformed(style)) stableExtent = false
    if (style.display === 'inline' || style.display === 'none') continue
    const before = forcedBreak(style.breakBefore) || forcedBreak(style.pageBreakBefore)
    const after = forcedBreak(style.breakAfter) || forcedBreak(style.pageBreakAfter)
    if (!before && !after) continue
    const rects = [...el.getClientRects()].filter(r => r.width > 0)
    if (!rects.length) continue
    if (before) forced.add(pageOf(rects[0]) - 1)
    if (after) forced.add(pageOf(rects.at(-1)))
  }
  // Vertical offsets do not change horizontal page extent; measure before writes
  // so expansion can commit offsets and iframe size in the same layout pass.
  const extent = stableExtent ? measureExtent?.() : undefined
  timing?.('layout_geometry', measuring)
  const applying = Date.now()
  for (const [index, page] of pages) {
    if (page.unsafe || forced.has(index) || !page.runs.length) continue
    const rows = []
    for (const item of page.runs.sort((a, b) => a.r.top - b.r.top)) {
      let row = rows.at(-1)
      if (!row || item.r.top >= row.bottom - 2)
        rows.push(row = { top: item.r.top, bottom: item.r.bottom, runs: [] })
      row.bottom = Math.max(row.bottom, item.r.bottom)
      row.runs.push(item)
    }
    if (page.headingBottom !== null && page.headingBottom > rows[0].top) continue
    // Preserve the title-to-prose gap; only the remaining prose gaps may expand.
    const top = page.headingBottom === null ? topMargin : rows[0].top
    // A skipped/blank column is an explicit layout boundary, not prose overflow.
    const offsets = pageLineOffsets(rows, top, height - bottomMargin,
      index === last || !pages.has(index + 1))
    if (!offsets) continue
    for (const { el, r, oldTop } of page.notes) {
      const distances = rows.map(row => Math.abs((row.top + row.bottom) / 2 - (r.top + r.bottom) / 2))
      const nearest = distances.indexOf(Math.min(...distances))
      el.style.setProperty('position', 'relative', 'important')
      el.style.setProperty('top', `${oldTop + offsets[nearest]}px`, 'important')
    }
    rows.forEach((row, i) => row.runs.forEach(({ el }) => {
      const top = `${offsets[i]}px`
      if (el.style.top !== top || el.style.getPropertyPriority('top') !== 'important')
        el.style.setProperty('top', top, 'important')
    }))
  }
  timing?.('layout_offsets', applying)
  return extent
}

const interLineStops = (edges, target, min, max, shifts) => {
  let intervals = [[min, max]]
  for (const { top, bottom } of edges) for (const shift of shifts) {
    const a = top - shift - .5, b = bottom - shift + .5
    intervals = intervals.flatMap(([lo, hi]) => b <= lo || a >= hi ? [[lo, hi]]
      : [...(a >= lo ? [[lo, a]] : []), ...(b <= hi ? [[b, hi]] : [])])
  }
  return intervals.map(([lo, hi]) => Math.max(lo, Math.min(hi, target)))
}
const closestStop = (candidates, target) => candidates.length
  ? candidates.reduce((a, b) => Math.abs(a - target) < Math.abs(b - target) ? a : b) : target

// Select an inter-line stop before scrolling, keeping overlap at 100% steps.
export function safeScrollOffset(edges, target, current, viewport) {
  if (!edges.length || !Number.isFinite(target) || target === current) return target
  const forward = target > current
  const glyph = Math.max(0, ...edges.map(row => row.bottom - row.top))
  // A short viewport's percentage window may be narrower than one large glyph.
  const limit = Math.max(Math.min(120, viewport * .15), glyph < viewport ? glyph + 1 : 0)
  const min = forward ? Math.max(current + 1, target - limit) : target
  const max = forward ? target : Math.min(current - 1, target + limit)
  if (min > max) return target
  const both = interLineStops(edges, target, min, max, [0, viewport])
  // ponytail: simultaneous gaps can be impossible at fixed height. Prioritize the
  // leading edge in the reading direction, without masking text or changing layout.
  return closestStop(both.length ? both : interLineStops(edges, target, min, max,
    [forward ? viewport : 0]), target)
}

export function settledScrollOffset(edges, target, previous, viewport) {
  if (!edges.length || !Number.isFinite(target) || target === previous) return target
  const glyph = Math.max(0, ...edges.map(row => row.bottom - row.top))
  const limit = Math.max(Math.min(48, viewport * .08), glyph < viewport ? glyph / 2 + 1 : 0)
  const min = Math.max(0, target - limit), max = target + limit
  const both = interLineStops(edges, target, min, max, [0, viewport])
  return closestStop(both.length ? both : interLineStops(edges, target, min, max,
    [target > previous ? viewport : 0]), target)
}

export function invalidateScrollLines(doc) {
  const state = scrollLines.get(doc)
  if (state) state.dirty = true
}

// Cache document-local geometry, not absolute offsets: adjacent chapters can move.
export function prepareScrollLines(doc) {
  if (!doc?.body) return []
  let state = scrollLines.get(doc)
  if (!state) {
    state = { dirty: true, edges: [] }
    const Observer = doc.defaultView?.MutationObserver
    if (Observer) {
      state.observer = new Observer(() => { state.dirty = true })
      state.observer.observe(doc.body, { subtree: true, childList: true,
        characterData: true, attributes: true, attributeFilter: ['style', 'class', 'hidden', 'dir'] })
    }
    scrollLines.set(doc, state)
  }
  if (state.observer?.takeRecords().length) state.dirty = true
  if (!state.dirty) return state.edges
  const edges = new Map()
  if (doc.body.textContent.length <= 300000) {
    const range = doc.createRange()
    const walker = doc.createTreeWalker(doc.body, 4)
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (!node.textContent.trim() || node.parentElement.closest('script, style')) continue
      selectTextRuns(range, node, walker)
      for (const rect of range.getClientRects()) {
        if (rect.height > 0 && rect.width > 0)
          edges.set(rect.top, Math.max(edges.get(rect.top) ?? -Infinity, rect.bottom))
      }
    }
  }
  // Inline runs share line boxes; retain their union instead of per-glyph rects.
  const merged = []
  for (const edge of Array.from(edges, ([top, bottom]) => ({top, bottom})).sort((a, b) => a.top - b.top)) {
    const last = merged.at(-1)
    // Overlapping font boxes on adjacent lines are not one paragraph-sized row.
    if (last && (edge.bottom <= last.bottom || Math.abs(edge.top - last.top) < .5))
      last.bottom = Math.max(last.bottom, edge.bottom)
    else merged.push(edge)
  }
  state.edges = merged
  state.dirty = false
  return merged
}

export function lineAlignedOffset(documents, target, current, viewport, settled = false) {
  const edges = []
  for (const { doc, offset } of documents) {
    const lines = prepareScrollLines(doc)
    for (const boundary of [target - offset, target + viewport - offset]) {
      let lo = 0, hi = lines.length
      while (lo < hi) {
        const mid = (lo + hi) >>> 1
        if (lines[mid].bottom < boundary - 120) lo = mid + 1
        else hi = mid
      }
      for (let i = lo; i < lines.length && lines[i].top <= boundary + 120; i++)
        edges.push({ top: lines[i].top + offset, bottom: lines[i].bottom + offset })
    }
  }
  return (settled ? settledScrollOffset : safeScrollOffset)(edges, target, current, viewport)
}
