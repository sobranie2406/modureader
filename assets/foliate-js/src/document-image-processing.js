// Local, bounded raster operations. Originals and text layers are never edited.
export const normalizeEnhancement = (value = {}) => {
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new RangeError('Invalid enhancement')
    const result = {}
    for (const [key, min, max] of [['ink', 0, 15], ['contrast', -100, 100],
        ['darken', 0, 100], ['whiten', 0, 200], ['sharpen', 0, 100]]) {
        const n = value[key] ?? 0
        if (!Number.isFinite(n) || n < min || n > max) throw new RangeError('Invalid enhancement: ' + key)
        result[key] = n
    }
    return result
}
export const hasEnhancement = value => Object.values(normalizeEnhancement(value)).some(n => n !== 0)
const check = signal => { if (signal?.aborted) throw new DOMException('Image processing cancelled', 'AbortError') }
const pause = () => new Promise(resolve => setTimeout(resolve, 0))
const clamp = n => Math.max(0, Math.min(255, n))
const validate = ({data, width, height}) => {
    if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1 ||
        width * height > 2097152 || data?.length !== width * height * 4)
        throw new RangeError('Invalid or oversized image')
}

export async function enhanceImage(image, value, {signal} = {}) {
    validate(image); check(signal)
    const options = normalizeEnhancement(value)
    if (!hasEnhancement(options)) return image
    const {width, height, data} = image, output = new Uint8ClampedArray(data.length)
    const lut = new Uint8ClampedArray(256), gain = 2 ** (options.contrast / 50)
    for (let i = 0; i < 256; i++) lut[i] = clamp(255 * (clamp((i - 128) * gain + 128) / 255) ** (1 + options.darken / 70))
    for (let y = 0; y < height; y++) {
        if (y % 48 === 0) { await pause(); check(signal) }
        for (let x = 0; x < width; x++) {
            const p = (y * width + x) * 4
            const channels = [data[p], data[p + 1], data[p + 2]]
            const neutral = Math.max(...channels) - Math.min(...channels) < 24
            let minimum = (channels[0] + channels[1] + channels[2]) / 3
            if (options.ink && neutral) {
                for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
                    const q = (Math.max(0, Math.min(height - 1, y + dy)) * width + Math.max(0, Math.min(width - 1, x + dx))) * 4
                    if (Math.max(data[q], data[q + 1], data[q + 2]) - Math.min(data[q], data[q + 1], data[q + 2]) < 24)
                        minimum = Math.min(minimum, (data[q] + data[q + 1] + data[q + 2]) / 3)
                }
            }
            for (let c = 0; c < 3; c++) {
                let v = data[p + c]
                // Ink strengthens nearby dark neutral strokes, not every dark tone.
                if (minimum < 140 && neutral) v += (Math.min(v, minimum) - v) * options.ink / 15 * .75
                if (options.sharpen) {
                    const at = (xx, yy) => data[(yy * width + xx) * 4 + c]
                    const average = (at(Math.max(0, x - 1), y) + at(Math.min(width - 1, x + 1), y) +
                        at(x, Math.max(0, y - 1)) + at(x, Math.min(height - 1, y + 1))) / 4
                    v += (data[p + c] - average) * options.sharpen / 100
                }
                v = lut[Math.round(clamp(v))]
                // Lift only light, near-neutral paper; leave coloured illustration pixels intact.
                if (neutral && v > 160) v += (255 - v) * Math.min(1, options.whiten / 200) * (v - 160) / 95
                output[p + c] = v
            }
            output[p + 3] = data[p + 3]
        }
    }
    check(signal); data.set(output)
    return image
}

// Conservative border detection. Busy/dark borders return the full page rather
// than guessing a crop. Isolated one-pixel dust is ignored; thin lines remain.
export async function detectContentCrop(image, {margin = .03, signal} = {}) {
    validate(image); check(signal)
    if (!Number.isFinite(margin) || margin < 0 || margin > .2) throw new RangeError('Invalid crop margin')
    const {data, width, height} = image
    const full = reason => ({crop:{x:0,y:0,width:1,height:1}, reason, detected:false})
    const rgb = p => [0,1,2].map(c => data[p + c] * data[p + 3] / 255 + 255 - data[p + 3])
    const edge = []
    for (let x = 0; x < width; x += Math.max(1, Math.floor(width / 128)))
        edge.push(rgb(x * 4), rgb(((height - 1) * width + x) * 4))
    for (let y = 0; y < height; y += Math.max(1, Math.floor(height / 128)))
        edge.push(rgb(y * width * 4), rgb((y * width + width - 1) * 4))
    const bg = [0,1,2].map(c => edge.map(v => v[c]).sort((a,b) => a-b)[Math.floor(edge.length / 2)])
    if (Math.min(...bg) < 180 || edge.filter(v => v.some((n,c) => Math.abs(n - bg[c]) > 24)).length > edge.length * .08)
        return full('uncertain-border')
    const mask = new Uint8Array(width * height)
    for (let y = 0; y < height; y++) {
        if (y % 64 === 0) { await pause(); check(signal) }
        for (let x = 0; x < width; x++) {
            const p = y * width + x
            mask[p] = rgb(p * 4).some((v,c) => Math.abs(v - bg[c]) > 18) ? 1 : 0
        }
    }
    let left = width, top = height, right = -1, bottom = -1
    for (let y = 0; y < height; y++) {
        if (y % 64 === 0) { await pause(); check(signal) }
        for (let x = 0; x < width; x++) {
            if (!mask[y * width + x]) continue
            let neighbours = 0
            for (let yy = Math.max(0, y - 1); yy <= Math.min(height - 1, y + 1); yy++)
                for (let xx = Math.max(0, x - 1); xx <= Math.min(width - 1, x + 1); xx++)
                    neighbours += mask[yy * width + xx]
            if (neighbours < 2) continue
            left = Math.min(left, x); right = Math.max(right, x)
            top = Math.min(top, y); bottom = Math.max(bottom, y)
        }
    }
    if (right < 0) return full('blank-or-low-contrast')
    // Two extra raster pixels protect antialiasing outside the detected edge.
    const x = Math.max(0, left / width - margin - 2 / width), y = Math.max(0, top / height - margin - 2 / height)
    const r = Math.min(1, (right + 1) / width + margin + 2 / width), b = Math.min(1, (bottom + 1) / height + margin + 2 / height)
    return {crop:{x,y,width:r-x,height:b-y}, reason:'content-bounds', detected:true}
}
