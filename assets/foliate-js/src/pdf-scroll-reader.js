import { adjacentPanel, readingRegions, layoutSignature, resolveReadingRegions } from './pdf-reading-layout.js'
import { scrollPagePlan, scrollVisibleRegion, scrollSourcePoint } from './pdf-scroll-layout.js'
import { PdfRenderBudget } from './pdf-render-budget.js'
import './transient-scrollbar.js'
import { attachPdfZoomInput } from './pdf-zoom-input.js'

const GAP = 16, MAX_FRAMES = 7, MAX_BASE_PIXELS = 8388608

// Sliding, bounded DOM window. Prepending/removing pages compensates scrollTop;
// an iframe is inserted at its final position before its src is assigned.
export class PdfScrollReader {
    element = document.createElement('div')
    entries = []
    active = false
    destroyed = false
    extending = false
    generation = 0
    detailGeneration = 0
    blocked = new Set()
    budget = new PdfRenderBudget()
    baseController = new AbortController()
    direction = 1
    lastTop = 0
    constructor({ book, layout, view, createFrame, bounds, onLoad, onRelocate, onState, canAnimate = () => true, canPrepare = () => true,
        setZoom = () => {}, boxMode = () => false, pageViews = {} }) {
        Object.assign(this, { book, layout, view, createFrame, bounds, onLoad, onRelocate, onState, canAnimate, canPrepare, setZoom, boxMode, pageViews })
        Object.assign(this.element.style, { width: '100%', height: '100%', overflow: 'auto',
            position: 'relative', boxSizing: 'border-box', overflowAnchor: 'none',
            overscrollBehavior: 'contain', touchAction: 'pan-x pan-y', scrollbarWidth: 'none' })
        this.element.setAttribute('data-pdf-scroll', '')
        this.element.addEventListener('scroll', () => {
            if (this.programmaticTop === this.element.scrollTop &&
                this.programmaticLeft === this.element.scrollLeft) return
            this.changed(true)
        })
        this.element.addEventListener('wheel', event => this.wheel(event), { passive: false })
        this.element.addEventListener('touchstart', () => this.stopMomentum(), { passive: true })
    }
    get current() {
        const middle = this.element.scrollTop + this.viewport.height / 2
        return this.entries.find(e => e.element.offsetTop + e.plan.height > middle) ?? this.entries.at(-1)
    }
    get viewport() {
        const rect = this.element.getBoundingClientRect(), bounds = this.bounds()
        const width = this.element.clientWidth || bounds.width, height = this.element.clientHeight || bounds.height
        return { left: rect.left, top: rect.top, width, height, right: rect.left + width, bottom: rect.top + height }
    }
    get location() {
        const e = this.current
        if (!e) return null
        const rect = e.element.getBoundingClientRect(), viewport = this.viewport
        return { page: e.index, panel: e.panel,
            zoom: e.zoom ?? this.view.zoom,
            total: e.fallback ? 1 : readingRegions(this.layout, e.index).length,
            signature: e.fallback ? 'original-target' : layoutSignature(this.layout, e.index),
            center: scrollSourcePoint(e.plan, e.crop,
                viewport.left + viewport.width / 2 - rect.left,
                viewport.top + viewport.height / 2 - rect.top) }
    }
    async open(page, panel, anchor, center) {
        const version = this.generation
        let e
        try {
            e = await this.load({ page, panel })
            if (this.destroyed || version !== this.generation) return false
            if (typeof anchor === 'function' && !e.nativeText) {
                const doc = e.iframe.contentDocument, target = anchor(doc)
                let rect = [...(target?.getClientRects?.() ?? [])].find(r => r.width && r.height)
                if (!rect && target?.startContainer) {
                    const node = target.startContainer.nodeType === 3 ? target.startContainer.parentElement : target.startContainer
                    if (node?.closest?.('.textLayer')) rect = node.getBoundingClientRect()
                }
                if (rect) {
                    center = { x: (rect.left + Math.min(1, rect.width / 2)) / e.width,
                        y: (rect.top + rect.height / 2) / e.height }
                    const regions = e.regions
                    const found = regions.findIndex(r => center.x >= r.x && center.x < r.x + r.width &&
                        center.y >= r.y && center.y < r.y + r.height)
                    e.fallback = found < 0
                    e.panel = e.fallback ? 0 : found
                    e.crop = e.fallback ? { x: 0, y: 0, width: 1, height: 1 } : regions[found]
                }
            }
            this.entries = [e]
            // A search anchor can select a different panel or the original page.
            await this.prepareBase(e)
            if (this.destroyed || version !== this.generation) return false
            this.layoutEntry(e)
            this.restore(e, center)
            this.savedLocation = this.location
            e = null
            return true
        } finally { if (e) this.dispose(e) }
    }
    activate(reason = 'navigation') {
        if (this.baseController.signal.aborted) this.baseController = new AbortController()
        this.active = true
        if (!this.scrollbars && this.element.parentNode) {
            this.scrollbars = [globalThis.moduAttachScrollbar(
                this.element, this.element.parentNode, {
                    enabled: () => this.active,
                    reducedMotion: () => !this.canAnimate(),
                })]
        }
        for (const e of this.entries) if (!e.announced) {
            this.onLoad(e.iframe.contentDocument, e.index); e.announced = true
        }
        this.onRelocate(reason)
        this.reportedLocation = this.location
        this.changed(false)
    }
    suspend() {
        this.flushPosition()
        this.stopMomentum()
        this.active = false
        this.baseController.abort()
        this.scrollbars?.forEach(bar => bar.update())
        clearTimeout(this.timer)
        this.detailGeneration++
    }
    async load({ page, panel }, before = null) {
        const started = performance.now(), signal = this.baseController.signal
        const available = () => !this.destroyed && !signal.aborted
        const section = this.book.sections[page]
        const src = await (section.loadFrame ? section.loadFrame() : section.load())
        if (!available()) throw new DOMException('Reader closed', 'AbortError')
        const e = await this.createFrame(page, src, this.element, before)
        try {
            if (!available()) throw new DOMException('Reader closed', 'AbortError')
            Object.assign(e.iframe.style, { display: 'block', width: `${e.width}px`, height: `${e.height}px` })
            if (!section.loadFrame) {
                const doc = e.iframe.contentDocument
                await (doc.querySelector('[data-document-base]') ?? doc.querySelector('img'))?.decode()
            }
            if (!available()) throw new DOMException('Reader closed', 'AbortError')
            e.nativeText = e.iframe.contentDocument.documentElement.dataset.documentImage === 'false'
            e.fallback = e.nativeText
            e.panel = e.nativeText ? 0 : panel
            e.regions = e.nativeText ? readingRegions(null, page) :
                await resolveReadingRegions(this.layout, page, this.book,
                    {hideWatermarks: this.view.display?.hideWatermarks, active: available, signal})
            e.crop = e.regions[e.panel]
            if (!e.crop) throw new Error('Invalid PDF panel')
            await this.prepareBase(e, signal)
            if (!available()) throw new DOMException('Reader closed', 'AbortError')
            this.budget.record(performance.now() - started)
            return e
        } catch (error) { this.dispose(e); throw error }
    }
    async prepareBase(e, signal = this.baseController.signal) {
        if (e.nativeText || !this.book.sections[e.index].loadFrame) return
        const key = JSON.stringify([e.crop, this.view.enhancement, this.view.display?.hideWatermarks])
        if (e.baseKey === key) return
        const bounds = this.bounds()
        const plan = scrollPagePlan({ pageWidth: e.width, pageHeight: e.height,
            width: Math.max(1, (this.element.clientWidth || bounds.width) - 12),
            height: Math.max(1, bounds.height), crop: e.crop, view: this.view })
        const dpr = devicePixelRatio || 1
        // Backing pixels stay bounded at 8MP even at high zoom; detail uses visible regions.
        const result = await (this.book.scrollRegionRenderer ?? this.book.readingRegionRenderer).render({
            page: e.index, region: e.crop, enhancement: this.view.enhancement,
            hideWatermarks: this.view.display?.hideWatermarks,
            width: e.crop.width * e.width * plan.scale * dpr,
            height: e.crop.height * e.height * plan.scale * dpr,
        }, {signal})
        if (this.destroyed || signal.aborted) throw new DOMException('Reader closed', 'AbortError')
        let url = URL.createObjectURL(result.blob)
        try {
            const img = e.iframe.contentDocument.querySelector('[data-document-base]') ?? e.iframe.contentDocument.querySelector('img')
            img.src = url
            Object.assign(img.style, {position: 'absolute', left: `${e.crop.x * e.width}px`,
                top: `${e.crop.y * e.height}px`, width: `${e.crop.width * e.width}px`, height: `${e.crop.height * e.height}px`})
            await img.decode()
            if (this.destroyed || signal.aborted) throw new DOMException('Reader closed', 'AbortError')
            if (e.baseUrl) URL.revokeObjectURL(e.baseUrl)
            e.baseUrl = url; url = null
            e.baseKey = key
            e.baseRaster = {width: result.width, height: result.height}
        } finally { if (url) URL.revokeObjectURL(url) }
    }
    layoutEntry(e) {
        const bounds = this.bounds()
        const saved = this.pageViews[`${e.index}:${e.panel}`]
        e.zoom ??= saved?.signature === layoutSignature(this.layout, e.index) &&
            Number.isFinite(saved.zoom) && saved.zoom >= 1 && saved.zoom <= 15 ? Math.min(8, saved.zoom) : Math.min(8, this.view.zoom)
        e.plan = scrollPagePlan({ pageWidth: e.width, pageHeight: e.height,
            width: Math.max(1, (this.element.clientWidth || bounds.width) - 12), height: Math.max(1, bounds.height), crop: e.crop, view: {...this.view,zoom:e.zoom} })
        Object.assign(e.element.style, { position: 'relative', visibility: '',
            width: `${e.plan.width}px`, height: `${e.plan.height}px`, margin: `0 auto ${this.view.display?.separators === false ? 0 : GAP}px`,
            outline: this.view.display?.border ? '1px solid #888' : '',
            filter: this.view.display?.grayscale ? 'grayscale(1)' : '',
            overflow: 'hidden', overflowAnchor: 'none', flexShrink: '0' })
        Object.assign(e.iframe.style, { width: `${e.width}px`, height: `${e.height}px`, display: 'block',
            transform: `matrix(${e.plan.matrix.join(',')})`, transformOrigin: 'top left' })
        const doc = e.iframe.contentDocument
        doc.pdfRegion = true
        doc.scale = e.plan.scale
        doc.pdfClientPoint = (x, y) => {
            const r = e.element.getBoundingClientRect(), [a, b, c, d, tx, ty] = e.plan.matrix
            return { x: r.left + a * x + c * y + tx, y: r.top + b * x + d * y + ty }
        }
        // End padding lets the last (or very short) panel reach the top without
        // materializing the rest of a long book just to fill the screen.
        this.element.style.paddingBottom = `${bounds.height}px`
        if (!e.inputAttached) { this.attachInput(doc); e.inputAttached = true }
    }
    restore(e, center) {
        let x = 0, y = 0
        if (center && [center.x, center.y].every(Number.isFinite)) {
            const [a, b, c, d, tx, ty] = e.plan.matrix
            x = a * center.x * e.width + c * center.y * e.height + tx - this.viewport.width / 2
            y = b * center.x * e.width + d * center.y * e.height + ty - this.viewport.height / 2
        }
        this.programmaticScroll(Math.max(0, x), Math.max(0, e.element.offsetTop + y))
    }
    programmaticScroll(left, top) {
        this.element.scrollLeft = left
        this.element.scrollTop = top
        this.programmaticLeft = this.element.scrollLeft
        this.programmaticTop = this.element.scrollTop
        this.lastTop = this.element.scrollTop
    }
    panWithinPage(dx, dy) {
        const e = this.current
        if (!e) return
        this.stopMomentum()
        this.programmaticScroll(Math.max(0, Math.min(Math.max(0, e.plan.width - this.viewport.width), this.element.scrollLeft + dx)),
            Math.max(e.element.offsetTop, Math.min(e.element.offsetTop + Math.max(0, e.plan.height - this.viewport.height), this.element.scrollTop + dy)))
        this.changed(true)
    }
    resize(view = this.view) {
        this.stopMomentum()
        // ResizeObserver runs after the container changed size. Capture the
        // source anchor on scroll, not from the already-resized viewport here.
        const location = this.savedLocation ?? this.location
        const e = this.entries.find(e => e.index === location?.page && e.panel === location?.panel) ?? this.current
        if (e && view.zoom !== this.view.zoom) {
            e.zoom = Math.min(8, view.zoom)
            // Prepared neighbours are not visited pages: inherit the new zoom
            // unless this book already has an explicit viewport for that page.
            for (const item of this.entries) {
                const saved = this.pageViews[`${item.index}:${item.panel}`]
                if (item !== e && saved?.signature !== layoutSignature(this.layout, item.index))
                    item.zoom = Math.min(8, view.zoom)
            }
        }
        this.view = view
        for (const item of this.entries) this.layoutEntry(item)
        if (e) this.restore(e, location?.center)
        this.changed(false)
    }
    resetPosition() {
        if (this.current) this.restore(this.current, null)
        this.changed(true)
    }
    pan(dx, dy) {
        if (!this.active || this.destroyed || ![dx, dy].every(Number.isFinite)) return false
        this.element.scrollLeft += dx
        this.element.scrollTop += dy
        this.changed(true)
        return true
    }
    wheel(event) {
        this.stopMomentum()
        if (event.ctrlKey || event.metaKey || !this.active) return
        const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? this.bounds().height : 1
        this.pan(event.deltaX * unit, event.deltaY * unit)
        event.preventDefault(); event.stopImmediatePropagation()
    }
    stopMomentum() {
        if (this.momentumFrame != null)
            this.element.ownerDocument.defaultView.cancelAnimationFrame(this.momentumFrame)
        this.momentumFrame = null
    }
    startMomentum(vx, vy) {
        this.stopMomentum()
        if (!this.canAnimate() || Math.hypot(vx, vy) < 0.1) return
        const host = this.element.ownerDocument.defaultView
        let previous
        const tick = now => {
            this.momentumFrame = null
            if (!this.active || this.destroyed || !this.canAnimate() ||
                this.element.ownerDocument.visibilityState === 'hidden' ||
                this.entries.some(e => e.iframe.contentDocument.getSelection()?.type === 'Range')) return
            const elapsed = previous == null ? 16 : now - previous
            if (elapsed > 100) return // Never jump after the WebView resumes.
            previous = now
            const decay = Math.exp(-elapsed / 240)
            const left = this.element.scrollLeft, top = this.element.scrollTop
            this.pan(vx * 240 * (1 - decay), vy * 240 * (1 - decay))
            vx = this.element.scrollLeft === left ? 0 : vx * decay
            vy = this.element.scrollTop === top ? 0 : vy * decay
            if (Math.hypot(vx, vy) >= 0.03) this.momentumFrame = host.requestAnimationFrame(tick)
        }
        this.momentumFrame = host.requestAnimationFrame(tick)
    }
    attachInput(doc) {
        attachPdfZoomInput(doc, {
            active: () => this.active && !this.destroyed,
            zoom: () => this.current?.zoom ?? this.view.zoom,
            setZoom: this.setZoom, pan: (x,y) => this.pan(x,y), boxMode: this.boxMode,
            onGesture: () => this.stopMomentum(),
            onGestureEnd: () => this.flushPosition(),
            box: rect => {
                const e = this.entries.find(e => e.iframe.contentDocument === doc)
                if (!e) return
                const swapped = this.view.rotation % 180 !== 0
                this.setZoom((e.zoom ?? this.view.zoom) * Math.min(this.viewport.width/((swapped ? rect.height : rect.width)*e.plan.scale),
                    this.viewport.height/((swapped ? rect.width : rect.height)*e.plan.scale)))
                this.restore(e, {x:(rect.x+rect.width/2)/e.width,y:(rect.y+rect.height/2)/e.height})
                this.changed(true)
            },
        })
        doc.addEventListener('wheel', e => this.wheel(e), { capture: true, passive: false })
        let start, last, dragging = false, suppressClick = 0, vx = 0, vy = 0, movedAt = 0
        const point = event => {
            const touches = [...event.touches]
            return touches.length ? { x: touches.reduce((s, t) => s + t.screenX, 0) / touches.length,
                y: touches.reduce((s, t) => s + t.screenY, 0) / touches.length,
                count: touches.length, at: event.timeStamp } : null
        }
        doc.addEventListener('touchstart', event => {
            if (!this.active) return
            if (this.momentumFrame != null) suppressClick = Date.now() + 400
            this.stopMomentum()
            vx = vy = 0
            last = point(event); start = { ...last, at: Date.now() }
            dragging ||= event.touches.length > 1
            if (dragging) { event.preventDefault(); event.stopImmediatePropagation() }
        }, { capture: true, passive: false })
        doc.addEventListener('touchmove', event => {
            const p = point(event)
            if (!p || !last || !this.active) return
            if (!dragging && doc.getSelection()?.type !== 'Range' && Date.now() - start.at < 350 &&
                Math.hypot(p.x - start.x, p.y - start.y) > 8) dragging = true
            if (dragging) {
                if (p.count === last.count) {
                    const dx = last.x - p.x, dy = last.y - p.y
                    const elapsed = Math.max(1, p.at - last.at)
                    vx = Math.max(-4, Math.min(4, dx / elapsed))
                    vy = Math.max(-4, Math.min(4, dy / elapsed))
                    movedAt = p.at
                    this.pan(dx, dy)
                } else { vx = vy = 0 }
                event.preventDefault(); event.stopImmediatePropagation()
            }
            last = p
        }, { capture: true, passive: false })
        for (const type of ['touchend', 'touchcancel']) doc.addEventListener(type, event => {
            const released = point(event)
            if (dragging) {
                event.preventDefault(); event.stopImmediatePropagation(); suppressClick = Date.now() + 400
                if (type === 'touchend' && !released && event.timeStamp - movedAt < 80)
                    this.startMomentum(vx, vy)
            }
            vx = vy = 0
            last = released
            if (!last || type === 'touchcancel') { dragging = false; start = null }
        }, { capture: true, passive: false })
        doc.addEventListener('click', event => {
            if (Date.now() < suppressClick) { event.preventDefault(); event.stopImmediatePropagation() }
        }, { capture: true })
    }
    adjacent(e, direction) {
        if (!e.fallback) return adjacentPanel(this.layout, this.book.sections.length, e.index, e.panel, direction, this.book)
        const page = e.index + direction
        return page < 0 || page >= this.book.sections.length ? null :
            { page, panel: direction > 0 ? 0 : readingRegions(this.layout, page).length - 1 }
    }
    trim(direction) {
        // Reserve one maximum-sized incoming page; never evict visible/selected content.
        const pixels = () => this.entries.reduce((sum, e) =>
            sum + (e.baseRaster ? e.baseRaster.width * e.baseRaster.height : 0), 0)
        while (this.entries.length >= MAX_FRAMES || pixels() + MAX_BASE_PIXELS > this.budget.maxBasePixels) {
            const e = direction > 0 ? this.entries[0] : this.entries.at(-1)
            if (!e) return false
            if (e === this.current) return false
            const top = this.element.scrollTop, bottom = top + this.bounds().height
            if (e.element.offsetTop < bottom && e.element.offsetTop + e.plan.height > top) return false
            if (e.iframe.contentDocument.getSelection()?.type === 'Range') return false
            const oldTop = this.current?.element.getBoundingClientRect().top, current = this.current
            this.entries.splice(this.entries.indexOf(e), 1)
            this.dispose(e)
            if (current && oldTop != null) this.programmaticScroll(this.element.scrollLeft,
                this.element.scrollTop + current.element.getBoundingClientRect().top - oldTop)
        }
        return true
    }
    async extend(direction) {
        const edge = direction > 0 ? this.entries.at(-1) : this.entries[0]
        const target = edge && this.adjacent(edge, direction)
        if (!target || this.blocked.has(direction) || !this.trim(direction)) return false
        let e
        try {
            e = await this.load(target, direction < 0 ? this.entries[0].element : null)
            if (!this.active || this.destroyed) return false
            const current = this.current, oldTop = current?.element.getBoundingClientRect().top
            direction > 0 ? this.entries.push(e) : this.entries.unshift(e)
            this.layoutEntry(e)
            if (current && oldTop != null) this.programmaticScroll(this.element.scrollLeft,
                this.element.scrollTop + current.element.getBoundingClientRect().top - oldTop)
            this.onLoad(e.iframe.contentDocument, e.index)
            e.announced = true
            e = null
            this.changed(this.current !== current)
            return true
        } catch (error) {
            if (!this.destroyed && this.active && error.name !== 'AbortError') { this.blocked.add(direction); this.onState('failed') }
            return false
        } finally { if (e) this.dispose(e) }
    }
    ensureNeighbors() {
        if (this.neighborTask) return this.neighborTask
        if (!this.active || this.destroyed || !this.canPrepare()) return Promise.resolve()
        this.extending = true
        this.neighborTask = Promise.resolve().then(async () => {
            // Prepare the direction of travel first, including tall pages whose
            // next page lies outside the old two-screen loading threshold.
            for (const direction of [this.direction, -this.direction]) {
                for (let n = 0; n < MAX_FRAMES && this.active && !this.destroyed && this.canPrepare(); n++) {
                    const current = this.entries.indexOf(this.current), edge = direction > 0 ? this.entries.at(-1) : this.entries[0]
                    if (!edge || current < 0) break
                    const count = direction > 0 ? this.entries.length - current - 1 : current
                    const wanted = direction === this.direction ? this.budget.ahead : 1
                    const covered = direction > 0 ? edge.element.offsetTop + edge.plan.height >= this.element.scrollTop + this.bounds().height * 2
                        : edge.element.offsetTop <= this.element.scrollTop - this.bounds().height
                    if (count >= wanted && covered) break
                    if (!await this.extend(direction)) break
                }
            }
        }).finally(() => { this.extending = false; this.neighborTask = null })
        return this.neighborTask
    }
    async retry() {
        this.blocked.clear()
        await this.ensureNeighbors()
        if (!this.blocked.size) this.onState('ready')
        return this.blocked.size === 0
    }
    flushPosition() {
        if (!this.active || this.destroyed || !this.recordPending) return
        this.recordPending = false
        this.onRelocate('viewport')
        this.reportedLocation = this.location
    }
    changed(record) {
        if (!this.active || this.destroyed) return
        if (record && this.element.scrollTop !== this.lastTop)
            this.direction = this.element.scrollTop > this.lastTop ? 1 : -1
        this.lastTop = this.element.scrollTop
        this.savedLocation = this.location
        if (this.savedLocation) {
            const l = this.savedLocation
            this.view = {...this.view, zoom:l.zoom}
            this.pageViews[`${l.page}:${l.panel}`] = {...l}
        }
        this.recordPending ||= record
        // Load neighbours during a gesture; only expensive raster refinement
        // and persistence wait for the short idle window.
        void this.ensureNeighbors()
        this.detailGeneration++
        clearTimeout(this.timer)
        this.timer = setTimeout(() => {
            const record = this.recordPending
            this.recordPending = false
            const location = this.location
            if (record || location?.page !== this.reportedLocation?.page ||
                location?.panel !== this.reportedLocation?.panel) {
                this.onRelocate(record ? 'viewport' : 'layout')
                this.reportedLocation = location
            }
            void this.refreshDetail()
            void this.ensureNeighbors()
        }, 100)
    }
    async refreshDetail() {
        const generation = ++this.detailGeneration
        const active = () => this.active && !this.destroyed && this.canPrepare() && generation === this.detailGeneration
        for (const e of this.entries) {
            if (!active()) return
            if (e.nativeText) continue
            const viewport = this.viewport
            const region = scrollVisibleRegion(e.plan, e.crop, e.element.getBoundingClientRect(), viewport)
            if (!region) continue
            const density = e.plan.scale * (devicePixelRatio || 1)
            if (e.baseRaster?.width / e.crop.width >= e.width * density - 2 &&
                e.baseRaster?.height / e.crop.height >= e.height * density - 2) continue
            let url
            try {
                const dpr = devicePixelRatio || 1
                const request = { page: e.index, region,
                    enhancement: this.view.enhancement,
                    hideWatermarks: this.view.display?.hideWatermarks,
                    width: region.width * e.width * e.plan.scale * dpr,
                    height: region.height * e.height * e.plan.scale * dpr }
                const key = JSON.stringify(request)
                if (e.detailKey === key) continue
                const result = await this.book.readingRegionRenderer.render(request)
                if (!active() || !this.entries.includes(e)) return
                url = URL.createObjectURL(result.blob)
                const img = e.iframe.contentDocument.createElement('img')
                img.dataset.documentDetail = ''
                img.src = url; img.alt = ''
                Object.assign(img.style, { position: 'absolute', pointerEvents: 'none', zIndex: '1',
                    left: `${region.x * e.width}px`, top: `${region.y * e.height}px`,
                    width: `${region.width * e.width}px`, height: `${region.height * e.height}px` })
                await img.decode()
                if (!active() || !this.entries.includes(e)) return
                e.detail?.remove()
                e.iframe.contentDocument.body.append(img); e.detail = img
                if (e.url) URL.revokeObjectURL(e.url)
                e.url = url; url = null
                e.detailKey = key
            } catch (_) { /* Keep the base page visible; later scroll/resize retries. */ }
            finally { if (url) URL.revokeObjectURL(url) }
        }
    }
    getContents() { return this.entries.map(e => ({ doc: e.iframe.contentDocument, index: e.index })) }
    dispose(e) {
        if (e.url) URL.revokeObjectURL(e.url)
        if (e.baseUrl) URL.revokeObjectURL(e.baseUrl)
        e.element.remove()
    }
    destroy() {
        this.suspend(); this.destroyed = true; this.generation++
        this.scrollbars?.forEach(bar => bar.destroy())
        for (const e of this.entries) this.dispose(e)
        this.entries = []; this.element.remove()
    }
}
