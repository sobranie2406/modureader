// Local, bounded raster operations. Originals and text layers are never edited.
export const normalizeEnhancement = (value = {}) => {
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new RangeError('Invalid enhancement')
    const result = {}
    for (const [key, min, max] of [['ink', 0, 15], ['contrast', -100, 100],
        ['darken', 0, 100], ['whiten', 0, 200], ['sharpen', 0, 100], ['watermark', 0, 100]]) {
        const n = value[key] ?? 0
        if (!Number.isFinite(n) || n < min || n > max) throw new RangeError('Invalid enhancement: ' + key)
        result[key] = n
    }
    const mode = value.paperMode ?? 'preserve'
    if (!['preserve', 'text'].includes(mode)) throw new RangeError('Invalid paper mode')
    if (mode !== 'preserve') result.paperMode = mode
    return result
}
export const hasEnhancement = value => Object.values(normalizeEnhancement(value)).some(n => typeof n === 'number' && n !== 0)
const check = signal => { if (signal?.aborted) throw new DOMException('Image processing cancelled', 'AbortError') }
const pause = () => new Promise(resolve => setTimeout(resolve, 0))
const clamp = n => Math.max(0, Math.min(255, n))
const validate = ({data, width, height}) => {
    if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1 ||
        width * height > 2097152 || data?.length !== width * height * 4)
        throw new RangeError('Invalid or oversized image')
}

// Conservative, opt-in scan cleanup. Inspired by the general mask/foreground-
// background separation approach, not an inpainting or text reconstruction model.
// Large pale components are candidates; dark strokes and their antialias fringe
// are protected. A pale heading and a pale watermark can still be indistinguishable.
async function fadeScanWatermarks(image, strength, signal) {
    const {data, width, height} = image, count = width * height
    const output = new Uint8ClampedArray(data)
    const histogram = Array.from({length:3}, () => new Uint32Array(256))
    let samples = 0
    for (let y = 0; y < height; y += Math.max(1, Math.floor(height / 100))) {
        for (let x = 0; x < width; x += Math.max(1, Math.floor(width / 100))) {
            const p = (y * width + x) * 4
            if (data[p + 3] !== 255) continue
            for (let c = 0; c < 3; c++) histogram[c][data[p + c]]++
            samples++
        }
    }
    if (!samples) return output
    const paper = histogram.map(h => {
        let n = 0
        for (let v = 0; v < 256; v++) { n += h[v]; if (n >= samples * .9) return v }
        return 255
    })
    if (Math.min(...paper) < 190) return output // not a light-paper scan
    const amount = strength / 100, paperLuma = (paper[0] + paper[1] + paper[2]) / 3
    const candidate = new Uint8Array(count), dark = new Uint8Array(count)
    let paperPixels = 0
    for (let y = 0; y < height; y++) {
        if (y % 48 === 0) { await pause(); check(signal) }
        for (let x = 0; x < width; x++) {
            const p = y * width + x, i = p * 4
            if (data[i + 3] !== 255) continue
            const r = data[i], g = data[i+1], b = data[i+2]
            const low = Math.min(r,g,b), high = Math.max(r,g,b), luma = (r+g+b)/3
            dark[p] = high < 145 || luma < 110 ? 1 : 0
            const delta = Math.max(Math.abs(paper[0]-r),Math.abs(paper[1]-g),Math.abs(paper[2]-b))
            if (delta <= 12) { paperPixels++; continue }
            const colored = high-low > 30
            if (luma < paperLuma - 8 && luma >= (colored ? 190 - 40*amount : 220 - 65*amount) && low >= 100)
                candidate[p] = 1
        }
    }
    if (paperPixels < count * .45) return output // dense pictures / full-bleed pages
    const mask = new Uint8Array(count)
    for (let y = 0; y < height; y++) {
        if (y % 48 === 0) { await pause(); check(signal) }
        for (let x = 0; x < width; x++) {
            const p = y * width + x
            if (!candidate[p]) continue
            let protectedInk = false
            for (let yy = Math.max(0,y-1); yy <= Math.min(height-1,y+1) && !protectedInk; yy++)
                for (let xx = Math.max(0,x-1); xx <= Math.min(width-1,x+1); xx++)
                    if (dark[yy*width+xx]) { protectedInk = true; break }
            if (!protectedInk) mask[p] = 1
        }
    }
    const queue = new Int32Array(count), minimumSpan = Math.max(10, Math.sqrt(count)*.025)
    for (let y = 0; y < height; y++) {
        if (y % 32 === 0) { await pause(); check(signal) }
        for (let x = 0; x < width; x++) {
            const first = y*width+x
            if (!mask[first]) continue
            let head=0, tail=1, left=x, right=x, top=y, bottom=y
            queue[0]=first; mask[first]=0
            while(head<tail) {
                if (head && head % 32768 === 0) { await pause(); check(signal) }
                const p=queue[head++], yy=Math.floor(p/width), xx=p%width
                left=Math.min(left,xx);right=Math.max(right,xx);top=Math.min(top,yy);bottom=Math.max(bottom,yy)
                for(let ny=Math.max(0,yy-1);ny<=Math.min(height-1,yy+1);ny++)
                    for(let nx=Math.max(0,xx-1);nx<=Math.min(width-1,xx+1);nx++) {
                        const q=ny*width+nx
                        if(mask[q]) { mask[q]=0;queue[tail++]=q }
                    }
            }
            const w=right-left+1,h=bottom-top+1
            // Keep small pale print, thin rules and large solid illustration fills.
            if(tail<12 || Math.max(w,h)<minimumSpan || Math.min(w,h)<3 ||
                tail>count*.12 || (tail>64 && tail/(w*h)>.8)) continue
            for(let n=0;n<tail;n++) {
                const i=queue[n]*4
                for(let c=0;c<3;c++) output[i+c]=data[i+c]+Math.max(0,paper[c]-data[i+c])*amount
            }
        }
    }
    check(signal)
    return output
}

// Small per-tile paper histogram: estimate illumination without OCR or another
// full-size bitmap. Interpolate tile centres to avoid seams on uneven scans.
async function paperField(data, width, height, signal) {
    const size = 64, cols = Math.ceil(width / size), rows = Math.ceil(height / size)
    const levels = new Float32Array(cols * rows)
    for (let ty = 0; ty < rows; ty++) {
        await pause(); check(signal)
        for (let tx = 0; tx < cols; tx++) {
            const histogram = new Uint32Array(256)
            let count = 0
            for (let y = ty * size; y < Math.min(height, (ty + 1) * size); y += 2)
                for (let x = tx * size; x < Math.min(width, (tx + 1) * size); x += 2) {
                    const p = (y * width + x) * 4
                    if (data[p + 3] < 250) continue
                    histogram[Math.round((data[p] + data[p + 1] + data[p + 2]) / 3)]++
                    count++
                }
            let sum = 0, paper = 255
            for (let n = 0; count && n < 256; n++) {
                sum += histogram[n]
                if (sum >= count * .85) { paper = n; break }
            }
            levels[ty * cols + tx] = Math.max(160, paper)
        }
    }
    return (x, y) => {
        const gx = Math.max(0, Math.min(cols - 1, x / size - .5))
        const gy = Math.max(0, Math.min(rows - 1, y / size - .5))
        const x0 = Math.floor(gx), y0 = Math.floor(gy)
        const x1 = Math.min(cols - 1, x0 + 1), y1 = Math.min(rows - 1, y0 + 1)
        const a = gx - x0, b = gy - y0
        return (levels[y0 * cols + x0] * (1-a) + levels[y0 * cols + x1] * a) * (1-b) +
            (levels[y1 * cols + x0] * (1-a) + levels[y1 * cols + x1] * a) * b
    }
}

export async function enhanceImage(image, value, {signal} = {}) {
    validate(image); check(signal)
    const options = normalizeEnhancement(value)
    if (!hasEnhancement(options)) return image
    const {width, height} = image
    // Cleanup precedes darkening/sharpening so they cannot amplify a watermark
    // before its mask is found. Commit only after all cancellable work succeeds.
    const data = options.watermark ? await fadeScanWatermarks(image, options.watermark, signal) : image.data
    if (options.watermark && ['ink','contrast','darken','whiten','sharpen'].every(key => options[key] === 0)) {
        check(signal); image.data.set(data); return image
    }
    const output = new Uint8ClampedArray(data.length)
    const paper = options.paperMode === 'text' && options.whiten
        ? await paperField(data, width, height, signal) : null
    const lut = new Uint8ClampedArray(256), gain = 2 ** (options.contrast / 50)
    for (let i = 0; i < 256; i++) lut[i] = clamp(255 * (clamp((i - 128) * gain + 128) / 255) ** (1 + options.darken / 70))
    for (let y = 0; y < height; y++) {
        if (y % 48 === 0) { await pause(); check(signal) }
        for (let x = 0; x < width; x++) {
            const p = (y * width + x) * 4
            const r = data[p], g = data[p + 1], b = data[p + 2]
            const neutral = Math.max(r, g, b) - Math.min(r, g, b) < 24
            const luma = (r + g + b) / 3
            let minimum = luma
            const background = paper?.(x, y)
            // Text mode deliberately removes paper colour. Dark strokes stay
            // untouched; faint print/illustrations should be checked in preview.
            const clean = background ? Math.min(255, luma * 255 / Math.max(150, background - 6)) : 0
            const paperAmount = background ? Math.min(1, options.whiten / 200) *
                Math.max(0, Math.min(1, (luma - 90) / 70)) : 0
            if (options.ink && neutral) {
                for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
                    const q = (Math.max(0, Math.min(height - 1, y + dy)) * width + Math.max(0, Math.min(width - 1, x + dx))) * 4
                    if (Math.max(data[q], data[q + 1], data[q + 2]) - Math.min(data[q], data[q + 1], data[q + 2]) < 24)
                        minimum = Math.min(minimum, (data[q] + data[q + 1] + data[q + 2]) / 3)
                }
            }
            for (let c = 0; c < 3; c++) {
                let v = data[p + c]
                if (paperAmount) v += (clean - v) * paperAmount
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
                if (!paper && neutral && v > 160) v += (255 - v) * Math.min(1, options.whiten / 200) * (v - 160) / 95
                output[p + c] = v
            }
            output[p + 3] = data[p + 3]
        }
    }
    check(signal); image.data.set(output)
    return image
}

// Locate printed strokes using local paper contrast. A global colour difference
// treats yellow paper, gradients and binding shadows as page-sized content.
// This is geometric text/content detection, not OCR; figures and notes survive.
export async function detectContentCrop(image, {margin = .03, signal} = {}) {
    validate(image); check(signal)
    if (!Number.isFinite(margin) || margin < 0 || margin > .2) throw new RangeError('Invalid crop margin')
    const {data, width, height} = image
    const full = reason => ({crop:{x:0,y:0,width:1,height:1}, reason, detected:false})
    const gray = new Uint8Array(width * height), histogram = new Uint32Array(256)
    // Integral local means cost O(pixels), not a window scan per pixel. Together
    // with the mask/queue these arrays stay within the existing 2MP budget.
    const stride = width + 1, integral = new Float64Array(stride * (height + 1))
    for (let y = 0; y < height; y++) {
        if (y % 64 === 0) { await pause(); check(signal) }
        let sum = 0
        for (let x = 0; x < width; x++) {
            const p = y * width + x, i = p * 4, alpha = data[i + 3] / 255
            const value = Math.round((data[i] * .299 + data[i+1] * .587 + data[i+2] * .114) * alpha + 255 * (1-alpha))
            gray[p] = value; histogram[value]++; sum += value
            integral[(y+1)*stride+x+1] = integral[y*stride+x+1] + sum
        }
    }
    let paper = 255, total = 0
    for (let v = 0; v < 256; v++) {
        total += histogram[v]
        if (total >= width * height * .85) { paper = v; break }
    }
    if (paper < 140) return full('uncertain-border')
    const radius = Math.max(6, Math.min(40, Math.round(Math.min(width,height) * .025)))
    const mask = new Uint8Array(width * height)
    for (let y = 0; y < height; y++) {
        if (y % 64 === 0) { await pause(); check(signal) }
        for (let x = 0; x < width; x++) {
            const p = y * width + x
            const l = Math.max(0,x-radius), r = Math.min(width,x+radius+1)
            const t = Math.max(0,y-radius), b = Math.min(height,y+radius+1)
            const mean = (integral[b*stride+r]-integral[b*stride+l]-integral[t*stride+r]+integral[t*stride+l])/((r-l)*(b-t))
            // Keep strong solid ink too, so diagrams and full-bleed pictures
            // cannot disappear merely because their interiors have no edges.
            mask[p] = gray[p] < mean - Math.max(7,mean*.055) || gray[p] < Math.min(110,paper*.5) ? 1 : 0
        }
    }
    let left = width, top = height, right = -1, bottom = -1
    const smallComponents = []
    const minimumInk = Math.max(8, Math.round(Math.min(width,height) * .012))
    const queue = new Int32Array(width * height)
    for (let y = 0; y < height; y++) {
        if (y % 64 === 0) { await pause(); check(signal) }
        for (let x = 0; x < width; x++) {
            const start = y * width + x
            if (!mask[start]) continue
            let head = 0, tail = 1, l = x, r = x, t = y, b = y, inside = false
            queue[0] = start; mask[start] = 0
            while (head < tail) {
                if (head > 0 && head % 65536 === 0) { await pause(); check(signal) }
                const p = queue[head++], yy = Math.floor(p / width), xx = p % width
                l = Math.min(l, xx); r = Math.max(r, xx); t = Math.min(t, yy); b = Math.max(b, yy)
                if (xx >= width * .12 && xx < width * .88 && yy >= height * .12 && yy < height * .88) inside = true
                for (let ny = Math.max(0, yy - 1); ny <= Math.min(height - 1, yy + 1); ny++)
                    for (let nx = Math.max(0, xx - 1); nx <= Math.min(width - 1, xx + 1); nx++) {
                        const q = ny * width + nx
                        if (mask[q]) { mask[q] = 0; queue[tail++] = q }
                    }
            }
            if (tail < 2) continue // isolated scanner dust, not thin strokes
            const touchesEdge = l === 0 || t === 0 || r === width - 1 || b === height - 1
            const peripheral = l < width*.06 || t < height*.06 || r >= width*.94 || b >= height*.94
            const cw = r-l+1, ch = b-t+1
            const brokenEdgeLine =
                ((r < width*.03 || l > width*.97) && ch > Math.max(30,height*.04) && ch > cw*25) ||
                ((b < height*.03 || t > height*.97) && cw > Math.max(30,width*.04) && cw > ch*25)
            if (brokenEdgeLine) continue
            // Frames are often inset several pixels from the actual image edge.
            // Require all their ink to stay outside the central reading region.
            if (peripheral && !inside && (r - l > width * .6 || b - t > height * .6)) continue
            // Full-bleed illustrations/dark pages are not safe text crops.
            if (touchesEdge && (tail > width * height * .5 ||
                (l === 0 && r === width - 1 && b - t > height * .2) ||
                (t === 0 && b === height - 1 && r - l > width * .2))) return full('uncertain-border')
            // Isolated few-pixel specks in the margins must not determine the
            // crop. Keep small punctuation near the established printed area.
            if (tail < minimumInk) { smallComponents.push({l,r,t,b}); continue }
            left = Math.min(left, l); right = Math.max(right, r)
            top = Math.min(top, t); bottom = Math.max(bottom, b)
        }
    }
    if (right < 0) return full('blank-or-low-contrast')
    const reach = Math.max(3, Math.round(Math.min(width,height) * .008))
    const body = {left, right, top, bottom}
    for (const {l,r,t,b} of smallComponents) {
        if (r < body.left-reach || l > body.right+reach || b < body.top-reach || t > body.bottom+reach) continue
        left = Math.min(left,l); right = Math.max(right,r)
        top = Math.min(top,t); bottom = Math.max(bottom,b)
    }
    // Two extra raster pixels protect antialiasing outside the detected edge.
    const x = Math.max(0, left / width - margin - 2 / width), y = Math.max(0, top / height - margin - 2 / height)
    const r = Math.min(1, (right + 1) / width + margin + 2 / width), b = Math.min(1, (bottom + 1) / height + margin + 2 / height)
    return {crop:{x,y,width:r-x,height:b-y}, reason:'content-bounds', detected:true}
}
