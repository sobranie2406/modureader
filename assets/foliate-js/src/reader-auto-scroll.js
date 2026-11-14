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
  refresh() {
    this.lastEstimate = null
    if (this.running && this.eInkMode && !this.advancing) this.scheduleEink?.()
  }
  cancelScheduled() {
    if (this.frame != null) this.host.cancelAnimationFrame(this.frame)
    if (this.timer != null) this.host.clearTimeout(this.timer)
    this.frame = this.timer = null
    this.scheduleEink = null
  }
  set({ enabled, speed = 1, session, eInkMode = false } = {}) {
    if (enabled !== true) { this.stop('manual'); return false }
    const renderer = this.renderer()
    if (!this.available(renderer)) { this.stop('unsupported'); return false }
    this.speed = Math.max(.1, Math.min(4, Number.isFinite(speed) ? speed : 1))
    if (this.running && this.currentRenderer === renderer && this.eInkMode === eInkMode) {
      if (eInkMode && !this.advancing) this.scheduleEink?.()
      return true
    }
    if (this.running && this.currentRenderer === renderer) this.cancelScheduled()
    else this.stop('renderer')
    this.running = true
    this.session = session ?? this.session
    this.eInkMode = eInkMode
    this.advancing = false
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
    const pace = time => {
      if (this.lastEstimate == null || time - this.lastEstimate >= 1000) {
        try {
          const estimate = renderer.getAutoScrollSpeed?.(this.pixelsPerSecond)
          if (Number.isFinite(estimate) && estimate > 0) this.pixelsPerSecond = estimate
        } catch { /* Keep the last pace while fonts or images change layout. */ }
        this.lastEstimate = time
      }
      return this.speed * this.pixelsPerSecond
    }
    const advance = async (distance, time) => {
      this.advancing = true
      try {
        const result = await renderer.autoScrollBy(distance, active)
        if (!active()) { if (this.generation === generation) this.stop('inactive'); return false }
        if (typeof result === 'number' && Number.isFinite(result) && result >= 0) {
          // Subpixel scrollTop may still quantize to physical pixels. Keep both
          // undershoot and overshoot instead of losing or multiplying distance.
          this.distance -= result
        } else if (result === 'moved') this.distance -= distance
        else { this.stop(result === 'end' ? 'end' : 'inactive'); return false }
        if (this.eInkMode || time - this.lastFlush >= 500) {
          renderer.flushAutoScrollPosition?.()
          this.lastFlush = time
        }
        return true
      } catch {
        if (this.generation === generation) this.stop('error')
        return false
      } finally {
        if (this.generation === generation) this.advancing = false
      }
    }
    const schedule = () => { this.frame = this.host.requestAnimationFrame(tick) }
    const tick = async time => {
      if (!active()) { if (this.generation === generation) this.stop('inactive'); return }
      this.frame = null
      const elapsed = this.lastTime == null ? 0 : Math.min(100, Math.max(0, time - this.lastTime))
      this.lastTime = time
      this.lastFlush ??= time
      this.distance += pace(time) * elapsed / 1000
      const distance = renderer.supportsFractionalAutoScroll?.() ? this.distance : Math.floor(this.distance)
      if (distance > 0 && !await advance(distance, time)) return
      if (active()) schedule()
    }
    if (eInkMode) {
      const now = () => this.host.performance?.now?.() ?? Date.now()
      this.scheduleEink = () => {
        if (this.timer != null) this.host.clearTimeout(this.timer)
        if (!active()) { if (this.generation === generation) this.stop('inactive'); return }
        const step = this.distance > .001 ? this.distance : renderer.getAutoScrollStep?.() ?? 600
        const delay = Math.max(100, Math.min(2147483647, step / pace(now()) * 1000))
        this.timer = this.host.setTimeout(async () => {
          if (!active()) { if (this.generation === generation) this.stop('inactive'); return }
          this.timer = null
          if (this.distance <= .001) this.distance += step
          if (await advance(this.distance, now()) && active()) this.scheduleEink()
        }, delay)
      }
      this.scheduleEink()
    } else schedule()
    return true
  }
  stop(reason = 'manual') {
    if (!this.running) return
    this.running = false
    this.generation++
    this.cancelScheduled()
    const renderer = this.currentRenderer
    this.currentRenderer = null
    try { renderer.flushAutoScrollPosition?.() }
    finally {
      renderer.setAutoScrolling?.(false)
      this.onStop(reason, this.session)
    }
  }
}
