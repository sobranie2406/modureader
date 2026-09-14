// A bounded, live DOM window for horizontal reflowable books. Resource loading
// is serialized; inserting an iframe by changing CSS order must not move/reload
// existing iframe nodes. Preparing a chapter is deliberately not activation.
export class ContinuousSectionWindow {
  entries = new Map()
  current = null
  pinned = null
  closed = false
  busy = false
  timer = null
  warming = false
  tail = Promise.resolve()
  anchor = null
  constructor({ container, sections, create, activate, changed,
    maxViews = 9, maxBytes = 8 * 1024 * 1024 }) {
    Object.assign(this, { container, sections, create, activate, changed, maxViews, maxBytes })
    container.style.display = 'flex'
    container.style.flexDirection = 'column'
    container.style.overflowAnchor = 'none'
    this.tailSpace = container.ownerDocument.createElement('div')
    Object.assign(this.tailSpace.style, { order: '2147483647', flex: '0 0 auto',
      height: `${container.clientHeight}px`, pointerEvents: 'none' })
    container.append(this.tailSpace)
  }
  adjacent(index, direction) {
    for (let i = index + direction; i >= 0 && i < this.sections.length; i += direction)
      if (this.sections[i]?.load && this.sections[i].linear !== 'no') return i
  }
  get ordered() { return [...this.entries.values()].filter(e => e.ready && !e.detached).sort((a, b) => a.index - b.index) }
  top(entry) {
    return entry.view.element.getBoundingClientRect().top -
      this.container.getBoundingClientRect().top + this.container.scrollTop
  }
  get height() { return this.container.clientHeight }
  remember() {
    this.anchor = this.current?.ready ? { entry: this.current,
      y: this.top(this.current) - this.container.scrollTop, scroll: this.container.scrollTop } : null
  }
  compensate(snapshot = this.anchor) {
    if (!snapshot || !this.entries.has(snapshot.entry.index)) return
    this.container.scrollTop = this.top(snapshot.entry) - snapshot.y
    this.remember()
  }
  drop(entry) {
    entry.view.destroy()
    entry.view.element.remove()
    this.entries.delete(entry.index)
    this.sections[entry.index].unload?.()
  }
  makeRoom(index, foreground) {
    const bytes = () => [...this.entries.values()].reduce((n, e) => n + (this.sections[e.index].size || 0), 0)
    while (this.entries.size >= this.maxViews || (this.entries.size > 0 &&
      bytes() + (this.sections[index].size || 0) > this.maxBytes)) {
      const list = this.ordered
      const candidates = [...this.entries.values()].filter(e => e !== this.current && e.index !== this.pinned &&
        (e.detached || e === list[0] || e === list.at(-1)) &&
        (foreground || e.detached || (index > list.at(-1)?.index ? e === list[0] : e === list.at(-1))) &&
        (foreground || e.detached || Math.abs(e.index - this.current.index) > Math.abs(index - this.current.index)) &&
        !e.view.document.getSelection()?.toString() && (foreground ||
          this.top(e) + e.view.element.getBoundingClientRect().height < this.container.scrollTop ||
          this.top(e) > this.container.scrollTop + this.height))
      candidates.sort((a, b) => Math.abs(b.index - index) - Math.abs(a.index - index))
      if (!candidates.length) return foreground
      this.remember()
      this.drop(candidates[0])
      this.compensate()
    }
    return true
  }
  ensure(index, foreground = false) {
    const operation = async () => {
      if (this.closed) return
      if (this.entries.has(index)) return this.entries.get(index)
      if (!this.sections[index]?.load || !this.makeRoom(index, foreground)) return
      if (!foreground && this.sections[index].size > 2 * 1024 * 1024) return
      const src = await this.sections[index].load()
      let view
      try {
        if (this.closed) return
        view = await this.create(index, src)
        if (this.closed) { view.destroy(); view.element.remove(); return }
        this.remember()
        const entry = { index, src, view, ready: true, activated: false }
        this.entries.set(index, entry)
        Object.assign(view.element.style, { position: 'relative', order: String(index),
          visibility: '', pointerEvents: '', left: '', top: '', contentVisibility: 'visible' })
        this.compensate()
        this.updateTail()
        if (!this.busy) this.changed?.()
        return entry
      } finally {
        if (!view || this.closed) this.sections[index].unload?.()
      }
    }
    const result = this.tail.then(operation)
    this.tail = result.catch(() => {})
    return result
  }
  select(entry) {
    if (!entry || this.current === entry) return
    if (entry.detached) {
      entry.detached = false
      entry.view.element.style.display = 'flex'
      this.trimTo(entry.index)
    }
    this.current = entry
    this.activate(entry)
    entry.activated = true
    this.remember()
  }
  track() {
    if (this.closed || this.busy) return
    const position = this.container.scrollTop + 1
    const entry = this.ordered.find(e => this.top(e) + e.view.element.getBoundingClientRect().height > position)
    this.select(entry)
    // Initialize only documents actually visible, not speculative neighbors.
    // Restore the primary chapter after wiring a visible trailing document.
    for (const e of this.ordered) if (!e.activated && this.top(e) < position + this.height &&
      this.top(e) + e.view.element.getBoundingClientRect().height > position) {
      this.activate(e)
      e.activated = true
      if (this.current) this.activate(this.current)
    }
    this.remember()
    this.warm()
  }
  warm() {
    if (this.timer != null || this.warming || this.closed || !this.current) return
    this.timer = setTimeout(async () => {
      this.timer = null
      if (this.closed || this.busy) return
      this.warming = true
      try {
      // Warm in both directions to a viewport beyond the visible region. A
      // short-chapter book may require more than the adjacent two documents.
      for (let n = 0; n < this.maxViews && !this.closed && !this.busy; n++) {
        const list = this.ordered
        if (!list.length) return
        const first = list[0], last = list.at(-1)
        const bottom = this.top(last) + last.view.element.getBoundingClientRect().height
        const next = bottom < this.container.scrollTop + this.height * 2
          ? this.adjacent(last.index, 1) : undefined
        const prev = this.top(first) > this.container.scrollTop - this.height
          ? this.adjacent(first.index, -1) : undefined
        let added = false
        for (const index of [next, prev]) {
          if (index == null || this.closed || this.busy) continue
          try { added = !!await this.ensure(index) || added }
          catch { /* A speculative failure is retried by explicit navigation. */ }
        }
        if (!added) break
      }
      } finally { this.warming = false }
    }, 100)
  }
  resize() {
    if (this.closed || this.busy) return
    if (this.anchor && Math.abs(this.container.scrollTop - this.anchor.scroll) > 1) {
      this.track()
      return
    }
    this.compensate()
    this.warm()
  }
  updateTail() {
    const last = this.ordered.at(-1)
    // A temporary loading tail allows short chapters to be prepended without
    // browser scroll clamping. It disappears when the next viewport is ready.
    const end = last ? this.top(last) + last.view.element.getBoundingClientRect().height : 0
    const needed = !last || this.adjacent(last.index, 1) != null
      ? Math.max(0, this.container.scrollTop + this.height * 1.5 - end) : 0
    this.tailSpace.style.height = `${Math.min(this.height, needed)}px`
  }
  async goTo(index, anchor, select, scroll) {
    this.busy = true
    try {
      const entry = await this.ensure(index, true)
      if (!entry || this.closed) return
      this.trimTo(index)
      this.select(entry)
      await scroll(typeof anchor === 'function' ? anchor(entry.view.document) : anchor ?? 0, select)
      this.remember()
    } finally { this.busy = false; this.warm() }
  }
  trimTo(index) {
    // Keep an off-screen speaking document alive, but not in the visible flow
    // after an unrelated TOC jump. Restoring it never reloads its iframe.
    const keep = new Set([index])
    for (const dir of [-1, 1]) {
      let i = this.adjacent(index, dir)
      while (this.entries.has(i) && !this.entries.get(i).detached) {
        keep.add(i); i = this.adjacent(i, dir)
      }
    }
    for (const e of this.ordered) if (!keep.has(e.index)) {
      if (e.index === this.pinned) {
        e.detached = true; e.view.element.style.display = 'none'
      } else this.drop(e)
    }
  }
  destroy() {
    this.closed = true
    clearTimeout(this.timer)
    for (const entry of [...this.entries.values()]) this.drop(entry)
    this.current = null
    this.tailSpace.remove()
    this.container.style.display = ''
    this.container.style.flexDirection = ''
    this.container.style.overflowAnchor = ''
  }
}
