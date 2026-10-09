// Accept only explicit QQ Reader notes or markers recovered by the MOBI loader.
// Ordinary image descriptions must remain image previews.
export function imageFootnoteText(img) {
    if (!img?.matches?.('img')) return null
    const text = img.getAttribute('data-modu-mobi-footnote')
        ?? (img.matches('.qqreader-footnote') ? img.getAttribute('alt') : null)
    return text?.trim() ? text : null
}

// Render only the note, not another copy of the source chapter and its assets.
// Keep the source DOM untouched so existing CFIs and TTS ranges remain valid.
export function createImageFootnoteBook(img) {
    const text = imageFootnoteText(img)
    if (text === null) return null
    const doc = img.ownerDocument.implementation.createHTMLDocument('')
    const meta = doc.createElement('meta')
    meta.setAttribute('charset', 'utf-8')
    doc.head.prepend(meta)
    doc.documentElement.lang = img.ownerDocument.documentElement.lang
    const note = doc.createElement('aside')
    note.setAttribute('role', 'doc-footnote')
    const paragraph = doc.createElement('p')
    paragraph.style.whiteSpace = 'pre-wrap'
    // alt is plain text, including decoded entities; never interpret it as HTML.
    paragraph.textContent = text
    note.append(paragraph)
    doc.body.append(note)
    const blob = new Blob([doc.documentElement.outerHTML], { type: 'text/html;charset=utf-8' })
    let url = null
    const unload = () => {
        if (url !== null) URL.revokeObjectURL(url)
        url = null
    }
    return {
        metadata: { language: doc.documentElement.lang },
        sections: [{
            id: 'modu-image-footnote', size: blob.size,
            load: () => url ??= URL.createObjectURL(blob),
            unload,
            createDocument: () => doc.cloneNode(true),
        }],
        destroy: unload,
    }
}
