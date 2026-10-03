import { pdfViewport } from './pdf-reading-viewport.js'
import { rotateRegion, rotatePoint } from './document-regions.js'

// Full CSS page geometry, not a full high-resolution raster allocation.
export const scrollPagePlan = ({ pageWidth, pageHeight, width, height, crop, view }) => {
    const visible = pdfViewport({ pageWidth, pageHeight, width, height, crop, view })
    const r = rotateRegion(crop, view.rotation)
    const w = r.width * visible.rw * visible.scale, h = r.height * visible.rh * visible.scale
    return pdfViewport({ pageWidth, pageHeight, width: w, height: h, crop,
        view: { ...view, zoom: 1, fit: 'width' } })
}

export const scrollVisibleRegion = (plan, crop, pageRect, viewport) => {
    const left = Math.max(pageRect.left, viewport.left), top = Math.max(pageRect.top, viewport.top)
    const right = Math.min(pageRect.left + plan.width, viewport.right)
    const bottom = Math.min(pageRect.top + plan.height, viewport.bottom)
    if (right <= left || bottom <= top) return null
    const r = rotateRegion(crop, plan.rotation)
    return rotateRegion({ x: r.x + (left - pageRect.left) / (plan.rw * plan.scale),
        y: r.y + (top - pageRect.top) / (plan.rh * plan.scale),
        width: (right - left) / (plan.rw * plan.scale),
        height: (bottom - top) / (plan.rh * plan.scale) }, -plan.rotation)
}

export const scrollSourcePoint = (plan, crop, x, y) => {
    const r = rotateRegion(crop, plan.rotation)
    return rotatePoint({ x: r.x + Math.max(0, Math.min(plan.width, x)) / (plan.rw * plan.scale),
        y: r.y + Math.max(0, Math.min(plan.height, y)) / (plan.rh * plan.scale) }, -plan.rotation)
}
