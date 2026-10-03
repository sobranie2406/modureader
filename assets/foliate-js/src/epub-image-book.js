import { createEpubImageSource } from './epub-image-source.js'

// Opt-in display adapter. Never change the original spine, DOM node order or
// source archive. Mixed/text sections retain their HTML, not a screenshot.
export function createEpubImageBook(book) {
    const source = createEpubImageSource(book), readingSource = createEpubImageSource(book), entries = new Map()
    const nativeTextPages = new Set()
    let generation = 0
    const release = entry => {
        URL.revokeObjectURL(entry.url)
        if (entry.image) URL.revokeObjectURL(entry.image)
        entry.release()
    }
    const load = async index => {
        const version = generation
        if (entries.has(index)) {
            const item = entries.get(index); entries.delete(index); entries.set(index, item)
            return item.url
        }
        const info = await source.info(index)
        if (!info.imageOnly) nativeTextPages.add(index)
        const lease = await book.sections[index].loadImageDocument()
        let image, url, retained = false
        try {
            const html = await (await fetch(lease.src)).text()
            const doc = new DOMParser().parseFromString(html, 'text/html')
            doc.querySelector('meta[name="viewport"]')?.remove()
            const meta = doc.createElement('meta'); meta.name = 'viewport'
            meta.content = `width=${info.width},height=${info.height}`; doc.head.append(meta)
            doc.documentElement.dataset.documentImage = String(info.imageOnly)
            const style = doc.createElement('style')
            style.textContent = `html{width:${info.width}px!important;overflow:hidden!important} body{min-height:0!important}`
            if (info.imageOnly) {
                const result = await source.render({page:index, width:1000, height:1500})
                image = URL.createObjectURL(result.blob)
                // Keep all original nodes for source CFIs; only hide their paint.
                style.textContent += 'body img,body svg{visibility:hidden!important}[data-document-base]{visibility:visible!important;position:absolute!important;inset:0!important;margin:0!important;padding:0!important;border:0!important;max-width:none!important;max-height:none!important}'
                const img = doc.createElement('img'); img.dataset.documentBase = ''; img.src = image
                img.style.width = `${info.width}px`; img.style.height = `${info.height}px`
                img.alt = ''; doc.body.append(img)
            }
            doc.head.append(style)
            url = URL.createObjectURL(new Blob([doc.documentElement.outerHTML], {type:'text/html'}))
            if (version !== generation) throw new DOMException('Reader closed', 'AbortError')
            entries.set(index, {url, image, release:lease.release}); retained = true
            // Seven visible frames plus candidates. Evict only after the new
            // document is complete; each lease is separate from the real book.
            while (entries.size > 12) {
                const key = entries.keys().next().value
                release(entries.get(key)); entries.delete(key)
            }
            return url
        } finally {
            if (!retained) { if (url) URL.revokeObjectURL(url); if (image) URL.revokeObjectURL(image); lease.release() }
        }
    }
    return {
        ...book, rendition:{...book.rendition,layout:'pre-paginated',spread:'none'},
        sections:book.sections.map((section,index)=>({...section,load:()=>load(index)})),
        readingRegionRenderer:readingSource, nativeTextPages,
        disposeImageBook() {
            generation++; source.clear(); readingSource.clear()
            for (const item of entries.values()) release(item)
            entries.clear()
        },
    }
}
