// Coordinates are normalized against the original, upright page viewport.
// PDF's built-in page rotation is already part of that viewport. `rotation`
// below is an additional user rotation; never persist screen pixel positions.
export const FULL_PAGE = Object.freeze({ x: 0, y: 0, width: 1, height: 1 })

export const normalizeRotation = rotation => {
    if (!Number.isInteger(rotation) || rotation % 90 !== 0)
        throw new RangeError('Rotation must be a multiple of 90 degrees')
    return ((rotation % 360) + 360) % 360
}

export const validateRegion = (rect = FULL_PAGE) => {
    const { x, y, width, height } = rect
    if (![x, y, width, height].every(Number.isFinite) || x < 0 || y < 0 ||
        width <= 0 || height <= 0 || x + width > 1 + 1e-9 || y + height > 1 + 1e-9)
        throw new RangeError('Region must be inside the normalized page')
    return { x, y, width, height }
}

export const rotatePoint = ({ x, y }, rotation = 0) => {
    if (![x, y].every(Number.isFinite)) throw new RangeError('Invalid point')
    switch (normalizeRotation(rotation)) {
        case 90: return { x: 1 - y, y: x }
        case 180: return { x: 1 - x, y: 1 - y }
        case 270: return { x: y, y: 1 - x }
        default: return { x, y }
    }
}

export const rotateRegion = (rect, rotation = 0) => {
    const { x, y, width, height } = validateRegion(rect)
    const points = [{ x, y }, { x: x + width, y },
        { x, y: y + height }, { x: x + width, y: y + height }]
        .map(point => rotatePoint(point, rotation))
    const left = Math.min(...points.map(p => p.x)), top = Math.min(...points.map(p => p.y))
    return { x: left, y: top, width: Math.max(...points.map(p => p.x)) - left,
        height: Math.max(...points.map(p => p.y)) - top }
}

// Reversible mapping for future annotations, OCR boxes and selections.
export const sourceToRegion = (point, crop = FULL_PAGE, rotation = 0) => {
    const r = rotateRegion(crop, rotation), p = rotatePoint(point, rotation)
    return { x: (p.x - r.x) / r.width, y: (p.y - r.y) / r.height }
}
export const regionToSource = (point, crop = FULL_PAGE, rotation = 0) => {
    const r = rotateRegion(crop, rotation)
    return rotatePoint({ x: r.x + point.x * r.width, y: r.y + point.y * r.height }, -rotation)
}

export const GRID_PRESETS = Object.freeze({
    single: [1, 1], horizontal2: [2, 1], vertical2: [1, 2], four: [2, 2],
    horizontal6: [3, 2], vertical6: [2, 3], nine: [3, 3],
})

export const splitRegions = ({ crop = FULL_PAGE, preset = 'single', order = 'row-ltr' } = {}) => {
    const rect = validateRegion(crop), grid = GRID_PRESETS[preset]
    if (!grid || !['row-ltr', 'row-rtl', 'column-ltr', 'column-rtl'].includes(order))
        throw new RangeError('Invalid grid or reading order')
    const [columns, rows] = grid, regions = []
    for (let row = 0; row < rows; row++) for (let column = 0; column < columns; column++) {
        regions.push({ row, column, x: rect.x + rect.width * column / columns,
            y: rect.y + rect.height * row / rows, width: rect.width / columns,
            height: rect.height / rows })
    }
    const col = order.endsWith('rtl') ? -1 : 1
    regions.sort(order.startsWith('row')
        ? (a, b) => a.row - b.row || col * (a.column - b.column)
        : (a, b) => col * (a.column - b.column) || a.row - b.row)
    return regions
}

// Original page is always zero based; visible odd/even page numbers are 1 based.
export const pageLayout = (config, page) => {
    if (!Number.isInteger(page) || page < 0) throw new RangeError('Invalid original page')
    return config?.pages?.[page] ?? config?.[page % 2 === 0 ? 'odd' : 'even'] ?? config?.all ?? null
}
