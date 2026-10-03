import { pageLayout, splitRegions } from './document-regions.js'

export const readingRegions = (config, page, book) => splitRegions(book?.nativeTextPages?.has(page) ? {} : pageLayout(config, page) ?? {})
export const layoutSignature = (config, page) => JSON.stringify(readingRegions(config, page)
    .map(({ x, y, width, height }) => [x, y, width, height]))

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
        if (item != null) splitRegions(item)
    for (const key of Object.keys(config.pages))
        if (!/^\d+$/.test(key)) throw new TypeError('Invalid original page')
    return JSON.parse(JSON.stringify(config))
}
