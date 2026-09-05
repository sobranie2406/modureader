// Book content is untrusted. Reader-owned scripts run in the parent document.
export const sanitizeBookDocument = (doc, allowScript = false) => {
    if (allowScript) return doc
    for (const el of doc.querySelectorAll('script, iframe, frame, object, embed, base, foreignObject, animate, set')) el.remove()
    for (const el of doc.querySelectorAll('*')) {
        for (const attr of Array.from(el.attributes)) {
            const name = attr.name.toLowerCase()
            const value = attr.value.replace(/[\u0000-\u0020]/g, '').toLowerCase()
            const safeInlineImage = name === 'src' && el.localName === 'img'
                && /^data:image\/(png|jpeg|gif|webp|bmp|avif);/.test(value)
            if (name.startsWith('on') || name === 'srcdoc'
                || (['href', 'xlink:href', 'src', 'action', 'formaction'].includes(name)
                    && /^(javascript|vbscript|data):/.test(value) && !safeInlineImage)) {
                el.removeAttribute(attr.name)
            }
        }
    }
    for (const meta of doc.querySelectorAll('meta[http-equiv]')) {
        if (['refresh', 'content-security-policy'].includes(meta.getAttribute('http-equiv').toLowerCase())) meta.remove()
    }
    if (doc.head) {
        const csp = doc.createElementNS('http://www.w3.org/1999/xhtml', 'meta')
        csp.setAttribute('http-equiv', 'Content-Security-Policy')
        csp.setAttribute('content', "script-src 'none'; object-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'")
        doc.head.prepend(csp)
    }
    return doc
}
