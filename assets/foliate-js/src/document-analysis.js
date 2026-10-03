// Shared, local-only document evidence. Detection is advisory: image + text
// does not prove how a PDF's text layer was produced (OCR or authoring).
const identity = [1, 0, 0, 1, 0, 0];
export const multiply = (a, b) => [
    a[0]*b[0]+a[2]*b[1], a[1]*b[0]+a[3]*b[1],
    a[0]*b[2]+a[2]*b[3], a[1]*b[2]+a[3]*b[3],
    a[0]*b[4]+a[2]*b[5]+a[4], a[1]*b[4]+a[3]*b[5]+a[5],
];
const point = (m, x, y) => [m[0]*x+m[2]*y+m[4], m[1]*x+m[3]*y+m[5]];
const validMatrix = m => m?.length === 6 && Array.from(m).every(Number.isFinite);
function bounds(points, width, height) {
    const xs = points.map(p => p[0]), ys = points.map(p => p[1]);
    const left = Math.max(0, Math.min(width, Math.min(...xs)));
    const top = Math.max(0, Math.min(height, Math.min(...ys)));
    const right = Math.max(left, Math.min(width, Math.max(...xs)));
    const bottom = Math.max(top, Math.min(height, Math.max(...ys)));
    return { left: left/width, top: top/height, right: right/width, bottom: bottom/height };
}
function unionCoverage(rects) {
    const xs = [...new Set(rects.flatMap(r => [r.left, r.right]))].sort((a,b) => a-b);
    let area = 0;
    for (let i = 1; i < xs.length; i++) {
        const bands = rects.filter(r => r.left < xs[i] && r.right > xs[i-1])
            .map(r => [r.top, r.bottom]).sort((a,b) => a[0]-b[0]);
        let end = 0, height = 0;
        for (const [a,b] of bands) { height += Math.max(0, b-Math.max(a,end)); end = Math.max(end,b); }
        area += (xs[i]-xs[i-1])*height;
    }
    return Math.min(1, area);
}
export function checkCancelled(signal) {
    if (signal?.aborted) throw new DOMException('Document analysis cancelled', 'AbortError');
}
export function samplePageIndices(length, limit = 5) {
    if (!Number.isInteger(length) || length <= 0) return [];
    const count = Math.max(1, Math.min(length, 9, Math.trunc(limit) || 5));
    return [...new Set(Array.from({length: count}, (_, i) => count === 1 ? 0
        : Math.round(i*(length-1)/(count-1))))];
}
export function summarizePages(pages, total) {
    // Blank/illustration-only cover and sparse decoration are not a book type.
    const informative = pages.filter(p => !['blank', 'unknown', 'image-candidate', 'illustrated'].includes(p.kind));
    const kinds = new Set(informative.map(p => p.kind));
    return { kind: kinds.size > 1 ? 'mixed' : [...kinds][0] ?? 'unknown',
        total, sampled: pages.length, complete: pages.length === total,
        pages: pages.map(({text, blocks, images, ...evidence}) => evidence) };
}

export async function analyzePdfPage(page, OPS, {signal} = {}) {
    checkCancelled(signal);
    const viewport = page.getViewport({scale: 1});
    const {width, height} = viewport;
    if (!(width > 0 && height > 0) || !validMatrix(viewport.transform))
        throw new Error('Invalid PDF page geometry');
    const content = await page.getTextContent();
    checkCancelled(signal);
    const blocks = [];
    let characters = 0, validCharacters = 0;
    for (const item of content.items) {
        if (typeof item.str !== 'string') continue;
        const count = [...item.str.replace(/[\s\u0000-\u001f\ufffd]/gu, '')].length;
        characters += count;
        if (!count || !validMatrix(item.transform) || !Number.isFinite(item.width) ||
            !Number.isFinite(item.height)) continue;
        const m = multiply(viewport.transform, item.transform);
        const size = Math.hypot(m[2], m[3]);
        if (!(size > 0 && item.width > 0)) continue;
        const horizontal = Math.hypot(m[0], m[1]);
        if (!horizontal) continue;
        // Baseline to ascent/descent bounds, retaining rotation in the quad.
        const style = content.styles?.[item.fontName];
        const ascent = Number.isFinite(style?.ascent) ? style.ascent : 0.8;
        const descent = Number.isFinite(style?.descent) ? style.descent : -0.2;
        const dx = m[0]/horizontal*item.width, dy = m[1]/horizontal*item.width;
        const quad = [[m[4]+m[2]*descent,m[5]+m[3]*descent],
            [m[4]+dx+m[2]*descent,m[5]+dy+m[3]*descent],
            [m[4]+dx+m[2]*ascent,m[5]+dy+m[3]*ascent],
            [m[4]+m[2]*ascent,m[5]+m[3]*ascent]];
        const box = bounds(quad, width, height);
        if (box.right <= box.left || box.bottom <= box.top) continue;
        validCharacters += count;
        blocks.push({text: item.str, box, quad: quad.map(([x,y]) => [x/width,y/height]),
            direction: item.dir ?? 'ltr', hasEOL: item.hasEOL === true,
            source: 'text-layer', confidence: null});
    }
    const operators = await page.getOperatorList();
    checkCancelled(signal);
    let matrix = identity, clipped = false, uncertain = false, paint = false;
    const stack = [], images = [];
    const addImage = transform => {
        const m = multiply(viewport.transform, transform);
        const box = bounds([[0,0],[1,0],[1,1],[0,1]].map(([x,y]) => point(m,x,y)),width,height);
        if (images.length < 512) images.push(box); else uncertain = true;
        // A rotated/sheared image's AABB can overstate its actual area.
        if (clipped || Math.abs(m[0]*m[2]+m[1]*m[3]) > 0.01 ||
            (Math.abs(m[1]) > 0.01 && Math.abs(m[0]) > 0.01)) uncertain = true;
        paint = true;
    };
    for (let i = 0; i < operators.fnArray.length; i++) {
        if (i % 2048 === 0) { checkCancelled(signal); await new Promise(resolve => setTimeout(resolve,0)); }
        const op = operators.fnArray[i], args = operators.argsArray[i];
        if (op === OPS.save || op === OPS.paintFormXObjectBegin) {
            stack.push([matrix,clipped]);
            if (op === OPS.paintFormXObjectBegin) {
                if (validMatrix(args?.[0])) matrix = multiply(matrix,args[0]);
                if (args?.[1]) clipped = true;
            }
        } else if (op === OPS.restore || op === OPS.paintFormXObjectEnd) {
            [matrix,clipped] = stack.pop() ?? [identity,false];
        } else if (op === OPS.transform && validMatrix(args)) matrix = multiply(matrix,args);
        else if (op === OPS.clip || op === OPS.eoClip) clipped = true;
        else if (op === OPS.paintImageXObject || op === OPS.paintInlineImageXObject) addImage(matrix);
        else if (op === OPS.paintImageXObjectRepeat) {
            const [,sx,sy,positions] = args;
            for (let j = 0; j < positions.length; j += 2)
                addImage(multiply(matrix,[sx,0,0,sy,positions[j],positions[j+1]]));
        } else if ([OPS.paintInlineImageXObjectGroup, OPS.paintImageMaskXObject,
            OPS.paintImageMaskXObjectGroup, OPS.paintImageMaskXObjectRepeat].includes(op)) {
            uncertain = true; paint = true;
        } else if ([OPS.stroke, OPS.fill, OPS.eoFill, OPS.fillStroke, OPS.eoFillStroke,
            OPS.shadingFill].includes(op)) paint = true;
    }
    const coverage = unionCoverage(images);
    const reliableText = validCharacters >= 24 && validCharacters >= characters*0.8;
    const kind = coverage >= 0.65 && !uncertain
        ? reliableText ? 'image-with-text' : 'scanned'
        : reliableText ? 'text' : !paint && !characters ? 'blank' : 'unknown';
    return {page: page.pageNumber-1, width, height, rotation: viewport.rotation,
        kind, characters, validCharacters, reliableText, imageCoverage: coverage,
        coverageUncertain: uncertain, images, blocks,
        text: blocks.map(b => b.text+(b.hasEOL ? '\n' : ' ')).join('')};
}

export function createPdfAnalysis(pdf, OPS) {
    const cache = new Map();
    let generation = 0;
    const page = async (index, options = {}) => {
        if (!Number.isInteger(index) || index < 0 || index >= pdf.numPages)
            throw new RangeError('PDF page out of bounds');
        checkCancelled(options.signal);
        const startedGeneration = generation;
        let result = cache.get(index);
        if (!result) result = await analyzePdfPage(await pdf.getPage(index+1), OPS, options);
        checkCancelled(options.signal);
        if (startedGeneration !== generation)
            throw new DOMException('PDF reader closed during analysis', 'AbortError');
        cache.delete(index); cache.set(index,result);
        while (cache.size > 12) cache.delete(cache.keys().next().value);
        return result;
    };
    return { page, clear: () => { generation++; cache.clear(); },
        async sample({signal, onProgress} = {}) {
            const indices = samplePageIndices(pdf.numPages), pages = [];
            for (const index of indices) {
                pages.push(await page(index,{signal}));
                onProgress?.(pages.length,indices.length);
            }
            return {format:'pdf', ...summarizePages(pages,pdf.numPages)};
        },
    };
}

export function analyzeEpubSection(doc, {index, href, excluded = false} = {}) {
    const clone = (doc.body ?? doc.documentElement).cloneNode(true);
    for (const el of clone.querySelectorAll('script,style,nav,rt,rp,[hidden],[aria-hidden="true"]')) el.remove();
    const text = clone.textContent.replace(/\s+/gu,' ').trim();
    const characters = [...text].length;
    const images = Array.from(clone.querySelectorAll('img,image')).map((el,order) => ({
        order, resource: el.getAttribute('src') ?? el.getAttribute('href') ?? el.getAttribute('xlink:href'),
        width: el.getAttribute('width'), height: el.getAttribute('height'),
    })).filter(image => image.resource);
    // Intrinsic dimensions/CSS coverage require a rendered page; do not treat
    // a cover or a single decorative icon as a proven scanned chapter.
    const kind = excluded ? 'illustrated' : characters >= 80 ? 'text'
        : images.length ? 'image-candidate' : characters ? 'unknown' : 'blank';
    return {page:index, href, kind, characters, images, text, blocks:[],
        reliableText:characters >= 80, excluded, coverageUncertain:true};
}
