import {validateRegion} from './document-regions.js'

// Only requested pages are read. This does not perform OCR or sample a book.
export async function extractPdfText(pdf, {page, region}) {
    region = validateRegion(region)
    if (!Number.isInteger(page) || page < 0 || page >= pdf.numPages) throw new RangeError('Invalid page')
    const source = await pdf.getPage(page + 1), viewport = source.getViewport({scale:1})
    const content = await source.getTextContent(), t = viewport.transform
    const point = (x,y) => [t[0]*x+t[2]*y+t[4], t[1]*x+t[3]*y+t[5]]
    const entries = []
    for (const item of content.items) {
        if (!item.str?.trim() || !item.transform || !Number.isFinite(item.width)) continue
        const m=item.transform, height=Math.hypot(m[2],m[3]), horizontal=Math.hypot(m[0],m[1])
        if (!height || !horizontal) continue
        const style=content.styles?.[item.fontName], ascent=style?.ascent ?? .8, descent=style?.descent ?? -.2
        const dx=m[0]/horizontal*item.width, dy=m[1]/horizontal*item.width
        const corners=[[0,descent],[1,descent],[0,ascent],[1,ascent]].map(([u,v])=>point(m[4]+u*dx+v*m[2],m[5]+u*dy+v*m[3]))
        const left=Math.min(...corners.map(p=>p[0]))/viewport.width, right=Math.max(...corners.map(p=>p[0]))/viewport.width
        const top=Math.min(...corners.map(p=>p[1]))/viewport.height, bottom=Math.max(...corners.map(p=>p[1]))/viewport.height
        if ((top+bottom)/2 < region.y || (top+bottom)/2 > region.y+region.height || right <= region.x || left >= region.x+region.width) continue
        // Estimate partial horizontal runs; preserve complete items unchanged.
        let text=item.str
        if (right>left && item.dir !== 'ttb') {
            const chars=[...text], n=chars.length
            const start=Math.max(0,Math.round((region.x-left)/(right-left)*n))
            const end=Math.min(n,Math.round((region.x+region.width-left)/(right-left)*n))
            text=chars.slice(start,end).join('')
        }
        if (text.trim()) entries.push({text,left,right,top,height:bottom-top})
    }
    entries.sort((a,b)=>a.top-b.top)
    const rows=[]
    for(let i=0;i<entries.length;){
        const first=entries[i++],row=[first]
        while(i<entries.length && entries[i].top-first.top<Math.min(first.height,entries[i].height)*.45) row.push(entries[i++])
        row.sort((a,b)=>a.left-b.left)
        let line=''
        for(let n=0;n<row.length;n++) {
            const entry=row[n],previous=row[n-1]
            if(previous && entry.left-previous.right > .002 && /[a-zA-Z0-9]$/.test(line) && /^[a-zA-Z0-9]/.test(entry.text)) line+=' '
            line+=entry.text
        }
        rows.push(line.trim())
    }
    const text=rows.join('\n')
    if(text.length>100000) throw new RangeError('Select a smaller area')
    return {text,page,source:'text-layer'}
}
