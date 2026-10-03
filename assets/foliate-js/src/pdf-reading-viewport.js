import { FULL_PAGE, validateRegion, normalizeRotation, rotatePoint, rotateRegion } from './document-regions.js'
import { normalizeEnhancement } from './document-image-processing.js'
import { normalizeDocumentDisplay } from './document-reading-options.js'

export const normalizePdfView = (value = {}) => {
    const zoom = value.zoom ?? 1, fit = value.fit ?? 'screen', mode = value.mode ?? 'single'
    if (!Number.isFinite(zoom) || zoom < 1 || zoom > 15 || !['screen', 'width'].includes(fit) ||
        !['single', 'scroll'].includes(mode))
        throw new RangeError('Invalid PDF view')
    return { zoom, fit, rotation: normalizeRotation(value.rotation ?? 0), mode,
        ...(value.enhancement ? {enhancement:normalizeEnhancement(value.enhancement)} : {}),
        ...(value.display ? {display:normalizeDocumentDisplay(value.display)} : {}) }
}
const clamp = (value, min, max) => Math.max(min, Math.min(max, value))

// All persistent coordinates refer to the upright source page, never pixels.
// The raster and original text layer use the same affine transform.
export const pdfViewport = ({ pageWidth, pageHeight, width, height, crop = FULL_PAGE,
    view = {}, center }) => {
    if (![pageWidth, pageHeight, width, height].every(n => Number.isFinite(n) && n > 0))
        throw new RangeError('Invalid viewport dimensions')
    const { zoom, fit, rotation } = normalizePdfView(view)
    validateRegion(crop)
    const r = rotateRegion(crop, rotation), swapped = rotation % 180 !== 0
    const rw = swapped ? pageHeight : pageWidth, rh = swapped ? pageWidth : pageHeight
    const scale = (fit === 'width' ? width / (r.width * rw)
        : Math.min(width / (r.width * rw), height / (r.height * rh))) * zoom
    const vw = Math.min(r.width, width / (rw * scale)), vh = Math.min(r.height, height / (rh * scale))
    const wanted = center && [center.x, center.y].every(Number.isFinite)
        ? rotatePoint(center, rotation) : { x: r.x + r.width / 2, y: r.y + vh / 2 }
    const x = clamp(wanted.x - vw / 2, r.x, r.x + r.width - vw)
    const y = clamp(wanted.y - vh / 2, r.y, r.y + r.height - vh)
    const visible = { x, y, width: vw, height: vh }
    const transform = rotation === 90 ? [0, 1, -1, 0, pageHeight, 0]
        : rotation === 180 ? [-1, 0, 0, -1, pageWidth, pageHeight]
        : rotation === 270 ? [0, -1, 1, 0, 0, pageWidth] : [1, 0, 0, 1, 0, 0]
    transform[4] -= x * rw
    transform[5] -= y * rh
    return { scale, rotation, rw, rh, visible,
        sourceRegion: rotateRegion(visible, -rotation),
        center: rotatePoint({ x: x + vw / 2, y: y + vh / 2 }, -rotation),
        width: vw * rw * scale, height: vh * rh * scale,
        matrix: transform.map(n => n * scale) }
}

export const panPdfViewport = (plan, dx, dy) => {
    if (![dx, dy].every(Number.isFinite)) throw new RangeError('Invalid pan')
    const p = rotatePoint(plan.center, plan.rotation)
    return rotatePoint({ x: p.x + dx / (plan.rw * plan.scale),
        y: p.y + dy / (plan.rh * plan.scale) }, -plan.rotation)
}
