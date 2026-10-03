import { adjacentPanel, readingRegions, layoutSignature } from './pdf-reading-layout.js'
import { scrollPagePlan, scrollVisibleRegion, scrollSourcePoint } from './pdf-scroll-layout.js'

const GAP = 16, MAX_FRAMES = 7

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
    constructor({ book, layout, view, createFrame, bounds, onLoad, onRelocate, onState }) {
        Object.assign(this, { book, layout, view, createFrame, bounds, onLoad, onRelocate, onState })
        Object.assign(this.element.style, { width: '100%', height: '100%', overflow: 'auto',
            position: 'relative', boxSizing: 'border-box', overflowAnchor: 'none',
            overscrollBehavior: 'contain', touchAction: 'pan-x pan-y', scrollbarGutter: 'stable' })
        this.element.setAttribute('data-pdf-scroll', '')
        this.element.addEventListener('scroll', () => {
            if (this.programmaticTop === this.element.scrollTop &&
                this.programmaticLeft === this.element.scrollLeft) return
            this.changed(true)
        })
        this.element.addEventListener('wheel', event => this.wheel(event), { passive: false })
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
                    const regions = readingRegions(this.layout, page)
                    const found = regions.findIndex(r => center.x >= r.x && center.x < r.x + r.width &&
                        center.y >= r.y && center.y < r.y + r.height)
                    e.fallback = found < 0
                    e.panel = e.fallback ? 0 : found
                    e.crop = e.fallback ? { x: 0, y: 0, width: 1, height: 1 } : regions[found]
                }
            }
            this.entries = [e]
            this.layoutEntry(e)
            this.restore(e, center)
            this.savedLocation = this.location
            e = null
            return true
        } finally { e?.element.remove() }
    }
    activate(reason = 'navigation') {
        this.active = true
        for (const e of this.entries) if (!e.announced) {
            this.onLoad(e.iframe.contentDocument, e.index); e.announced = true
        }
        this.onRelocate(reason)
        this.reportedLocation = this.location
        this.changed(false)
    }
    suspend() {
        this.active = false
        clearTimeout(this.timer)
        this.detailGeneration++
    }
    async load({ page, panel }, before = null) {
        const src = await this.book.sections[page].load()
        if (this.destroyed) throw new Error('Reader closed')
        const e = await this.createFrame(page, src, this.element, before)
        try {
            if (this.destroyed) throw new Error('Reader closed')
            Object.assign(e.iframe.style, { display: 'block', width: `${e.width}px`, height: `${e.height}px` })
            await (e.iframe.contentDocument.querySelector('[data-document-base]') ?? e.iframe.contentDocument.querySelector('img'))?.decode()
            if (this.destroyed) throw new Error('Reader closed')
            e.nativeText = e.iframe.contentDocument.documentElement.dataset.documentImage === 'false'
            e.fallback = e.nativeText
            e.panel = e.nativeText ? 0 : panel
            e.crop = readingRegions(this.layout, page, this.book)[e.panel]
            if (!e.crop) throw new Error('Invalid PDF panel')
            return e
        } catch (error) { e.element.remove(); throw error }
    }
    layoutEntry(e) {
        const bounds = this.bounds()
        e.plan = scrollPagePlan({ pageWidth: e.width, pageHeight: e.height,
            width: Math.max(1, (this.element.clientWidth || bounds.width) - 12), height: Math.max(1, bounds.height), crop: e.crop, view: this.view })
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
    }
    resize(view = this.view) {
        // ResizeObserver runs after the container changed size. Capture the
        // source anchor on scroll, not from the already-resized viewport here.
        const location = this.savedLocation ?? this.location
        const e = this.entries.find(e => e.index === location?.page && e.panel === location?.panel) ?? this.current
        this.view = view
        for (const item of this.entries) this.layoutEntry(item)
        if (e) this.restore(e, location?.center)
        this.changed(false)
    }
    pan(dx, dy) {
        if (!this.active || this.destroyed || ![dx, dy].every(Number.isFinite)) return false
        this.element.scrollLeft += dx
        this.element.scrollTop += dy
        this.changed(true)
        return true
    }
    wheel(event) {
        if (event.ctrlKey || event.metaKey || !this.active) return
        const unit = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? this.bounds().height : 1
        this.pan(event.deltaX * unit, event.deltaY * unit)
        event.preventDefault(); event.stopImmediatePropagation()
    }
    attachInput(doc) {
        doc.addEventListener('wheel', e => this.wheel(e), { capture: true, passive: false })
        let start, last, dragging = false, suppressClick = 0
        const point = event => {
            const touches = [...event.touches]
            return touches.length ? { x: touches.reduce((s, t) => s + t.screenX, 0) / touches.length,
                y: touches.reduce((s, t) => s + t.screenY, 0) / touches.length } : null
        }
        doc.addEventListener('touchstart', event => {
            if (!this.active) return
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
                this.pan(last.x - p.x, last.y - p.y)
                event.preventDefault(); event.stopImmediatePropagation()
            }
            last = p
        }, { capture: true, passive: false })
        for (const type of ['touchend', 'touchcancel']) doc.addEventListener(type, event => {
            if (dragging) {
                event.preventDefault(); event.stopImmediatePropagation(); suppressClick = Date.now() + 400
            }
            last = point(event)
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
        if (this.entries.length < MAX_FRAMES) return true
        const e = direction > 0 ? this.entries[0] : this.entries.at(-1)
        if (e === this.current) return false
        const top = this.element.scrollTop, bottom = top + this.bounds().height
        if (e.element.offsetTop < bottom && e.element.offsetTop + e.plan.height > top) return false
        if (e.iframe.contentDocument.getSelection()?.type === 'Range') return false
        const oldTop = this.current?.element.getBoundingClientRect().top, current = this.current
        this.entries.splice(this.entries.indexOf(e), 1)
        this.dispose(e)
        if (current && oldTop != null) this.programmaticScroll(this.element.scrollLeft,
            this.element.scrollTop + current.element.getBoundingClientRect().top - oldTop)
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
        } catch (_) {
            if (!this.destroyed && this.active) { this.blocked.add(direction); this.onState('failed') }
            return false
        } finally { if (e) this.dispose(e) }
    }
    ensureNeighbors() {
        if (this.neighborTask) return this.neighborTask
        if (!this.active || this.destroyed) return Promise.resolve()
        this.extending = true
        this.neighborTask = Promise.resolve().then(async () => {
            if (!this.active || this.destroyed) return
            if (this.element.scrollTop < this.bounds().height) await this.extend(-1)
            for (let n = 0; n < MAX_FRAMES && this.active && !this.destroyed; n++) {
                const last = this.entries.at(-1)
                if (!last || last.element.offsetTop + last.plan.height > this.element.scrollTop + this.bounds().height * 2) break
                if (!await this.extend(1)) break
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
    changed(record) {
        if (!this.active || this.destroyed) return
        this.savedLocation = this.location
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
        const active = () => this.active && !this.destroyed && generation === this.detailGeneration
        for (const e of this.entries) {
            if (!active()) return
            if (e.nativeText) continue
            const viewport = this.viewport
            const region = scrollVisibleRegion(e.plan, e.crop, e.element.getBoundingClientRect(), viewport)
            if (!region) continue
            let url
            try {
                const dpr = devicePixelRatio || 1
                const result = await this.book.readingRegionRenderer.render({ page: e.index, region,
                    enhancement: this.view.enhancement,
                    hideWatermarks: this.view.display?.hideWatermarks,
                    width: region.width * e.width * e.plan.scale * dpr,
                    height: region.height * e.height * e.plan.scale * dpr })
                if (!active() || !this.entries.includes(e)) return
                url = URL.createObjectURL(result.blob)
                const img = e.iframe.contentDocument.createElement('img')
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
            } catch (_) { /* Keep the base page visible; later scroll/resize retries. */ }
            finally { if (url) URL.revokeObjectURL(url) }
        }
    }
    getContents() { return this.entries.map(e => ({ doc: e.iframe.contentDocument, index: e.index })) }
    dispose(e) { if (e.url) URL.revokeObjectURL(e.url); e.element.remove() }
    destroy() {
        this.suspend(); this.destroyed = true; this.generation++
        for (const e of this.entries) this.dispose(e)
        this.entries = []; this.element.remove()
    }
}
