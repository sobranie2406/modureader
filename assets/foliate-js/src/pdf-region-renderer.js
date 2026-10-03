import { FULL_PAGE, validateRegion, normalizeRotation, rotateRegion } from './document-regions.js'
import { normalizeEnhancement, hasEnhancement, enhanceImage, detectContentCrop } from './document-image-processing.js'

const abortError = () => new DOMException('PDF region request cancelled', 'AbortError')
const check = signal => { if (signal.aborted) throw abortError() }

// A virtual full-page viewport, but ONLY the requested visible rectangle gets
// a bitmap. High zoom must never allocate a full-page high-resolution canvas.
export const regionRenderPlan = (page, { region = FULL_PAGE, rotation = 0,
    width = 1200, height = 1200 } = {}) => {
    region = validateRegion(region)
    rotation = normalizeRotation(rotation)
    if (![width, height].every(value => Number.isFinite(value) && value > 0))
        throw new RangeError('Invalid output dimensions')
    const original = page.getViewport({ scale: 1 })
    const base = page.getViewport({ scale: 1, rotation: normalizeRotation(original.rotation + rotation) })
    const regionWidth = base.width * region.width, regionHeight = base.height * region.height
    if (![regionWidth, regionHeight].every(value => Number.isFinite(value) && value > 0))
        throw new RangeError('Invalid PDF page dimensions')
    const scale = Math.min(width / regionWidth, height / regionHeight,
        2048 / regionWidth, 2048 / regionHeight, Math.sqrt(2097152 / (regionWidth * regionHeight)))
    const viewport = page.getViewport({ scale, rotation: base.rotation })
    // Floor (rather than ceil) keeps the hard pixel budget even at its boundary.
    const outputWidth = Math.max(1, Math.floor(regionWidth * scale))
    const outputHeight = Math.max(1, Math.floor(regionHeight * scale))
    return { viewport, width: outputWidth, height: outputHeight,
        transform: [1, 0, 0, 1, -region.x * viewport.width, -region.y * viewport.height],
        region, sourceRegion: rotateRegion(region, -rotation), rotation }
}

export const createPdfRegionRenderer = (pdf, {
    createCanvas = () => document.createElement('canvas'),
    encode = canvas => new Promise((resolve, reject) => canvas.toBlob(blob =>
        blob ? resolve(blob) : reject(new Error('PDF region encoding failed')), 'image/png')),
} = {}) => {
    let current, tail = Promise.resolve(), generation = 0
    const cache = new Map()
    let cacheBytes = 0
    const watermarkGroups = async () => {
        const config = await pdf.getOptionalContentConfig?.()
        return Object.entries(config?.getGroups() ?? {}).filter(([, group]) =>
            /watermark|水印/i.test(group.name ?? '')).map(([id, group]) => ({id, name:group.name}))
    }
    const cancel = () => current?.abort()
    const clear = () => { generation++; cancel(); cache.clear(); cacheBytes = 0 }
    const info = async (page = 0) => {
        if (!Number.isInteger(page) || page < 0 || page >= pdf.numPages)
            throw new RangeError('PDF page out of bounds')
        const version = generation
        const viewport = (await pdf.getPage(page + 1)).getViewport({ scale: 1 })
        if (version !== generation) throw abortError()
        const watermarks = await watermarkGroups()
        if (version !== generation) throw abortError()
        return { page, total: pdf.numPages, width: viewport.width, height: viewport.height, watermarks }
    }
    const render = (request, { signal } = {}) => {
        cancel()
        const controller = new AbortController(), version = generation
        current = controller
        const abort = () => controller.abort()
        signal?.addEventListener('abort', abort, { once: true })
        if (signal?.aborted) abort()
        // Serialize canvas ownership, including cancellation and encoding. A fast
        // drag can queue requests, but at most one bitmap is being rendered.
        const pending = tail.catch(() => {}).then(async () => {
            check(controller.signal)
            const pageNumber = request.page
            if (!Number.isInteger(pageNumber) || pageNumber < 0 || pageNumber >= pdf.numPages)
                throw new RangeError('PDF page out of bounds')
            const page = await pdf.getPage(pageNumber + 1)
            check(controller.signal)
            const plan = regionRenderPlan(page, request)
            const enhancement = normalizeEnhancement(request.enhancement)
            if (request.analyzeCrop && (plan.rotation !== 0 || Object.keys(FULL_PAGE).some(k => plan.region[k] !== FULL_PAGE[k])))
                throw new RangeError('Crop detection requires an unrotated full page')
            const key = JSON.stringify([pageNumber, plan.region, plan.rotation,
                plan.viewport.scale, plan.width, plan.height, enhancement, request.analyzeCrop === true, request.margin ?? .03,
                request.hideWatermarks === true])
            if (cache.has(key)) {
                const result = cache.get(key)
                cache.delete(key); cache.set(key, result)
                return result
            }
            const canvas = createCanvas()
            let task
            const cancelTask = () => task?.cancel()
            controller.signal.addEventListener('abort', cancelTask, { once: true })
            try {
                canvas.width = plan.width; canvas.height = plan.height
                const canvasContext = canvas.getContext('2d')
                if (!canvasContext) throw new Error('PDF canvas unavailable')
                let optionalContentConfigPromise
                if (request.hideWatermarks === true && pdf.getOptionalContentConfig) {
                    // Fresh config per render: never mutate original-page or
                    // other reader instances. Only explicitly named OCGs.
                    const config = await pdf.getOptionalContentConfig()
                    for (const [id, group] of Object.entries(config?.getGroups() ?? {}))
                        if (/watermark|水印/i.test(group.name ?? '')) config.setVisibility(id, false)
                    optionalContentConfigPromise = Promise.resolve(config)
                    check(controller.signal)
                }
                task = page.render({ canvasContext, viewport: plan.viewport, optionalContentConfigPromise,
                    transform: plan.transform, intent: 'print', background: 'rgb(255,255,255)' })
                await task.promise
                check(controller.signal)
                let cropDetection
                if (request.analyzeCrop || hasEnhancement(enhancement)) {
                    const pixels = canvasContext.getImageData(0, 0, plan.width, plan.height)
                    if (request.analyzeCrop) cropDetection = await detectContentCrop(pixels,
                        {margin:request.margin ?? .03, signal:controller.signal})
                    if (hasEnhancement(enhancement)) {
                        await enhanceImage(pixels, enhancement, {signal:controller.signal})
                        canvasContext.putImageData(pixels, 0, 0)
                    }
                }
                const blob = await encode(canvas)
                check(controller.signal)
                if (version !== generation) throw abortError()
                const result = { blob, page: pageNumber, width: plan.width, height: plan.height,
                    region: plan.region, sourceRegion: plan.sourceRegion, rotation: plan.rotation,
                    ...(cropDetection ? {cropDetection} : {}) }
                if (blob.size <= 8 * 1024 * 1024) {
                    cache.set(key, result); cacheBytes += blob.size
                    while (cache.size > 4 || cacheBytes > 8 * 1024 * 1024) {
                        const oldest = cache.keys().next().value
                        cacheBytes -= cache.get(oldest).blob.size; cache.delete(oldest)
                    }
                }
                return result
            } catch (error) {
                if (controller.signal.aborted) throw abortError()
                throw error
            } finally {
                controller.signal.removeEventListener('abort', cancelTask)
                canvas.width = 0; canvas.height = 0
            }
        }).finally(() => {
            signal?.removeEventListener('abort', abort)
            if (current === controller) current = null
        })
        tail = pending.catch(() => {})
        return pending
    }
    return { info, render, cancel, clear }
}
