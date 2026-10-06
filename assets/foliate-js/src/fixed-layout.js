import { bookFrameSandbox } from './frame-script-policy.js'
import { adjacentPanel, readingRegions, restoredPanel, layoutSignature,
    validateReadingLayout, resolveReadingRegions } from './pdf-reading-layout.js'
import { normalizePdfView, pdfViewport, panPdfViewport } from './pdf-reading-viewport.js'
import { normalizeDocumentDisplay, attachDocumentGestures } from './document-reading-options.js'
import { PdfScrollReader } from './pdf-scroll-reader.js'

const parseViewport = str => str
    ?.split(/[,;\s]/) // NOTE: technically, only the comma is valid
    ?.filter(x => x)
    ?.map(x => x.split('=').map(x => x.trim()))

const getViewport = (doc, viewport) => {
    // use `viewBox` for SVG
    if (doc.documentElement.localName === 'svg') {
        const [, , width, height] = doc.documentElement
            .getAttribute('viewBox')?.split(/\s/) ?? []
        return { width, height }
    }

    // get `viewport` `meta` element
    const meta = parseViewport(doc.querySelector('meta[name="viewport"]')
        ?.getAttribute('content'))
    if (meta) return Object.fromEntries(meta)

    // fallback to book's viewport
    if (typeof viewport === 'string') return parseViewport(viewport)
    if (viewport) return viewport

    // if no viewport (possibly with image directly in spine), get image size
    const img = doc.querySelector('img')
    if (img) return { width: img.naturalWidth, height: img.naturalHeight }

    // just show *something*, i guess...
    console.warn(new Error('Missing viewport properties'))
    return { width: 1000, height: 2000 }
}

export class FixedLayout extends HTMLElement {
    #root = this.attachShadow({ mode: 'closed' })
    #observer = new ResizeObserver(() => { this.#render(); this.#schedulePdfDetail() })
    #spreads
    #index = -1
    defaultViewport
    spread
    #portrait = false
    #left
    #right
    #center
    #side
    #pdfLayout
    #pdfEnabled = false
    #pdfPage = -1
    #pdfPanel = 0
    #pdfFallback = false
    #pdfResume
    #pdfGeneration = 0
    #pdfUrl
    #pdfBusy = false
    #pdfRetry
    #pdfView = normalizePdfView()
    #pdfCenter
    #pdfPlan
    #pdfDetailGeneration = 0
    #pdfDetailTimer
    #pdfDetailUrl
    #pdfPrefetchTimer
    #pdfPrefetchGeneration = 0
    #pdfPrefetchBusy = false
    #pdfScroll
    #destroyed = false
    #autoTimer
    #autoAt = 0
    readerActive = true
    get pdfReading() { return this.#pdfEnabled }
    get isNavigating() { return this.#pdfBusy }
    get pdfView() { return { ...this.#pdfView } }
    setPdfView(value) {
        if (this.#destroyed || this.#pdfBusy || !this.book?.readingRegionRenderer) return false
        const next = normalizePdfView(value)
        const previous = this.#pdfView, location = this.pdfRegionLocation
        const changeMode = next.mode !== previous.mode
        const changeImage = JSON.stringify(next.enhancement ?? {}) !== JSON.stringify(previous.enhancement ?? {}) ||
            next.display?.hideWatermarks !== previous.display?.hideWatermarks
        if (next.fit !== this.#pdfView.fit) this.#pdfCenter = null
        this.#pdfView = next
        this.#autoAt = Date.now()
        if ((changeMode || changeImage) && this.#pdfEnabled && location) {
            return this.#showPdfPanel(location.page, location.panel, 'layout', null, location.center).then(ok => {
                if (!ok) { this.#pdfView = previous; this.#pdfScroll?.activate('layout'); this.#pdfRetry = null }
                return ok
            })
        }
        this.#render()
        this.#schedulePdfDetail(true)
        return true
    }
    panPdfView(dx, dy) {
        if (this.#pdfScroll && this.#pdfEnabled && !this.#pdfBusy) return this.#pdfScroll.pan(dx, dy)
        if (!this.#pdfEnabled || !this.#pdfPlan || this.#pdfBusy || this.#destroyed) return false
        this.#pdfCenter = panPdfViewport(this.#pdfPlan, dx, dy)
        this.#render()
        this.#schedulePdfDetail(true)
        return true
    }
    get pdfRegionLocation() {
        if (this.#pdfEnabled && this.#pdfScroll) return this.#pdfScroll.location
        if (!this.#pdfEnabled || this.#pdfPage < 0) return null
        return { page: this.#pdfPage, panel: this.#pdfPanel,
            total: this.#pdfFallback ? 1 : readingRegions(this.#pdfLayout, this.#pdfPage).length,
            signature: this.#pdfFallback ? 'original-target' : layoutSignature(this.#pdfLayout, this.#pdfPage),
            center: this.#pdfCenter ? { ...this.#pdfCenter } : null }
    }
    async setPdfLayout(config, enabled, resume) {
        if (!this.book.readingRegionRenderer) return false
        const layout = validateReadingLayout(config)
        const page = this.index
        const previous = { layout: this.#pdfLayout, enabled: this.#pdfEnabled }
        this.#pdfGeneration++
        this.#cancelPdfDetail()
        this.book.readingRegionRenderer.cancel()
        this.#pdfLayout = layout
        this.#pdfResume = resume
        this.#pdfEnabled = enabled === true
        this.#pdfScroll?.suspend()
        if (page < 0) return true
        if (this.#pdfEnabled) {
            const center = resume?.page === page && resume?.signature === layoutSignature(layout, page)
                ? resume.center : null
            const ok = await this.#showPdfPanel(page, restoredPanel(layout, page, resume), 'layout', null, center)
            if (!ok) {
                this.#pdfLayout = previous.layout
                this.#pdfEnabled = previous.enabled
                this.#pdfRetry = null
                this.#pdfScroll?.activate('layout')
                this.dispatchEvent(new CustomEvent('chapter-state', { detail: { state: 'ready' } }))
            }
            return ok
        }
        this.#pdfBusy = false
        const oldSpread = this.#index
        this.#index = -1 // force an original spread, even on the same source page
        try { await this.goTo({ index: page }) }
        catch (_) {
            this.#index = oldSpread
            this.#pdfLayout = previous.layout
            this.#pdfEnabled = previous.enabled
            this.#pdfScroll?.activate('layout')
            return false
        }
        this.#releasePdfUrl()
        return true
    }
    #releasePdfUrl() {
        if (this.#pdfUrl) URL.revokeObjectURL(this.#pdfUrl)
        this.#pdfUrl = null
        if (this.#pdfDetailUrl) URL.revokeObjectURL(this.#pdfDetailUrl)
        this.#pdfDetailUrl = null
    }
    #cancelPdfDetail() {
        clearTimeout(this.#pdfDetailTimer)
        this.#pdfDetailGeneration++
        clearTimeout(this.#pdfPrefetchTimer)
        this.#pdfPrefetchGeneration++
        if (this.#pdfPrefetchBusy) {
            this.book?.readingRegionRenderer?.cancel()
            this.book?.cropRegionRenderer?.cancel()
            this.#pdfPrefetchBusy = false
        }
    }
    #schedulePdfPrefetch() {
        clearTimeout(this.#pdfPrefetchTimer)
        const page = this.#pdfPage + 1, generation = ++this.#pdfPrefetchGeneration
        // Only native PDFs opt in. Never probe ordinary ebook chapters here.
        if (!this.book?.sections[page]?.loadFrame || this.#pdfScroll || !this.#pdfEnabled) return
        const active = () => !this.#destroyed && !this.#pdfBusy && this.#pdfEnabled &&
            generation === this.#pdfPrefetchGeneration
        this.#pdfPrefetchTimer = setTimeout(async () => {
            if (!active() || !this.readerActive) return
            this.#pdfPrefetchBusy = true
            try {
                const regions = await resolveReadingRegions(this.#pdfLayout, page, this.book,
                    {hideWatermarks: this.#pdfView.display?.hideWatermarks, active})
                if (!active()) return
                const bounds = this.getBoundingClientRect()
                await this.book.readingRegionRenderer.render({page, region: regions[0],
                    enhancement: this.#pdfView.enhancement,
                    hideWatermarks: this.#pdfView.display?.hideWatermarks,
                    width: Math.max(1, bounds.width * (devicePixelRatio || 1)),
                    height: Math.max(1, bounds.height * (devicePixelRatio || 1))})
            } catch (_) { /* Optional: a failed prefetch must never change the visible page. */ }
            finally { if (generation === this.#pdfPrefetchGeneration) this.#pdfPrefetchBusy = false }
        }, 800)
    }
    #schedulePdfDetail(record = false) {
        this.#cancelPdfDetail()
        if (this.#pdfScroll) { this.#pdfScroll.changed(record); return }
        if (!this.#pdfEnabled || !this.#center?.crop || this.#destroyed || this.#pdfBusy) return
        this.#pdfDetailTimer = setTimeout(() => {
            if (record) this.#reportLocation('viewport')
            void this.#refreshPdfDetail()
        }, 100)
    }
    async #refreshPdfDetail() {
        const frame = this.#center, plan = this.#pdfPlan
        if (!frame?.crop || !plan || this.#pdfBusy || !this.#pdfEnabled || frame.iframe.contentDocument.documentElement.dataset.documentImage === 'false') return
        const density = plan.scale * (devicePixelRatio || 1)
        // The initial cropped raster already covers the whole crop. Do not
        // render/encode it again at essentially the same screen resolution.
        if (frame.raster && frame.raster.width / frame.crop.width >= frame.width * density - 2 &&
            frame.raster.height / frame.crop.height >= frame.height * density - 2) {
            this.#schedulePdfPrefetch()
            return
        }
        const generation = ++this.#pdfDetailGeneration
        const active = () => !this.#destroyed && this.#pdfEnabled &&
            frame === this.#center && generation === this.#pdfDetailGeneration
        let url
        try {
            const region = plan.sourceRegion, dpr = devicePixelRatio || 1
            // Render in source orientation, then rotate both raster and text
            // with the iframe matrix. Never allocate a zoomed whole-page canvas.
            const result = await this.book.readingRegionRenderer.render({ page: this.#pdfPage, region,
                enhancement: this.#pdfView.enhancement,
                hideWatermarks: this.#pdfView.display?.hideWatermarks,
                width: region.width * frame.width * plan.scale * dpr,
                height: region.height * frame.height * plan.scale * dpr })
            if (!active()) return
            url = URL.createObjectURL(result.blob)
            const img = frame.iframe.contentDocument.createElement('img')
            img.dataset.documentDetail = ''
            img.src = url
            img.alt = ''
            Object.assign(img.style, { position: 'absolute', pointerEvents: 'none', zIndex: '1',
                left: `${region.x * frame.width}px`, top: `${region.y * frame.height}px`,
                width: `${region.width * frame.width}px`, height: `${region.height * frame.height}px` })
            await img.decode()
            if (!active()) return
            frame.detail?.remove()
            // Append after all original nodes to keep existing CFI paths stable.
            frame.iframe.contentDocument.body.append(img)
            frame.detail = img
            if (this.#pdfDetailUrl) URL.revokeObjectURL(this.#pdfDetailUrl)
            this.#pdfDetailUrl = url
            url = null
            this.dispatchEvent(new CustomEvent('pdf-detail', { detail: { state: 'ready' } }))
        } catch (_) {
            // Keep the bounded base raster visible; later movement/resize retries.
            if (active()) this.dispatchEvent(new CustomEvent('pdf-detail', { detail: { state: 'failed' } }))
        } finally {
            if (url) URL.revokeObjectURL(url)
            if (active()) this.#schedulePdfPrefetch()
        }
    }
    #attachPdfPan(doc) {
        doc.addEventListener('wheel', event => {
            if (!this.#pdfEnabled || event.ctrlKey || event.metaKey) return
            if (doc.getSelection()?.type === 'Range') return
            const plan = this.#pdfPlan
            const multiplier = event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? plan?.height ?? 1 : 1
            if (this.panPdfView(event.deltaX * multiplier, event.deltaY * multiplier)) {
                event.preventDefault()
                event.stopImmediatePropagation()
            }
        }, { passive: false, capture: true })
        // Two fingers pan; one finger remains available for text selection and
        // the existing page gestures. Do not bring back automatic selection flips.
        let last, panning = false, suppressClickUntil = 0
        const point = event => event.touches.length === 2
            ? { x: (event.touches[0].screenX + event.touches[1].screenX) / 2,
                y: (event.touches[0].screenY + event.touches[1].screenY) / 2 } : null
        doc.addEventListener('touchstart', event => {
            last = point(event)
            panning ||= !!last
            if (panning) { event.preventDefault(); event.stopImmediatePropagation() }
        }, { passive: false, capture: true })
        doc.addEventListener('touchmove', event => {
            const p = point(event)
            if (last && p) {
                this.panPdfView(last.x - p.x, last.y - p.y)
            }
            if (panning) { event.preventDefault(); event.stopImmediatePropagation() }
            last = p
        }, { passive: false, capture: true })
        for (const type of ['touchend', 'touchcancel']) doc.addEventListener(type, event => {
            if (panning) {
                event.preventDefault(); event.stopImmediatePropagation()
                suppressClickUntil = Date.now() + 400
            }
            last = point(event)
            if (!event.touches.length || type === 'touchcancel') panning = false
        }, { passive: false, capture: true })
        doc.addEventListener('click', event => {
            if (Date.now() < suppressClickUntil) {
                event.preventDefault(); event.stopImmediatePropagation()
            }
        }, { capture: true })
    }
    async #showPdfPanel(page, panel, reason, anchor, center) {
        if (this.#destroyed || page < 0 || page >= this.book.sections.length) return false
        if (this.#pdfView.mode === 'scroll') return this.#showPdfScroll(page, panel, reason, anchor, center)
        let regions = readingRegions(this.#pdfLayout, page)
        let crop = regions[panel], fallback = false
        if (!crop) return false
        const generation = ++this.#pdfGeneration
        this.#cancelPdfDetail()
        this.#pdfScroll?.suspend()
        this.#pdfBusy = true
        this.#pdfRetry = () => this.#showPdfPanel(page, panel, reason, anchor, center)
        this.dispatchEvent(new CustomEvent('chapter-state', { detail: { state: 'loading' } }))
        let frame, url
        const active = () => !this.#destroyed && generation === this.#pdfGeneration
        try {
            const section = this.book.sections[page]
            const src = await (section.loadFrame ? section.loadFrame() : section.load())
            if (!active()) return false
            frame = await this.#createFrame('center', { index: page, src }, true)
            if (!active()) return false
            const nativeText = frame.iframe.contentDocument.documentElement.dataset.documentImage === 'false'
            if (nativeText) { crop = {x:0,y:0,width:1,height:1}; panel = 0; fallback = true }
            else {
                regions = await resolveReadingRegions(this.#pdfLayout, page, this.book,
                    {hideWatermarks: this.#pdfView.display?.hideWatermarks, active})
                if (!active()) return false
                crop = regions[panel]
            }
            // Search/note CFIs keep their original text nodes. Locate the target
            // before cropping; never land on a different invisible panel.
            if (typeof anchor === 'function' && !nativeText) {
                Object.assign(frame.iframe.style, { display: 'block', width: `${frame.width}px`, height: `${frame.height}px` })
                const target = anchor(frame.iframe.contentDocument)
                if (typeof target?.getClientRects === 'function') {
                    let rect = [...target.getClientRects()].find(r => r.width > 0 && r.height > 0)
                    if (!rect) {
                        const node = target.startContainer?.nodeType === 3
                            ? target.startContainer.parentElement : target.startContainer
                        if (node?.closest?.('.textLayer')) rect = node.getBoundingClientRect()
                    }
                    if (rect) {
                        const x = (rect.left + Math.min(1, rect.width / 2)) / frame.width
                        const y = (rect.top + rect.height / 2) / frame.height
                        center = { x, y }
                        const found = regions.findIndex(r => x >= r.x && y >= r.y &&
                            x < r.x + r.width && y < r.y + r.height)
                        fallback = found < 0
                        panel = fallback ? 0 : found
                        crop = fallback ? { x: 0, y: 0, width: 1, height: 1 } : regions[panel]
                    }
                }
            }
            const bounds = this.getBoundingClientRect()
            if (!nativeText) {
            const result = await this.book.readingRegionRenderer.render({ page, region: crop,
                enhancement: this.#pdfView.enhancement,
                hideWatermarks: this.#pdfView.display?.hideWatermarks,
                width: Math.max(1, bounds.width * (devicePixelRatio || 1)),
                height: Math.max(1, bounds.height * (devicePixelRatio || 1)) })
            if (!active()) return false
            frame.raster = {width: result.width, height: result.height}
            url = URL.createObjectURL(result.blob)
            const img = frame.iframe.contentDocument.querySelector('[data-document-base]') ?? frame.iframe.contentDocument.querySelector('img')
            img.src = url
            // Keep the original text/annotation DOM and its CFI paths. Only
            // replace the bitmap, at its original page-coordinate rectangle.
            Object.assign(img.style, { position: 'absolute',
                left: `${crop.x * frame.width}px`, top: `${crop.y * frame.height}px`,
                width: `${crop.width * frame.width}px`, height: `${crop.height * frame.height}px` })
            await img.decode()
            }
            if (!active()) return false
            frame.crop = crop
            frame.iframe.contentDocument.pdfRegion = true
            this.#pdfScroll?.destroy()
            this.#pdfScroll = null
            // Reparenting an iframe reloads its browsing context. Leave the
            // candidate in place and remove only the previously visible frames.
            for (const child of [...this.#root.children])
                if (child !== frame.element) child.remove()
            Object.assign(frame.element.style, { position: '', visibility: '' })
            this.#left = this.#right = null
            this.#center = frame
            this.#side = 'center'
            this.#pdfPage = page
            this.#pdfPanel = panel
            this.#pdfFallback = fallback
            this.#pdfCenter = center
            this.#releasePdfUrl()
            this.#pdfUrl = url
            url = null
            this.#render()
            this.#attachPdfPan(frame.iframe.contentDocument)
            attachDocumentGestures(frame.iframe.contentDocument, () => this.#pdfView,
                direction => direction > 0 ? this.next() : this.prev(),
                () => this.dispatchEvent(new CustomEvent('document-menu')))
            this.dispatchEvent(new CustomEvent('load', { detail: { doc: frame.iframe.contentDocument, index: page } }))
            frame = null // committed; failures/cancellation must not remove it
            this.#reportLocation(reason)
            this.#pdfRetry = null
            this.dispatchEvent(new CustomEvent('chapter-state', { detail: { state: 'ready' } }))
            return true
        } catch (error) {
            if (active()) {
                this.#pdfScroll?.activate('layout')
                this.dispatchEvent(new CustomEvent('chapter-state', { detail: { state: 'failed' } }))
            }
            return false
        } finally {
            frame?.element.remove()
            if (url) URL.revokeObjectURL(url)
            if (active()) { this.#pdfBusy = false; this.#schedulePdfDetail() }
        }
    }
    async #showPdfScroll(page, panel, reason, anchor, center) {
        const generation = ++this.#pdfGeneration
        this.#cancelPdfDetail()
        this.book.readingRegionRenderer.cancel()
        this.#pdfScroll?.suspend()
        this.#pdfBusy = true
        this.#pdfRetry = () => this.#showPdfScroll(page, panel, reason, anchor, center)
        this.dispatchEvent(new CustomEvent('chapter-state', { detail: { state: 'loading' } }))
        const flow = new PdfScrollReader({ book: this.book, layout: this.#pdfLayout, view: this.#pdfView,
            bounds: () => this.getBoundingClientRect(),
            createFrame: (index, src, parent, before) => this.#createFrame('center', { index, src }, true, parent, before),
            onLoad: (doc, index) => this.dispatchEvent(new CustomEvent('load', { detail: { doc, index } })),
            onRelocate: reason => this.#reportLocation(reason),
            onState: state => this.dispatchEvent(new CustomEvent('chapter-state', { detail: { state } })) })
        Object.assign(flow.element.style, { position: 'absolute', visibility: 'hidden' })
        this.#root.append(flow.element)
        const active = () => !this.#destroyed && generation === this.#pdfGeneration
        let committed = false
        try {
            if (!await flow.open(page, panel, anchor, center) || !active()) return false
            this.#pdfScroll?.destroy()
            this.#pdfScroll = flow
            for (const child of [...this.#root.children]) if (child !== flow.element) child.remove()
            Object.assign(flow.element.style, { position: 'relative', visibility: '' })
            this.#left = this.#right = this.#center = null
            this.#releasePdfUrl()
            committed = true
            this.#pdfRetry = null
            flow.activate(reason)
            this.dispatchEvent(new CustomEvent('chapter-state', { detail: { state: 'ready' } }))
            return true
        } catch (_) {
            if (active()) {
                this.#pdfScroll?.activate('layout')
                this.dispatchEvent(new CustomEvent('chapter-state', { detail: { state: 'failed' } }))
            }
            return false
        } finally {
            if (!committed) flow.destroy()
            if (active()) this.#pdfBusy = false
        }
    }
    retryNavigation() { return this.#pdfRetry ? this.#pdfRetry() : this.#pdfScroll?.retry() }
    constructor() {
        super()

        const sheet = new CSSStyleSheet()
        this.#root.adoptedStyleSheets = [sheet]
        sheet.replaceSync(`:host {
            width: 100%;
            height: 100%;
            display: flex;
            justify-content: center;
            align-items: center;
            position: relative;
        }`)

        this.#observer.observe(this)
    }
    async #createFrame(position, { index, src }, deferred = false, parent = this.#root, before = null) {
        const element = document.createElement('div')
        const iframe = document.createElement('iframe')
        element.append(iframe)
        if (deferred) Object.assign(element.style, { position: 'absolute', visibility: 'hidden' })
        Object.assign(iframe.style, {
            border: '0',
            display: 'none',
            overflow: 'hidden',
        })
        iframe.setAttribute('sandbox', bookFrameSandbox())
        iframe.setAttribute('scrolling', 'no')
        iframe.setAttribute('part', 'filter')
        parent.insertBefore(element, before)
        if (!src) return { blank: true, element, iframe }
        return new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
                iframe.removeEventListener('load', onload)
                element.remove()
                reject(new Error('PDF frame load timed out'))
            }, 15000)
            const onload = () => {
                if (iframe.contentDocument?.URL !== src) return
                clearTimeout(timeout)
                iframe.removeEventListener('load', onload)
                const doc = iframe.contentDocument
                doc.position = position
                if (!deferred) this.dispatchEvent(new CustomEvent('load', { detail: { doc, index } }))
                const { width, height } = getViewport(doc, this.defaultViewport)
                resolve({
                    element, iframe, index,
                    width: parseFloat(width),
                    height: parseFloat(height),
                })
            }
            iframe.addEventListener('load', onload)
            iframe.src = src
        })
    }
    #render(side = this.#side) {
        if (this.#destroyed || !this.isConnected) return
        if (this.#pdfScroll) { this.#pdfScroll.resize(this.#pdfView); return }
        if (!side) return
        const left = this.#left ?? {}
        const right = this.#center ?? this.#right
        const target = side === 'left' ? left : right
        const { width, height } = this.getBoundingClientRect()
        if (this.#center?.crop) {
            const frame = this.#center, crop = frame.crop
            if (width <= 0 || height <= 0) return
            const plan = pdfViewport({ pageWidth: frame.width, pageHeight: frame.height,
                width, height, crop, view: this.#pdfView, center: this.#pdfCenter })
            this.#pdfPlan = plan
            this.#pdfCenter = plan.center
            frame.iframe.contentDocument.scale = plan.scale
            frame.iframe.contentDocument.pdfClientPoint = (x, y) => {
                const rect = frame.element.getBoundingClientRect(), [a, b, c, d, e, f] = plan.matrix
                return { x: rect.left + a * x + c * y + e, y: rect.top + b * x + d * y + f }
            }
            Object.assign(frame.iframe.style, { width: `${frame.width}px`, height: `${frame.height}px`,
                transform: `matrix(${plan.matrix.join(',')})`,
                transformOrigin: 'top left', display: 'block' })
            Object.assign(frame.element.style, { width: `${plan.width}px`, height: `${plan.height}px`,
                flexShrink: '0', overflow: 'hidden', display: 'block',
                outline: this.#pdfView.display?.border ? '1px solid #888' : '',
                filter: this.#pdfView.display?.grayscale ? 'grayscale(1)' : '' })
            return
        }
        const portrait = this.spread !== 'both' && this.spread !== 'portrait'
            && height > width
        this.#portrait = portrait
        const blankWidth = left.width ?? right.width
        const blankHeight = left.height ?? right.height

        const scale = portrait || this.#center
            ? Math.min(
                width / (target.width ?? blankWidth),
                height / (target.height ?? blankHeight))
            : Math.min(
                width / ((left.width ?? blankWidth) + (right.width ?? blankWidth)),
                height / Math.max(
                    left.height ?? blankHeight,
                    right.height ?? blankHeight))

        const transform = frame => {
            const { element, iframe, width, height, blank } = frame
            iframe.contentDocument.scale = scale
            Object.assign(iframe.style, {
                width: `${width}px`,
                height: `${height}px`,
                transform: `scale(${scale})`,
                transformOrigin: 'top left',
                display: blank ? 'none' : 'block',
            })
            Object.assign(element.style, {
                width: `${(width ?? blankWidth) * scale}px`,
                height: `${(height ?? blankHeight) * scale}px`,
                overflow: 'hidden',
                display: 'block',
            })
            if (portrait && frame !== target) {
                element.style.display = 'none'
            }
        }
        if (this.#center) {
            transform(this.#center)
        } else {
            transform(left)
            transform(right)
        }
    }
    async #showSpread({ left, right, center, side }) {
        let nextLeft, nextRight, nextCenter
        try {
            if (center) nextCenter = await this.#createFrame('center', center, true)
            else {
                nextLeft = await this.#createFrame('left', left, true)
                nextRight = await this.#createFrame('right', right, true)
            }
            if (this.#destroyed) throw new Error('Reader closed')
            const frames = [nextLeft, nextRight, nextCenter].filter(Boolean)
            this.#pdfScroll?.destroy()
            this.#pdfScroll = null
            for (const child of [...this.#root.children])
                if (!frames.some(frame => frame.element === child)) child.remove()
            this.#left = nextLeft
            this.#right = nextRight
            this.#center = nextCenter
            this.#side = nextCenter ? 'center' : nextLeft.blank ? 'right'
                : nextRight.blank ? 'left' : side
            for (const frame of frames) Object.assign(frame.element.style, { position: '', visibility: '' })
            this.#render()
            for (const frame of frames) if (!frame.blank)
                this.dispatchEvent(new CustomEvent('load', { detail: { doc: frame.iframe.contentDocument, index: frame.index } }))
        } catch (error) {
            for (const frame of [nextLeft, nextRight, nextCenter]) frame?.element.remove()
            throw error
        }
    }
    #goLeft() {
        if (this.#center || this.#left?.blank) return
        if (this.#portrait && this.#left?.element?.style?.display === 'none') {
            this.#right.element.style.display = 'none'
            this.#left.element.style.display = 'block'
            this.#side = 'left'
            return true
        }
    }
    #goRight() {
        if (this.#center || this.#right?.blank) return
        if (this.#portrait && this.#right?.element?.style?.display === 'none') {
            this.#left.element.style.display = 'none'
            this.#right.element.style.display = 'block'
            this.#side = 'right'
            return true
        }
    }
    open(book) {
        this.book = book
        this.#autoAt = Date.now()
        this.#autoTimer = setInterval(async () => {
            const seconds = this.#pdfView.display?.autoSeconds ?? 0
            if (!seconds || !this.#pdfEnabled || this.#pdfBusy || !this.readerActive ||
                document.visibilityState === 'hidden' || this.getContents().some(x => x.doc.getSelection()?.type === 'Range')) {
                this.#autoAt = Date.now(); return
            }
            if (Date.now()-this.#autoAt >= seconds*1000) { this.#autoAt=Date.now(); await this.next() }
        }, 1000)
        const { rendition } = book
        this.spread = rendition?.spread
        this.defaultViewport = rendition?.viewport

        const rtl = book.dir === 'rtl'
        const ltr = !rtl
        this.rtl = rtl

        if (rendition?.spread === 'none')
            this.#spreads = book.sections.map(section => ({ center: section }))
        else this.#spreads = book.sections.reduce((arr, section) => {
            const last = arr[arr.length - 1]
            const { linear, pageSpread } = section
            if (linear === 'no') return arr
            const newSpread = () => {
                const spread = {}
                arr.push(spread)
                return spread
            }
            if (pageSpread === 'center') {
                const spread = last.left || last.right ? newSpread() : last
                spread.center = section
            }
            else if (pageSpread === 'left') {
                const spread = last.center || last.left || ltr ? newSpread() : last
                spread.left = section
            }
            else if (pageSpread === 'right') {
                const spread = last.center || last.right || rtl ? newSpread() : last
                spread.right = section
            }
            else if (ltr) {
                if (last.center || last.right) newSpread().left = section
                else if (last.left) last.right = section
                else last.left = section
            }
            else {
                if (last.center || last.left) newSpread().right = section
                else if (last.right) last.left = section
                else last .right = section
            }
            return arr
        }, [{}])
    }
    get index() {
        if (this.#pdfEnabled && this.#pdfScroll) return this.#pdfScroll.location?.page ?? -1
        if (this.#pdfEnabled) return this.#pdfPage
        const spread = this.#spreads[this.#index]
        const section = spread?.center ?? (this.#side === 'left'
            ? spread?.left ?? spread?.right : spread?.right ?? spread?.left)
        return this.book.sections.indexOf(section)
    }
    #reportLocation(reason) {
        const region = this.pdfRegionLocation
        this.dispatchEvent(new CustomEvent('relocate', { detail:
            { reason, range: null, index: this.index,
                fraction: region ? region.panel / region.total : 0,
                size: region ? 1 / region.total : 1, pdfRegion: region,
                readingAction: ['page', 'navigation', 'viewport'].includes(reason) } }))
    }
    getSpreadOf(section) {
        const spreads = this.#spreads
        for (let index = 0; index < spreads.length; index++) {
            const { left, right, center } = spreads[index]
            if (left === section) return { index, side: 'left' }
            if (right === section) return { index, side: 'right' }
            if (center === section) return { index, side: 'center' }
        }
    }
    async goToSpread(index, side, reason) {
        if (index < 0 || index > this.#spreads.length - 1) return
        if (index === this.#index) {
            this.#side = side ?? this.#side
            this.#render()
            this.#reportLocation(reason)
            return
        }
        this.#index = index
        const spread = this.#spreads[index]
        if (spread.center) {
            const index = this.book.sections.indexOf(spread.center)
            const src = await spread.center?.load?.()
            await this.#showSpread({ center: { index, src } })
        } else {
            const indexL = this.book.sections.indexOf(spread.left)
            const indexR = this.book.sections.indexOf(spread.right)
            const srcL = await spread.left?.load?.()
            const srcR = await spread.right?.load?.()
            const left = { index: indexL, src: srcL }
            const right = { index: indexR, src: srcR }
            await this.#showSpread({ left, right, side })
        }
        this.#reportLocation(reason)
    }
    async select(target) {
        await this.goTo(target)
        // TODO
    }
    async goTo(target) {
        const { book } = this
        const resolved = await target
        const section = book.sections[resolved.index]
        if (!section) return
        if (this.#pdfEnabled) {
            const panel = restoredPanel(this.#pdfLayout, resolved.index, this.#pdfResume)
            const center = this.#pdfResume?.page === resolved.index &&
                this.#pdfResume?.signature === layoutSignature(this.#pdfLayout, resolved.index)
                ? this.#pdfResume.center : null
            this.#pdfResume = null
            return this.#showPdfPanel(resolved.index, panel, 'navigation', resolved.textAnchor ? resolved.anchor : null, center)
        }
        const { index, side } = this.getSpreadOf(section)
        await this.goToSpread(index, side, 'navigation')
    }
    async next() {
        if (this.#pdfEnabled && this.#pdfScroll) return this.panPdfView(0, this.getBoundingClientRect().height * .8)
        if (this.#pdfEnabled) return this.#movePdfPanel(1)
        const s = this.rtl ? this.#goLeft() : this.#goRight()
        if (s) this.#reportLocation('page')
        else return this.goToSpread(this.#index + 1, this.rtl ? 'right' : 'left', 'page')
    }
    async prev() {
        if (this.#pdfEnabled && this.#pdfScroll) return this.panPdfView(0, -this.getBoundingClientRect().height * .8)
        if (this.#pdfEnabled) return this.#movePdfPanel(-1)
        const s = this.rtl ? this.#goRight() : this.#goLeft()
        if (s) this.#reportLocation('page')
        else return this.goToSpread(this.#index - 1, this.rtl ? 'left' : 'right', 'page')
    }
    #movePdfPanel(direction) {
        if (this.#pdfBusy) return false
        if (normalizeDocumentDisplay(this.#pdfView.display).tapPan && this.#pdfPlan) {
            const plan=this.#pdfPlan, frame=this.#center
            const crop=frame.crop
            // Page-space vertical traversal after rotation; only consume a
            // page turn while there is an unread part of the current viewport.
            const top=plan.visible.y,bottom=top+plan.visible.height
            const target=pdfViewport({pageWidth:frame.width,pageHeight:frame.height,
                width:this.clientWidth,height:this.clientHeight,crop,view:this.#pdfView,
                center:panPdfViewport(plan,0,direction*this.clientHeight*.8)})
            if (Math.abs(target.visible.y-top)>.00001 && bottom>top) return this.panPdfView(0,direction*this.clientHeight*.8)
        }
        if (this.#pdfFallback) {
            const page = this.#pdfPage + direction
            if (page < 0 || page >= this.book.sections.length) return false
            return this.#showPdfPanel(page,
                direction > 0 ? 0 : readingRegions(this.#pdfLayout, page).length - 1, 'page')
        }
        const target = adjacentPanel(this.#pdfLayout, this.book.sections.length,
            this.#pdfPage, this.#pdfPanel, direction, this.book)
        return target ? this.#showPdfPanel(target.page, target.panel, 'page') : false
    }
    #adjacentSection(direction) {
        let index = this.index + direction
        while (index >= 0 && index < this.book.sections.length) {
            if (this.book.sections[index].linear !== 'no') return this.goTo({ index })
            index += direction
        }
    }
    prevSection() { return this.#adjacentSection(-1) }
    nextSection() { return this.#adjacentSection(1) }
    getContents() {
        if (this.#pdfScroll) return this.#pdfScroll.getContents()
        return [this.#left, this.#center, this.#right].filter(frame => frame && !frame.blank)
            .map(frame => ({ doc: frame.iframe.contentDocument, index: frame.index }))
    }
    destroy() {
        this.#destroyed = true
        clearInterval(this.#autoTimer)
        this.#pdfGeneration++
        this.#cancelPdfDetail()
        this.#pdfScroll?.destroy()
        this.#releasePdfUrl()
        this.#observer.unobserve(this)
        this.book?.releasePageResources?.()
    }
}

customElements.define('foliate-fxl', FixedLayout)
