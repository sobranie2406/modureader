const EPUB_NS = 'http://www.idpf.org/2007/ops'

// Kindle conversion can strip the epub: prefix but retain its type value.
export function normalizeKF8Footnotes(doc) {
    for (const el of doc.querySelectorAll('aside[type], a[type]')) {
        if (el.hasAttributeNS(EPUB_NS, 'type') || el.hasAttribute('epub:type')) continue
        const allowed = el.localName === 'aside'
            ? ['footnote', 'endnote', 'note', 'rearnote'] : ['noteref', 'backlink']
        const types = el.getAttribute('type').split(/\s+/).filter(type => allowed.includes(type))
        if (!types.length) continue
        el.setAttributeNS(EPUB_NS, 'epub:type', types.join(' '))
        // Roles also survive KF8's malformed-XHTML -> HTML fallback.
        const role = types[0] === 'note' ? 'note'
            : `doc-${types[0] === 'rearnote' ? 'endnote' : types[0]}`
        const roles = new Set((el.getAttribute('role') ?? '').split(/\s+/).filter(Boolean))
        roles.add(role)
        el.setAttribute('role', [...roles].join(' '))
        // The popup extracts the aside's contents, so it remains visible there.
        if (el.localName === 'aside') el.style.setProperty('display', 'none', 'important')
        // Some conversions retain explicit note text but point to a duplicate/wrong ID.
        if (types.includes('noteref')) for (const img of el.querySelectorAll('img[zy-footnote]')) {
            const text = img.getAttribute('zy-footnote')
            if (text.trim() && text === img.getAttribute('alt'))
                img.setAttribute('data-modu-mobi-footnote', text)
        }
    }
    return doc
}

const legacyNote = el => el?.matches('ol[width="0pt"]')
    && el.children.length === 1
    && el.firstElementChild.matches('li[value="1"][height="0pt"][width="0pt"]')
    && [...el.childNodes].every(node => node === el.firstElementChild
        || node.nodeType === 8 || (node.nodeType === 3 && !node.textContent.trim()))
    && el.textContent.trim()
    && !el.querySelector('img, a, ol, ul, table')

const previousElement = el => {
    let node = el.previousSibling
    while (node && (node.nodeType === 8 || (node.nodeType === 3 && !node.textContent.trim())))
        node = node.previousSibling
    return node?.nodeType === 1 ? node : null
}

// ponytail: only recover the legacy singleton-list + superscript-icon pattern;
// ambiguous or differently converted MOBIs keep their original visible text.
export function restoreMOBI6Footnotes(doc) {
    for (const paragraph of doc.querySelectorAll('p')) {
        const notes = []
        for (let el = previousElement(paragraph); el?.localName === 'ol'; el = previousElement(el))
            notes.unshift(el)
        if (!notes.length || !notes.every(legacyNote)) continue
        const icons = [...paragraph.querySelectorAll('sup img')]
        if (icons.length !== notes.length || !icons.every(img => {
            const sup = img.closest('sup')
            const width = Number(img.getAttribute('width'))
            const height = Number(img.getAttribute('height'))
            return /^\d+$/.test(img.getAttribute('recindex') ?? '')
                && img.getAttribute('align') === 'baseline'
                && width >= 8 && width <= 16 && height === width
                && !img.closest('a') && !sup.textContent.trim()
                && sup.querySelectorAll('img').length === 1
        })) continue
        // Change attributes only: node order and text offsets used by CFIs stay intact.
        icons.forEach((img, i) => {
            img.setAttribute('data-modu-mobi-footnote', notes[i].textContent.trim())
            img.setAttribute('role', 'doc-noteref')
            notes[i].setAttribute('role', 'doc-footnote')
            notes[i].style.setProperty('display', 'none', 'important')
        })
    }
    return doc
}
