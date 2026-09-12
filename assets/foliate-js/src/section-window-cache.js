// Keep chapter URLs (and their loader-owned CSS/images/fonts) alive around the
// visible section. No hidden iframe: prefetch must not execute book scripts,
// start translation, emit reading events or mutate the visible selection.
export class SectionWindowCache {
  #sections
  #entries = new Map()
  #queue = []
  #running = false
  #closed = false
  #current = -1
  #timer = null
  #schedule
  #cancel
  #maxPrefetchSize
  constructor(sections, {
    schedule = callback => setTimeout(callback, 150),
    cancel = timer => clearTimeout(timer),
    maxPrefetchSize = 2 * 1024 * 1024,
  } = {}) {
    this.#sections = sections
    this.#schedule = schedule
    this.#cancel = cancel
    this.#maxPrefetchSize = maxPrefetchSize
  }
  get indices() { return [...this.#entries.keys()] }
  #stopTimer() {
    if (this.#timer !== null) this.#cancel(this.#timer)
    this.#timer = null
  }
  #discard(entry) {
    if (entry.discarded) return
    entry.discarded = true
    if (this.#entries.get(entry.index) === entry) this.#entries.delete(entry.index)
    if (entry.state === 'ready') this.#sections[entry.index].unload?.()
    else if (entry.state === 'queued') {
      this.#queue = this.#queue.filter(value => value !== entry)
      entry.reject(new Error('Chapter preload cancelled'))
    }
    // An active load owns one loader reference. Release it after completion,
    // never while an iframe or another load might still use its blob URLs.
  }
  load(index, { background = false } = {}) {
    if (this.#closed) return Promise.reject(new Error('Chapter cache closed'))
    if (!this.#sections[index]?.load) return Promise.reject(new Error('Invalid section'))
    if (!background) {
      this.#stopTimer()
      for (const entry of this.#entries.values()) {
        if (entry.state === 'queued' && entry.index !== index && entry.index !== this.#current)
          this.#discard(entry)
      }
    }
    const existing = this.#entries.get(index)
    if (existing) {
      if (!background && existing.state === 'queued') {
        this.#queue = [existing, ...this.#queue.filter(value => value !== existing)]
      }
      return existing.promise
    }
    while (this.#entries.size >= 3) {
      const candidate = [...this.#entries.values()].find(entry => entry.index !== this.#current)
      if (!candidate) break
      this.#discard(candidate)
    }
    const entry = { index, state: 'queued', discarded: false }
    entry.promise = new Promise((resolve, reject) => Object.assign(entry, { resolve, reject }))
    this.#entries.set(index, entry)
    if (background) this.#queue.push(entry)
    else this.#queue.unshift(entry)
    this.#pump()
    return entry.promise
  }
  async #pump() {
    if (this.#running || this.#closed) return
    const entry = this.#queue.shift()
    if (!entry) return
    this.#running = true
    entry.state = 'loading'
    try {
      const src = await this.#sections[entry.index].load()
      if (typeof src !== 'string' || !src) throw new Error('Empty chapter URL')
      if (entry.discarded) {
        this.#sections[entry.index].unload?.()
        entry.reject(new Error('Chapter preload cancelled'))
      } else {
        entry.state = 'ready'
        entry.resolve(src)
      }
    } catch (error) {
      if (this.#entries.get(entry.index) === entry) this.#entries.delete(entry.index)
      entry.reject(error)
    } finally {
      this.#running = false
      this.#pump()
    }
  }
  #adjacent(index, direction) {
    for (let i = index + direction; i >= 0 && i < this.#sections.length; i += direction) {
      const section = this.#sections[i]
      if (section?.linear !== 'no' && section?.load) return i
    }
    return undefined
  }
  setCurrent(index) {
    if (this.#closed) return
    this.#current = index
    this.#stopTimer()
    const adjacent = [this.#adjacent(index, 1), this.#adjacent(index, -1)]
      .filter(i => i != null && !(this.#sections[i].size > this.#maxPrefetchSize))
    const keep = new Set([index, ...adjacent])
    for (const entry of this.#entries.values()) {
      if (!keep.has(entry.index)) this.#discard(entry)
    }
    this.#timer = this.#schedule(() => {
      this.#timer = null
      if (this.#closed) return
      // Serialize loader calls so shared CSS/font reference counts cannot race.
      for (const i of adjacent) this.load(i, { background: true }).catch(() => {})
    })
  }
  destroy() {
    this.#closed = true
    this.#stopTimer()
    for (const entry of this.#entries.values()) this.#discard(entry)
  }
}
