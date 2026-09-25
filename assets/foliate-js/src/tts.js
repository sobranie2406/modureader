const blockTags = new Set([
    'article', 'aside', 'audio', 'blockquote', 'caption',
    'details', 'dialog', 'div', 'dl', 'dt', 'dd',
    'figure', 'footer', 'form', 'figcaption',
    'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hgroup', 'hr', 'li',
    'main', 'math', 'nav', 'ol', 'p', 'pre', 'section', 'tr',
])

function rangeIsEmpty(range, shouldSkipTextNode) {
    // Separators have no speech. Exclude them from the cursor in BOTH
    // directions, otherwise Previous lands on one and playback skips forward.
    return range.collapsed || /^[\p{P}\p{Z}\p{Cc}\p{Cf}\s⋯]*$/u.test(getRangeText(range, shouldSkipTextNode))
}

const quoteChars = new Set(['"', "'", '“', '”', '‘', '’'])

const noteTypes = new Set(['noteref', 'backlink', 'pagebreak', 'footnote',
    'footnotes', 'endnote', 'endnotes', 'rearnote', 'rearnotes', 'note'])
const typesOf = el => (el.getAttributeNS?.('http://www.idpf.org/2007/ops', 'type')
    ?? el.getAttribute('epub:type') ?? '').split(/\s+/)
const explicitNote = el => typesOf(el).some(type => noteTypes.has(type))
    || (el.getAttribute('role') ?? '').split(/\s+/)
        .some(role => noteTypes.has(role.replace(/^doc-/, '')))
    || [...el.classList].some(name => /^(?:footnotes?|endnotes?|rearnotes?|noteref|footnote-ref|footnote-backref)(?:[-_]\d+)?$/i.test(name))

const createTextFilter = doc => {
    const excluded = new WeakSet()
    // Legacy books often use an ordinary numbered link instead of epub:type.
    // Require note-specific evidence; TOC links and ordinary superscripts stay.
    for (const link of doc.querySelectorAll('a[href]')) {
        const href = link.getAttribute('href')
        const backlink = typesOf(link).includes('backlink')
            || (link.getAttribute('role') ?? '').split(/\s+/).includes('doc-backlink')
            || link.classList.contains('footnote-backref')
        if (backlink) {
            excluded.add(link)
            continue // Its target is BODY text, not a note to suppress.
        }
        let target = null
        const hash = href.indexOf('#')
        if (hash === 0) {
            try { target = doc.getElementById(decodeURIComponent(href.slice(1))) } catch (_) {}
        }
        const marker = /^(?:\[?\d+\]?|[①-⑳*†‡]+|注\d*)$/.test(link.textContent.trim())
        const noteTarget = /(?:^|[/#])(?:footnotes?|endnotes?|rearnotes?|notes?|fn)[-_.\d]/i.test(href)
        const knownTarget = target && explicitNote(target)
            && !typesOf(target).includes('noteref')
            && !(target.getAttribute('role') ?? '').split(/\s+/).includes('doc-noteref')
        if (!explicitNote(link) && !knownTarget && !(marker && noteTarget)) continue
        excluded.add(link)
        if (target) {
            // A backlink anchor at the start of a note usually owns no text;
            // exclude its paragraph/list item, not the surrounding chapter.
            const block = target.matches('a,span,sup')
                ? target.closest('p,li,aside') : target
            if (block && block !== doc.body) excluded.add(block)
        }
    }
    const cache = new WeakMap()
    const skipElement = el => {
        if (!el) return false
        if (cache.has(el)) return cache.get(el)
        const isRoot = el === doc.body || el === doc.documentElement
        const ownHidden = !isRoot && (el.hidden || el.getAttribute('aria-hidden') === 'true'
            || el.style?.display === 'none' || el.style?.visibility === 'hidden'
            || doc.defaultView?.getComputedStyle(el).display === 'none')
        const skip = excluded.has(el) || explicitNote(el) || ownHidden
            || ['script', 'style', 'template', 'rt', 'rp'].includes(el.localName)
            || skipElement(el.parentElement)
        cache.set(el, skip)
        return skip
    }
    return node => skipElement(node.parentElement)
}

const getRangeText = (range, shouldSkipTextNode) => {
    // Read the ORIGINAL nodes: cloneContents() loses the ancestor's note/hidden
    // attributes when both boundaries fall inside it, and loses computed CSS.
    const doc = range.startContainer.ownerDocument
    const root = range.commonAncestorContainer
    const walker = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT)
    let text = ''
    for (let node = root.nodeType === 3 ? root : walker.nextNode(); node; node = walker.nextNode()) {
        if (!range.intersectsNode(node) || shouldSkipTextNode(node)) continue
        const start = node === range.startContainer ? range.startOffset : 0
        const end = node === range.endContainer ? range.endOffset : node.length
        text += node.textContent.slice(start, end)
    }
    return text
}

const findBlockAncestor = node => {
    let el = node.parentElement
    while (el && !blockTags.has(el.tagName?.toLowerCase?.())) {
        el = el.parentElement
    }
    return el ?? node.ownerDocument?.body ?? null
}

const isSentenceTerminator = (char, nextChar) => {
    if (char === '.') {
        if (!nextChar) return true
        if (quoteChars.has(nextChar)) return true
        if (/\s/.test(nextChar)) return true
        return false
    }
    return char === '!' || char === '?' || char === '。' || char === '！' || char === '？'
}

const advancePastQuotes = (text, index) => {
    let end = index
    while (end < text.length && quoteChars.has(text[end])) end++
    return end
}

function* getBlocks(doc, shouldSkipTextNode) {
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT)
    let startNode = null
    let startOffset = 0
    let currentBlock = null
    let lastNode = null
    let lastOffset = 0

    const flushRange = () => {
        if (!startNode || !lastNode) return null
        const range = doc.createRange()
        range.setStart(startNode, startOffset)
        range.setEnd(lastNode, lastOffset)
        startNode = null
        startOffset = 0
        currentBlock = null
        lastNode = null
        lastOffset = 0
        if (rangeIsEmpty(range, shouldSkipTextNode)) return null
        return range
    }

    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (!node.textContent) continue
        if (shouldSkipTextNode(node)) continue

        const block = findBlockAncestor(node)

        if (!startNode) {
            startNode = node
            startOffset = 0
            currentBlock = block
        } else if (block !== currentBlock) {
            const range = flushRange()
            if (range) yield range
            startNode = node
            startOffset = 0
            currentBlock = block
        }

        const text = node.textContent
        let index = 0
        while (index < text.length) {
            const char = text[index]
            const nextChar = text[index + 1]
            if (isSentenceTerminator(char, nextChar)) {
                const endOffset = advancePastQuotes(text, index + 1)
                const range = doc.createRange()
                range.setStart(startNode, startOffset)
                range.setEnd(node, endOffset)
                if (!rangeIsEmpty(range, shouldSkipTextNode)) yield range
                startNode = node
                startOffset = endOffset
                lastNode = node
                lastOffset = endOffset
                index = endOffset
                continue
            }
            index += 1
        }

        lastNode = node
        lastOffset = text.length

        if (startNode === node && startOffset === text.length) {
            startNode = null
            startOffset = 0
            currentBlock = null
        }
    }

    const remaining = flushRange()
    if (remaining) yield remaining
}

class ListIterator {
    #arr = []
    #iter
    #index = -1
    #f
    constructor(iter, f = x => x) {
        this.#iter = iter
        this.#f = f
    }
    current() {
        if (this.#arr[this.#index]) return this.#f(this.#arr[this.#index])
    }
    first() {
        const newIndex = 0
        if (this.#arr[newIndex]) {
            this.#index = newIndex
            return this.#f(this.#arr[newIndex])
        }
    }
    last() {
        for (const value of this.#iter) this.#arr.push(value)
        const newIndex = this.#arr.length - 1
        if (this.#arr[newIndex]) {
            this.#index = newIndex
            return this.#f(this.#arr[newIndex])
        }
    }
    prev() {
        const newIndex = this.#index - 1
        if (this.#arr[newIndex]) {
            this.#index = newIndex
            return this.#f(this.#arr[newIndex])
        }
    }
    next() {
        const newIndex = this.#index + 1
        if (this.#arr[newIndex]) {
            this.#index = newIndex
            return this.#f(this.#arr[newIndex])
        }
        while (true) {
            const { done, value } = this.#iter.next()
            if (done) break
            this.#arr.push(value)
            if (this.#arr[newIndex]) {
                this.#index = newIndex
                return this.#f(this.#arr[newIndex])
            }
        }
    }
    #ensure(index) {
        while (this.#arr[index] == null) {
            const { done, value } = this.#iter.next()
            if (done) break
            this.#arr.push(value)
            if (this.#arr.length - 1 >= index) break
        }
        return this.#arr[index]
    }
    prepare() {
        const newIndex = this.#index + 1
        if (this.#arr[newIndex]) return this.#f(this.#arr[newIndex])
        while (true) {
            const { done, value } = this.#iter.next()
            if (done) break
            this.#arr.push(value)
            if (this.#arr[newIndex]) return this.#f(this.#arr[newIndex])
        }
    }
    peek(count = 1, offset = 1) {
        if (count <= 0) return []
        const startIndex = Math.max(this.#index + offset, 0)
        const results = []
        const endIndex = startIndex + count
        for (let idx = startIndex; idx < endIndex; idx++) {
            const value = this.#arr[idx] ?? this.#ensure(idx)
            if (!value) break
            results.push(this.#f(value))
        }
        return results
    }
    find(f) {
        const index = this.#arr.findIndex(x => f(x))
        if (index > -1) {
            this.#index = index
            return this.#f(this.#arr[index])
        }
        while (true) {
            const { done, value } = this.#iter.next()
            if (done) break
            this.#arr.push(value)
            if (f(value)) {
                this.#index = this.#arr.length - 1
                return this.#f(value)
            }
        }
    }
}

export class TTS {
    #list
    #lastMark
    #getCfi
    #textFilter
    #partial
    constructor(doc, textWalker, highlight, getCfi) {
        this.doc = doc
        this.highlight = highlight
        this.#getCfi = getCfi
        const shouldSkipTextNode = createTextFilter(doc)
        this.#textFilter = shouldSkipTextNode
        this.#list = new ListIterator(getBlocks(doc, shouldSkipTextNode), range => {
            return [getRangeText(range, shouldSkipTextNode), range]
        })
    }

    #getText(text, getNode) {
        if (!text) return ''
        if (!getNode) return text
        const tempElement = document.createElement('div')
        tempElement.innerHTML = text
        let node = getNode(tempElement)?.previousSibling
        while (node) {
            const next = node.previousSibling ?? node.parentNode?.previousSibling
            node.parentNode.removeChild(node)
            node = next
        }
        return tempElement.textContent
    }

    #ensureCurrentEntry() {
        const current = this.#list.current()
        if (current) return current
        return this.#list.first() ?? this.#list.next()
    }

    #locationOf(range) {
        // CFI is optional presentation metadata, not a prerequisite for speech.
        // Do not let a detached/relaid-out range discard an otherwise valid
        // sentence or abort the whole producer batch.
        try { return this.#getCfi?.(range.cloneRange()) ?? null }
        catch (_) {
            console.warn('TTS location unavailable; retaining speech text')
            return null
        }
    }

    #resultFrom(entry, { highlight = false } = {}) {
        if (!entry) return null
        let [text, range] = entry
        if (range === this.#partial?.original) {
            range = this.#partial.range
            text = getRangeText(range, this.#textFilter)
        }
        if (!text || !range) return null
        const plainText = this.#getText(text)
        let cfi = null
        if (highlight && this.highlight && range.cloneRange) {
            try { cfi = this.highlight(range.cloneRange()) ?? null }
            catch (_) {
                console.warn('TTS presentation unavailable; continuing speech')
            }
        }
        if (!cfi && this.#getCfi && range.cloneRange) {
            cfi = this.#locationOf(range)
        }
        return { text: plainText, cfi }
    }

    start() {
        this.#partial = null
        this.#lastMark = null
        const entry = this.#list.first()
        if (!entry) return this.next(true)
        return this.#resultFrom(entry, { highlight: true })?.text
    }

    end() {
        this.#partial = null
        this.#lastMark = null
        const entry = this.#list.last()
        if (!entry) return this.next()
        return this.#resultFrom(entry, { highlight: true })?.text
    }

    resume() {
        const entry = this.#list.current()
        if (!entry) return this.next()
        return this.#resultFrom(entry)?.text
    }

    prev(paused) {
        this.#partial = null
        this.#lastMark = null
        const entry = this.#list.prev()
        return this.#resultFrom(entry, { highlight: paused })?.text
    }

    next(paused) {
        this.#partial = null
        this.#lastMark = null
        const entry = this.#list.next()
        return this.#resultFrom(entry, { highlight: paused })?.text
    }

    // get next text without moving the iterator
    prepare() {
        const entry = this.#list.prepare()
        return this.#resultFrom(entry)?.text
    }

    from(range, { exactStart = false } = {}) {
        this.#lastMark = null
        this.#partial = null
        if (range.startContainer.ownerDocument !== this.doc) return null
        const entry = this.#list.find(range_ =>
            range.compareBoundaryPoints(Range.END_TO_START, range_) <= 0)
        if (exactStart && entry?.[1] && range.compareBoundaryPoints(Range.START_TO_START, entry[1]) > 0) {
            const tail = entry[1].cloneRange()
            tail.setStart(range.startContainer, range.startOffset)
            if (rangeIsEmpty(tail, this.#textFilter)) return this.next(true)
            this.#partial = { original: entry[1], range: tail }
        }
        return this.#resultFrom(entry, { highlight: true })?.text
    }

    currentDetail() {
        const entry = this.#ensureCurrentEntry()
        return this.#resultFrom(entry)
    }

    collectDetails(count = 1, { includeCurrent = false, offset = 1 } = {}) {
        if (!Number.isFinite(count) || count <= 0) return []
        const details = []
        if (includeCurrent) {
            const entry = this.#ensureCurrentEntry()
            const detail = this.#resultFrom(entry)
            if (detail) details.push(detail)
        }
        const needed = count - details.length
        if (needed <= 0) return details
        const entries = this.#list.peek(needed, offset)
        for (const entry of entries) {
            const detail = this.#resultFrom(entry)
            if (detail) details.push(detail)
        }
        return details
    }

    highlightCfi(cfi) {
        if (!cfi) return null
        // Audio presentation may complete late after resume/chapter navigation.
        // It must never seek the speech iterator backwards (or consume ahead).
        const entry = this.#list.current()
        const range = this.#partial && entry?.[1] === this.#partial.original ? this.#partial.range : entry?.[1]
        if (!range || this.#locationOf(range) !== cfi) return null
        return this.#resultFrom(entry, { highlight: true })
    }
}
