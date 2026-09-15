// Chapter Range rects are relative to the iframe viewport. Annotation SVGs
// live in the parent document. Convert through their actual transforms rather
// than assuming both origins coincide (preloaded chapters have their own padding).
export const annotationPointMapper = (doc, svg) => {
    const frame = doc.defaultView?.frameElement
    const matrix = svg.getScreenCTM?.()
    if (!frame || !matrix) return ({ x, y }) => ({ x, y })
    const inverse = matrix.inverse()
    if (![inverse.a, inverse.b, inverse.c, inverse.d, inverse.e, inverse.f].every(Number.isFinite))
        return ({ x, y }) => ({ x, y }) // Hidden/collapsed cached frame; redraw on activation.
    const bounds = frame.getBoundingClientRect()
    const scaleX = frame.offsetWidth ? bounds.width / frame.offsetWidth : 1
    const scaleY = frame.offsetHeight ? bounds.height / frame.offsetHeight : 1
    return ({ x, y }) => {
        const screenX = bounds.left + (frame.clientLeft + x) * scaleX
        const screenY = bounds.top + (frame.clientTop + y) * scaleY
        return { x: inverse.a * screenX + inverse.c * screenY + inverse.e,
            y: inverse.b * screenX + inverse.d * screenY + inverse.f }
    }
}

export const annotationRect = (rect, map, zoom = 1) => {
    const a = map({ x: rect.left * zoom, y: rect.top * zoom })
    const b = map({ x: rect.right * zoom, y: rect.bottom * zoom })
    const left = Math.min(a.x, b.x), top = Math.min(a.y, b.y)
    const right = Math.max(a.x, b.x), bottom = Math.max(a.y, b.y)
    return { left, top, right, bottom, width: right - left, height: bottom - top }
}
