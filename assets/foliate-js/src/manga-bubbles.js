// Each frame is the uncropped source page. The reader scales and clips the
// frame itself, so a source-relative layer follows both spread and scroll views.
export function drawMangaBubbles(doc, bubbles) {
    if (!bubbles.length) return null
    const host = doc.createElement('div')
    host.style.cssText = 'all:initial;position:fixed!important;inset:0!important;top:0!important;left:0!important;width:100%!important;height:100%!important;pointer-events:none!important;z-index:2147483646!important'
    host.dataset.mangaLayer = ''
    doc.documentElement.append(host)
    const root = host.attachShadow({mode: 'closed'})
    const style = doc.createElement('style')
    style.textContent = 'button{all:initial;box-sizing:border-box;position:absolute;pointer-events:auto;cursor:pointer;text-align:center;overflow:hidden;overflow-wrap:anywhere;word-break:break-word;line-height:1.12;font-family:sans-serif;color:#191919;border-radius:8%;direction:ltr}button:focus-visible{outline:2px solid #397bee}button[aria-pressed=true]{background:white}'
    root.append(style)
    for (const {rect, masks, tapToReveal, original, translation} of bubbles) {
        const covers = []
        if (translation && !tapToReveal) for (const [x,y,w,h] of masks) {
            const cover = doc.createElement('span')
            Object.assign(cover.style, {position:'absolute', left:x*100+'%', top:y*100+'%', width:w*100+'%', height:h*100+'%', background:'white', borderRadius:'8%'})
            root.append(cover)
            covers.push(cover)
        }
        const btn = doc.createElement('button')
        btn.type = 'button'
        const [x, y, w, h] = rect
        Object.assign(btn.style, {left:x*100+'%', top:y*100+'%', width:w*100+'%', height:h*100+'%'})
        const label = translation || original
        btn.setAttribute('aria-label', label)
        root.append(btn)
        const display = visible => {
            btn.setAttribute('aria-pressed', String(visible))
            for (const cover of covers) cover.hidden = !visible
            btn.textContent = visible ? label : ''
            if (!visible) return
            let low = 1, high = Math.max(1, Math.min(96, btn.clientHeight))
            while (high - low >= 1) {
                const size = Math.ceil((low + high) / 2)
                btn.style.fontSize = size+'px'
                if (btn.scrollHeight > btn.clientHeight || btn.scrollWidth > btn.clientWidth) high = size - 1
                else low = size
            }
            btn.style.fontSize = low+'px'
        }
        display(Boolean(translation && !tapToReveal))
        btn.addEventListener('click', e => {
            e.preventDefault()
            e.stopPropagation()
            display(btn.getAttribute('aria-pressed') !== 'true')
        })
    }
    return host
}

// Request only frames intersecting the reader. A single worker serves both
// pages of a spread and ignores responses belonging to discarded frames.
export function mangaReader({contents, request, cancel, draw = drawMangaBubbles, viewport}) {
    let epoch = 0, enabled = false, job = null, timer
    const pages = new Map(), layers = new Map()
    const visible = () => {
        const {width, height} = viewport()
        return contents().filter(({doc}) => {
            if (!doc?.querySelector('[data-document-base]') || doc.documentElement.dataset.documentImage === 'false') return false
            const frame = doc.defaultView?.frameElement
            const r = frame?.parentElement?.getBoundingClientRect()
            return r && r.width > 0 && r.height > 0 && r.left < width && r.top < height && r.right > 0 && r.bottom > 0
        })
    }
    const refresh = async () => {
        if (!enabled) return
        const frames = visible()
        const shown = new Set(frames.map(f => f.index))
        for (const [doc, layer] of layers) if (!frames.some(f => f.doc === doc)) {
            layer?.remove(); layers.delete(doc)
        }
        for (const page of pages.keys()) if (!shown.has(page)) pages.delete(page)
        for (const {doc, index} of frames) if (!layers.has(doc) && pages.has(index)) {
            layers.set(doc, draw(doc, pages.get(index)))
        }
        if (job) {
            if (!shown.has(job.page) && !job.abandoned) {
                job.abandoned = true
                cancel(job.page, job.epoch)
            }
            return
        }
        const next = frames.find(f => !pages.has(f.index))
        if (!next) return
        const current = job = {epoch, page: next.index}
        try {
            const result = await request(next.index, epoch)
            if (epoch === current.epoch && !current.abandoned) pages.set(next.index, result ?? [])
        } catch {
            if (epoch === current.epoch && !current.abandoned) pages.set(next.index, [])
        } finally {
            job = null
            schedule()
        }
    }
    const schedule = () => {
        if (enabled && !timer) timer = setTimeout(() => { timer = null; void refresh() }, 80)
    }
    return {schedule, configure(mode, generation) {
        if (generation <= epoch) return
        epoch = generation
        enabled = mode !== 'off'
        clearTimeout(timer); timer = null
        for (const layer of layers.values()) layer?.remove()
        layers.clear(); pages.clear()
        schedule()
    }}
}
