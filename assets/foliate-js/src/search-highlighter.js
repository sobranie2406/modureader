const NAME = 'modu-search-match'
const COLOR = 'rgba(47, 143, 255, 0.42)'
const SVG_NS = 'http://www.w3.org/2000/svg'

// Search ranges belong to the chapter document, not the parent paginator.
// Native text highlights follow line breaks, columns, font loads and zoom
// without converting coordinates or modifying the book's text/CFI structure.
export class SearchHighlighter {
    #doc
    #ranges = new Map()
    #highlight
    #style
    #svg
    #frame
    #observer
    #schedule = () => {
        if (this.#frame != null || !this.#svg) return
        this.#frame = this.#doc.defaultView.requestAnimationFrame(() => {
            this.#frame = null
            this.redraw()
        })
    }
    constructor(doc) { this.#doc = doc }
    add(key, range) {
        if (!range || range.collapsed || range.startContainer.ownerDocument !== this.#doc) return
        this.remove(key)
        const win = this.#doc.defaultView
        if (!this.#ranges.size) {
            if (win?.CSS?.highlights && typeof win.Highlight === 'function') {
                this.#highlight = new win.Highlight()
                this.#style = this.#doc.createElementNS('http://www.w3.org/1999/xhtml', 'style')
                this.#style.textContent = `::highlight(${NAME}) { background-color: ${COLOR}; }`
                ;(this.#doc.head ?? this.#doc.documentElement).append(this.#style)
                win.CSS.highlights.set(NAME, this.#highlight)
            } else {
                // Older WebViews: paint only text-node fragments, in the SAME
                // document coordinate space. No parent-frame padding/scale math.
                this.#svg = this.#doc.createElementNS(SVG_NS, 'svg')
                this.#svg.setAttribute('aria-hidden', 'true')
                this.#svg.setAttribute('data-modu-search-overlay', '')
                this.#svg.style.cssText = 'position:fixed!important;left:0!important;top:0!important;'
                    + 'width:100%!important;height:100%!important;overflow:visible!important;'
                    + 'pointer-events:none!important;z-index:2147483646!important;'
                this.#doc.documentElement.append(this.#svg)
                win?.addEventListener('resize', this.#schedule)
                this.#doc.addEventListener('scroll', this.#schedule, true)
                this.#doc.fonts?.addEventListener('loadingdone', this.#schedule)
                if (win?.ResizeObserver) {
                    this.#observer = new win.ResizeObserver(this.#schedule)
                    this.#observer.observe(this.#doc.body)
                }
            }
        }
        this.#ranges.set(key, range)
        if (this.#highlight) this.#highlight.add(range)
        else this.#schedule()
    }
    remove(key) {
        const range = this.#ranges.get(key)
        if (!range) return
        this.#highlight?.delete(range)
        this.#ranges.delete(key)
        if (!this.#ranges.size) this.clear()
        else this.#schedule()
    }
    clear() {
        const win = this.#doc.defaultView
        if (this.#highlight && win?.CSS?.highlights?.get(NAME) === this.#highlight)
            win.CSS.highlights.delete(NAME)
        this.#highlight = null
        this.#style?.remove()
        this.#style = null
        this.#svg?.remove()
        this.#svg = null
        if (this.#frame != null) win?.cancelAnimationFrame(this.#frame)
        this.#frame = null
        this.#observer?.disconnect()
        this.#observer = null
        win?.removeEventListener('resize', this.#schedule)
        this.#doc.removeEventListener('scroll', this.#schedule, true)
        this.#doc.fonts?.removeEventListener('loadingdone', this.#schedule)
        this.#ranges.clear()
    }
    redraw() {
        if (!this.#svg) return // Native highlights are laid out by the engine.
        const box = this.#svg.getBoundingClientRect()
        if (!box.width || !box.height) return
        this.#svg.setAttribute('viewBox', `0 0 ${box.width} ${box.height}`)
        const fragment = this.#doc.createDocumentFragment()
        for (const range of this.#ranges.values()) {
            const ancestor = range.commonAncestorContainer
            const walker = this.#doc.createTreeWalker(ancestor, 4 | 8) // text / CDATA
            let node = ancestor.nodeType === 3 || ancestor.nodeType === 4
                ? ancestor : walker.nextNode()
            for (; node; node = walker.nextNode()) {
                if (!range.intersectsNode(node)) continue
                const part = this.#doc.createRange()
                part.selectNodeContents(node)
                if (part.compareBoundaryPoints(0, range) < 0)
                    part.setStart(range.startContainer, range.startOffset)
                if (part.compareBoundaryPoints(2, range) > 0)
                    part.setEnd(range.endContainer, range.endOffset)
                for (const rect of part.getClientRects()) {
                    if (!rect.width || !rect.height || part.collapsed) continue
                    const el = this.#doc.createElementNS(SVG_NS, 'rect')
                    el.setAttribute('x', rect.left - box.left)
                    el.setAttribute('y', rect.top - box.top)
                    el.setAttribute('width', rect.width)
                    el.setAttribute('height', rect.height)
                    el.setAttribute('fill', COLOR)
                    fragment.append(el)
                }
            }
        }
        this.#svg.replaceChildren(fragment)
    }
}
