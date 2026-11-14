export const autoScrollPixelsPerSecond = (samples, fallback = 10) => {
  let height = 0, seconds = 0
  for (const sample of samples) {
    if (!Number.isFinite(sample.height) || sample.height <= 0) continue
    const text = sample.text ?? ''
    const cjk = text.match(/[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]/g)?.length ?? 0
    const words = text.replace(/[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]/g, ' ')
      .match(/[A-Za-z\u00c0-\u024f0-9]+(?:['’\-][A-Za-z\u00c0-\u024f0-9]+)*/g)?.length ?? 0
    height += sample.height
    seconds += cjk / 5 + words * .3
  }
  // Sparse/image-only viewports use the last measured pace instead of racing.
  return seconds >= 4 && height > 0 ? Math.max(.5, Math.min(200, height / seconds)) : fallback
}

export class ReaderAutoScroll {
  running = false
  generation = 0
  documents = new WeakSet()
  constructor({ renderer, canRun = () => true, onStop = () => {}, host = window }) {
    Object.assign(this, { renderer, canRun, onStop, host })
    this.attach(host.document)
    host.document.addEventListener('visibilitychange', () => {
      if (host.document.visibilityState === 'hidden') this.stop('inactive')
    })
    host.addEventListener('pagehide', () => this.stop('inactive'))
  }
  attach(doc) {
    if (!doc || this.documents.has(doc)) return
    this.documents.add(doc)
    let pointer, touch
    const point = event => ({ x: event.clientX, y: event.clientY })
    const dragged = (start, current) => start &&
      Math.hypot(current.clientX - start.x, current.clientY - start.y) > 8
    const opts = { capture: true, passive: true }
    doc.addEventListener('pointerdown', event => {
      pointer = event.button === 0 ? { ...point(event), id: event.pointerId } : null
    }, opts)
    doc.addEventListener('pointermove', event => {
      if (event.pointerId === pointer?.id && dragged(pointer, event)) this.stop('input')
    }, opts)
    for (const type of ['pointerup', 'pointercancel']) doc.addEventListener(type, () => { pointer = null }, opts)
    doc.addEventListener('touchstart', event => {
      touch = event.touches.length === 1 ? point(event.touches[0]) : null
      if (event.touches.length > 1) this.stop('input')
    }, opts)
    doc.addEventListener('touchmove', event => {
      if (touch && event.touches[0] && dragged(touch, event.touches[0])) this.stop('input')
    }, opts)
    for (const type of ['touchend', 'touchcancel']) doc.addEventListener(type, () => { touch = null }, opts)
    for (const type of ['wheel', 'keydown'])
      doc.addEventListener(type, () => this.stop('input'), { capture: true, passive: true })
    doc.addEventListener('selectionchange', () => {
      if (doc.getSelection()?.toString()) this.stop('selection')
    })
  }
  available(renderer) {
    return renderer?.autoScrollSupported === true && renderer.readerActive !== false &&
      !renderer.isNavigating && this.canRun() &&
      this.host.document.visibilityState !== 'hidden' &&
      !(renderer.getContents?.() ?? []).some(({ doc }) => doc.getSelection()?.toString())
  }
  refresh() { this.lastEstimate = null }
  set({ enabled, speed = 1, session } = {}) {
    if (enabled !== true) { this.stop('manual'); return false }
    const renderer = this.renderer()
    if (!this.available(renderer)) { this.stop('unsupported'); return false }
    this.speed = Math.max(.1, Math.min(4, Number.isFinite(speed) ? speed : 1))
    if (this.running && this.currentRenderer === renderer) return true
    this.stop('renderer')
    this.running = true
    this.session = session
    this.currentRenderer = renderer
    this.lastTime = null
    this.distance = 0
    this.lastFlush = null
    this.lastEstimate = null
    this.pixelsPerSecond = 10
    renderer.setAutoScrolling?.(true)
    for (const { doc } of renderer.getContents?.() ?? []) this.attach(doc)
    const generation = ++this.generation
    const active = () => this.running && this.generation === generation &&
      this.renderer() === renderer && this.available(renderer)
    const schedule = () => { this.frame = this.host.requestAnimationFrame(tick) }
    const tick = async time => {
      this.frame = null
      if (!active()) { if (this.generation === generation) this.stop('inactive'); return }
      const elapsed = this.lastTime == null ? 0 : Math.min(100, Math.max(0, time - this.lastTime))
      this.lastTime = time
      this.lastFlush ??= time
      if (this.lastEstimate == null || time - this.lastEstimate >= 1000) {
        try {
          const estimate = renderer.getAutoScrollSpeed?.(this.pixelsPerSecond)
          if (Number.isFinite(estimate) && estimate > 0) this.pixelsPerSecond = estimate
        } catch { /* Keep the last pace while fonts or images change layout. */ }
        this.lastEstimate = time
      }
      // Accumulate whole pixels: older WebViews round a fractional scrollTop.
      this.distance += this.speed * this.pixelsPerSecond * elapsed / 1000
      const distance = Math.floor(this.distance)
      if (distance) {
        this.distance -= distance
        try {
          const result = await renderer.autoScrollBy(distance, active)
          if (!active()) { if (this.generation === generation) this.stop('inactive'); return }
          if (result !== 'moved') { this.stop(result === 'end' ? 'end' : 'inactive'); return }
          if (time - this.lastFlush >= 500) {
            renderer.flushAutoScrollPosition?.()
            this.lastFlush = time
          }
        } catch {
          if (this.generation === generation) this.stop('error')
          return
        }
      }
      if (active()) schedule()
    }
    schedule()
    return true
  }
  stop(reason = 'manual') {
    if (!this.running) return
    this.running = false
    this.generation++
    if (this.frame != null) this.host.cancelAnimationFrame(this.frame)
    this.frame = null
    const renderer = this.currentRenderer
    this.currentRenderer = null
    try { renderer.flushAutoScrollPosition?.() }
    finally {
      renderer.setAutoScrolling?.(false)
      this.onStop(reason, this.session)
    }
  }
}
