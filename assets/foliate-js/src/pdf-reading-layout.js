import { FULL_PAGE, validateRegion, pageLayout, splitRegions } from './document-regions.js'

export const readingRegions = (config, page, book) => splitRegions(book?.nativeTextPages?.has(page) ? {} : pageLayout(config, page) ?? {})
export const layoutSignature = (config, page) => {
    const layout = pageLayout(config, page)
    // Automatic bounds vary by page, not by the editor's preview rectangle.
    return layout?.autoCrop ? JSON.stringify(['auto-v1', layout.autoMargin ?? .03,
        layout.preset ?? 'single', layout.order ?? 'row-ltr']) :
        JSON.stringify(readingRegions(config, page).map(({ x, y, width, height }) => [x, y, width, height]))
}

const cropStates = new WeakMap()
// Reflow consumes the whole original page after cropping, never just the
// currently visible split panel or zoomed viewport.
export async function resolveReflowRegion(config, page, book, options = {}) {
    if (options.enabled === false) return {...FULL_PAGE}
    const regions = await resolveReadingRegions(config, page, book, options)
    const x = Math.min(...regions.map(r => r.x)), y = Math.min(...regions.map(r => r.y))
    const right = Math.max(...regions.map(r => r.x + r.width))
    const bottom = Math.max(...regions.map(r => r.y + r.height))
    return validateRegion({x, y, width: right - x, height: bottom - y})
}
// A separate low-resolution renderer avoids cancelling scrolling/detail renders.
// Cache only small coordinates, keyed by original page and detection settings.
export async function resolveReadingRegions(config, page, book, {hideWatermarks = false, active = () => true} = {}) {
    const layout = pageLayout(config, page) ?? {}
    if (!layout.autoCrop || book?.nativeTextPages?.has(page)) return readingRegions(config, page, book)
    const check = () => { if (!active()) throw new DOMException('Reader changed', 'AbortError') }
    check()
    let state = cropStates.get(book)
    if (!state) { state = {cache: new Map(), tail: Promise.resolve()}; cropStates.set(book, state) }
    const key = JSON.stringify([page, layout.autoMargin ?? .03, hideWatermarks])
    const pending = state.tail.catch(() => {}).then(async () => {
        check()
        if (state.cache.has(key)) return state.cache.get(key)
        let crop = FULL_PAGE
        try {
            const result = await book.cropRegionRenderer.render({page, region: FULL_PAGE,
                rotation: 0, width: 1000, height: 1200, analyzeCrop: true, detectionOnly: true,
                margin: layout.autoMargin ?? .03, hideWatermarks})
            check()
            if (!result.cropDetection) throw new Error('Missing crop detection')
            if (result.cropDetection.detected) crop = validateRegion(result.cropDetection.crop)
            state.cache.set(key, crop)
            while (state.cache.size > 64) state.cache.delete(state.cache.keys().next().value)
        } catch (error) {
            check()
            if (error.name === 'AbortError') throw error
            // Never reuse the preceding page's box or interrupt reading on failure.
            // Unsuccessful requests are not cached, so revisiting can retry.
        }
        return crop
    })
    state.tail = pending.catch(() => {})
    const crop = await pending
    check()
    return splitRegions({...layout, crop})
}

// Never reinterpret an old panel number after changing the crop/order/grid.
export const restoredPanel = (config, page, saved) =>
    saved?.page === page && saved.signature === layoutSignature(config, page) &&
    Number.isInteger(saved.panel) && saved.panel >= 0 &&
    saved.panel < readingRegions(config, page).length ? saved.panel : 0

export const adjacentPanel = (config, total, page, panel, direction, book) => {
    if (![1, -1].includes(direction)) throw new RangeError('Invalid direction')
    if (page < 0) return direction > 0 && total > 0 ? { page: 0, panel: 0 } : null
    const next = panel + direction
    if (next >= 0 && next < readingRegions(config, page, book).length) return { page, panel: next }
    page += direction
    if (page < 0 || page >= total) return null
    return { page, panel: direction > 0 ? 0 : readingRegions(config, page, book).length - 1 }
}

export const validateReadingLayout = config => {
    if (config?.version !== 1 || !config.pages || typeof config.pages !== 'object')
        throw new TypeError('Invalid PDF reading layout')
    for (const item of [config.all, config.odd, config.even, ...Object.values(config.pages)])
        if (item != null) {
            splitRegions(item)
            if (item.autoCrop !== undefined && typeof item.autoCrop !== 'boolean') throw new TypeError('Invalid auto crop')
            if (item.autoMargin !== undefined && (!Number.isFinite(item.autoMargin) || item.autoMargin < 0 || item.autoMargin > .2))
                throw new RangeError('Invalid auto crop margin')
        }
    for (const key of Object.keys(config.pages))
        if (!/^\d+$/.test(key)) throw new TypeError('Invalid original page')
    return JSON.parse(JSON.stringify(config))
}
