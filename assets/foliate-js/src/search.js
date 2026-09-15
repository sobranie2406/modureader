// length for context in excerpts
const CONTEXT_LENGTH = 50

const normalizeWhitespace = str => str.replace(/\s+/g, ' ')

const makeExcerpt = (strs, { startIndex, startOffset, endIndex, endOffset }) => {
    const start = strs[startIndex]
    const end = strs[endIndex]
    const match = startIndex === endIndex
        ? start.slice(startOffset, endOffset)
        : start.slice(startOffset)
            + strs.slice(startIndex + 1, endIndex).join('')
            + end.slice(0, endOffset)
    const trimmedStart = normalizeWhitespace(start.slice(0, startOffset)).trimStart()
    const trimmedEnd = normalizeWhitespace(end.slice(endOffset)).trimEnd()
    const ellipsisPre = trimmedStart.length < CONTEXT_LENGTH ? '' : '…'
    const ellipsisPost = trimmedEnd.length < CONTEXT_LENGTH ? '' : '…'
    const pre = `${ellipsisPre}${trimmedStart.slice(-CONTEXT_LENGTH)}`
    const post = `${trimmedEnd.slice(0, CONTEXT_LENGTH)}${ellipsisPost}`
    return { pre, match, post }
}

// Translate offsets in the original, joined UTF-16 text back to DOM nodes.
// Start/end have separate boundary rules: an exclusive end at a node boundary
// belongs to the preceding node. Never reuse the previous match's end cursor
// as the next start (matches may overlap).
const rangeMapper = strs => {
    let length = 0
    const nodes = strs.flatMap((str, index) => {
        const start = length
        length += str.length
        return str.length ? [{ index, start, end: length }] : []
    })
    const locate = (offset, end) => {
        let lo = 0, hi = nodes.length - 1
        while (lo < hi) {
            const mid = (lo + hi) >>> 1
            if (end ? nodes[mid].end < offset : nodes[mid].end <= offset) lo = mid + 1
            else hi = mid
        }
        return nodes[lo]
    }
    return (start, end) => {
        const first = locate(start, false), last = locate(end, true)
        const range = { startIndex: first.index, startOffset: start - first.start,
            endIndex: last.index, endOffset: end - last.start }
        return { range, excerpt: makeExcerpt(strs, range) }
    }
}

const simpleSearch = function* (strs, query, options = {}) {
    if (!query || !strs.some(str => str.length)) return
    const result = rangeMapper(strs)
    // Match against the original text, not a lowercased copy: case conversion
    // can change UTF-16 length (for example İ), shifting every following hit.
    const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
    const pattern = new RegExp(escaped, options.sensitivity === 'variant' ? 'gu' : 'giu')
    const text = strs.join('')
    let match
    while ((match = pattern.exec(text))) {
        yield result(match.index, match.index + match[0].length)
        // Allow overlapping hits, advancing by a full code point.
        pattern.lastIndex = match.index + (text.codePointAt(match.index) > 0xffff ? 2 : 1)
    }
}

const segmenterSearch = function* (strs, query, options = {}) {
    if (!query || !strs.some(str => str.length)) return
    const { locales = 'en', granularity = 'word', sensitivity = 'base' } = options
    let segmenter, collator
    try {
        segmenter = new Intl.Segmenter(locales, { usage: 'search', granularity })
        collator = new Intl.Collator(locales, { sensitivity })
    } catch (e) {
        console.warn(e)
        segmenter = new Intl.Segmenter('en', { usage: 'search', granularity })
        collator = new Intl.Collator('en', { sensitivity })
    }
    const segments = function* (text) {
        let whitespace
        for (const { index, segment } of segmenter.segment(text)) {
            if (!/[^\p{Format}]/u.test(segment)) continue
            const end = index + segment.length
            if (/^\s+$/u.test(segment)) {
                if (whitespace) whitespace.end = end
                else whitespace = { start: index, end, text: ' ' }
            } else {
                if (whitespace) { yield whitespace; whitespace = null }
                yield { start: index, end, text: segment }
            }
        }
        if (whitespace) yield whitespace
    }
    const needle = Array.from(segments(query), part => part.text)
    if (!needle.length) return
    const normalizedQuery = needle.join('')
    const result = rangeMapper(strs)
    const window = []
    // Segment joined text so inline tags do not split words or graphemes.
    // Keep original offsets even when whitespace is collapsed for comparison.
    for (const part of segments(strs.join(''))) {
        window.push(part)
        if (window.length < needle.length) continue
        if (collator.compare(normalizedQuery, window.map(part => part.text).join('')) === 0)
            yield result(window[0].start, part.end)
        window.shift()
    }
}

export const search = (strs, query, options = {}) => {
    const { granularity = 'grapheme', sensitivity = 'base' } = options
    if (!Intl?.Segmenter || granularity === 'grapheme'
    && (sensitivity === 'variant' || sensitivity === 'accent'))
        return simpleSearch(strs, query, options)
    return segmenterSearch(strs, query, { ...options, granularity, sensitivity })
}

export const searchMatcher = (textWalker, opts) => {
    const { defaultLocale, matchCase, matchDiacritics, matchWholeWords } = opts
    return function* (doc, query) {
        const iter = textWalker(doc, function* (strs, makeRange) {
            for (const result of search(strs, query, {
                locales: doc.body.lang || doc.documentElement.lang || defaultLocale || 'en',
                granularity: matchWholeWords ? 'word' : 'grapheme',
                sensitivity: matchDiacritics && matchCase ? 'variant'
                : matchDiacritics && !matchCase ? 'accent'
                : !matchDiacritics && matchCase ? 'case'
                : 'base',
            })) {
                const { startIndex, startOffset, endIndex, endOffset } = result.range
                result.range = makeRange(startIndex, startOffset, endIndex, endOffset)
                yield result
            }
        })
        for (const result of iter) yield result
    }
}
