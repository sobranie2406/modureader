import { regionRenderPlan } from './pdf-region-renderer.js'
import { normalizeEnhancement, hasEnhancement, enhanceImage, detectContentCrop } from './document-image-processing.js'

const aborted = () => new DOMException('Image document closed', 'AbortError')
const check = signal => { if (signal?.aborted) throw aborted() }
const localImage = url => /^(blob:|data:image\/(?:png|jpeg|webp|gif|avif|bmp|svg\+xml)[;,])/i.test(url ?? '')
const boundedWait = async (promise, signal) => {
    check(signal)
    let timer, listener
    try {
        return await Promise.race([promise,
            new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Image page load timed out')), 10000) }),
            new Promise((_, reject) => { listener = () => reject(aborted()); signal?.addEventListener('abort', listener, {once:true}) })])
    } finally { clearTimeout(timer); signal?.removeEventListener('abort', listener) }
}
const exclusion = (book, section) => section.linear === 'no' || book.landmarks?.some(item =>
    item.type?.some(type => ['cover', 'toc'].includes(type)) && item.href?.split('#')[0] === section.id)

export function imageSectionEvidence({page, href, width, height, characters, images, excluded = false}) {
    // Union area, not a sum: overlapping SVG fragments must not inflate coverage.
    const boxes = images.map(i => ({x:Math.max(0,i.x), y:Math.max(0,i.y),
        r:Math.min(width,i.x+i.width), b:Math.min(height,i.y+i.height)})).filter(r => r.r>r.x && r.b>r.y)
    const xs = [...new Set(boxes.flatMap(r => [r.x,r.r]))].sort((a,b)=>a-b)
    let area = 0
    for (let n=1;n<xs.length;n++) {
        const bands=boxes.filter(r=>r.x<xs[n]&&r.r>xs[n-1]).sort((a,b)=>a.y-b.y)
        let end=0, h=0
        for(const r of bands){h+=Math.max(0,r.b-Math.max(end,r.y));end=Math.max(end,r.b)}
        area+=(xs[n]-xs[n-1])*h
    }
    const imageCoverage = width>0&&height>0 ? Math.min(1,area/(width*height)) : 0
    const large = images.some(i => i.naturalWidth>=300 && i.naturalHeight>=300) ||
        images.reduce((n,i)=>n+i.naturalWidth*i.naturalHeight,0)>=300000
    const imageOnly = characters === 0 && large && imageCoverage >= .65 && images.length>0
    return {page,href,width,height,characters,images,excluded,imageCoverage,coverageUncertain:false,
        reliableText:characters>=80, imageOnly,
        kind:excluded?'illustrated':characters>=80?'text':imageOnly?'scanned':images.length?'image-candidate':'blank'}
}

// Explicit, local inspection. One sandboxed layout frame at a time; no scripts,
// remote subresources or original DOM mutations. Section IDs remain spine IDs.
export function createEpubImageSource(book) {
    let current, tail=Promise.resolve(), generation=0
    const cache=new Map()
    const cancel=()=>current?.abort()
    const clear=()=>{generation++;cancel();for(const entry of cache.values())entry.release();cache.clear()}
    const enqueue = (fn, external) => {
        cancel(); const controller=new AbortController(), version=generation;current=controller
        const abort=()=>controller.abort();external?.addEventListener('abort',abort,{once:true})
        if(external?.aborted)abort()
        const job=tail.catch(()=>{}).then(async()=>{
            check(controller.signal)
            const result=await fn(controller.signal)
            check(controller.signal);if(version!==generation)throw aborted()
            return result
        }).finally(()=>{external?.removeEventListener('abort',abort);if(current===controller)current=null})
        tail=job.catch(()=>{});return job
    }
    const snapshot = async (index, signal) => {
        if(!Number.isInteger(index)||index<0||index>=book.sections.length)throw new RangeError('EPUB section out of bounds')
        if(cache.has(index)){const item=cache.get(index);cache.delete(index);cache.set(index,item);return item}
        const section=book.sections[index]
        let frame, url, retained=false, release=()=>{}
        try {
            const lease=await section.loadImageDocument();release=lease.release
            const src=lease.src;check(signal)
            if(!src?.startsWith('blob:'))throw new Error('Local EPUB resources required')
            const html=await (await fetch(src)).text();check(signal)
            const doc=new DOMParser().parseFromString(html,'text/html')
            if(doc.querySelectorAll('img,image').length>64)throw new Error('Too many image fragments in one section')
            for(const el of doc.querySelectorAll('script,iframe,object,embed,audio,video,base,meta[http-equiv]'))el.remove()
            for(const el of doc.querySelectorAll('*'))for(const attr of [...el.attributes])
                if(attr.name.startsWith('on'))el.removeAttribute(attr.name)
            const csp=doc.createElement('meta');csp.httpEquiv='Content-Security-Policy'
            csp.content="default-src 'none'; img-src blob: data:; style-src blob: 'unsafe-inline'; font-src blob: data:; base-uri 'none'; form-action 'none'"
            doc.head.prepend(csp)
            const measureStyle=doc.createElement('style')
            measureStyle.textContent='html { overflow: hidden !important; }'
            doc.head.append(measureStyle)
            frame=document.createElement('iframe');frame.setAttribute('sandbox','allow-same-origin')
            // visibility:hidden is inherited by chapter children and would make
            // all images/text appear absent to our visibility inspection.
            frame.setAttribute('aria-hidden','true');frame.tabIndex=-1
            Object.assign(frame.style,{position:'fixed',left:'-20000px',top:'0',width:'1000px',height:'1200px',border:'0',pointerEvents:'none'})
            url=URL.createObjectURL(new Blob([doc.documentElement.outerHTML],{type:'text/html'}))
            // Inserting a frame may synchronously load about:blank. Only the
            // requested chapter document is valid evidence.
            const ready=new Promise((resolve,reject)=>{frame.onload=()=>{
                if(frame.contentDocument?.URL===url)resolve()
            };frame.onerror=reject})
            document.body.append(frame);frame.src=url;await boundedWait(ready,signal)
            const rendered=frame.contentDocument
            if (rendered.fonts?.ready) await boundedWait(rendered.fonts.ready, signal)
            const elements=[...rendered.querySelectorAll('img,image')].filter(el=>{
                const s=frame.contentWindow.getComputedStyle(el)
                const r=el.getBoundingClientRect()
                return s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity)!==0&&r.width>0&&r.height>0
            })
            if(elements.length>64)throw new Error('Too many image fragments in one section')
            const images=[]
            let unsupported=false
            for(const el of elements){
                check(signal)
                const source=el.currentSrc||el.getAttribute('src')||el.getAttribute('href')||el.getAttribute('xlink:href')
                if(!localImage(source)){unsupported=true;continue}
                const image=new Image();image.src=source;await boundedWait(image.decode(),signal)
                const r=el.getBoundingClientRect()
                const style=frame.contentWindow.getComputedStyle(el)
                const styled = [el, ...function* () { for(let node=el.parentElement;node;node=node.parentElement)yield node }()]
                const unsupportedPaint = styled.some(node => {
                    const s=frame.contentWindow.getComputedStyle(node)
                    const generated = ['::before','::after'].some(pseudo => {
                        const content=frame.contentWindow.getComputedStyle(node,pseudo).content
                        return content && !['none','normal','""'].includes(content)
                    })
                    return generated || s.transform!=='none' || Number(s.opacity)!==1 || s.filter!=='none' ||
                        s.clipPath!=='none' || (s.maskImage && s.maskImage!=='none') || s.backgroundImage!=='none'
                })
                if(unsupportedPaint || el.closest('[transform]') || el.closest('svg')?.querySelector('text,foreignObject,path,rect,circle,ellipse,polygon,polyline,line,use,clipPath,mask,filter'))
                    {image.src='';unsupported=true;continue}
                let x=r.x,y=r.y,w=r.width,h=r.height
                const preserve=el.getAttribute('preserveAspectRatio')??'xMidYMid meet'
                const isSvg=el.localName==='image'
                if(isSvg && (!['xMidYMid meet','xMidYMid','none'].includes(preserve)))
                    {image.src='';unsupported=true;continue}
                if (!isSvg && style.objectFit==='contain' && style.objectPosition!=='50% 50%') {
                    image.src='';unsupported=true;continue
                }
                if((isSvg&&preserve!=='none')||(!isSvg&&style.objectFit==='contain')){
                    const scale=Math.min(w/image.naturalWidth,h/image.naturalHeight)
                    const rw=image.naturalWidth*scale,rh=image.naturalHeight*scale
                    x+=(w-rw)/2;y+=(h-rh)/2;w=rw;h=rh
                }else if(!isSvg&&!['fill','contain'].includes(style.objectFit)){
                    image.src='';unsupported=true;continue
                }
                images.push({resource:source,order:images.length,x,y,width:w,height:h,
                    naturalWidth:image.naturalWidth,naturalHeight:image.naturalHeight})
                image.src=''
            }
            // Visible body text only; hidden navigation must not turn a scan into text.
            let text='';const walker=rendered.createTreeWalker(rendered.body,NodeFilter.SHOW_TEXT)
            for(let node=walker.nextNode();node;node=walker.nextNode()){
                if(node.parentElement?.closest('script,style,nav,rt,rp,[hidden],[aria-hidden="true"]'))continue
                const range=rendered.createRange();range.selectNodeContents(node)
                const style=frame.contentWindow.getComputedStyle(node.parentElement)
                if(style.visibility!=='hidden'&&Number(style.opacity)!==0&&[...range.getClientRects()].some(r=>r.width&&r.height))text+=node.textContent
            }
            const width=Math.max(1000,rendered.documentElement.scrollWidth)
            const height=Math.max(1,...images.map(i=>i.y+i.height),rendered.body.scrollHeight)
            const evidence=imageSectionEvidence({page:index,href:section.id,width,height,
                characters:[...text.replace(/\s/g,'')].length,images,excluded:exclusion(book,section)})
            if(unsupported){evidence.imageOnly=false;evidence.coverageUncertain=true;if(!evidence.reliableText&&!evidence.excluded)evidence.kind='image-candidate'}
            const item={...evidence,release}
            check(signal);cache.set(index,item);retained=true
            while(cache.size>4){const key=cache.keys().next().value;cache.get(key).release();cache.delete(key)}
            return item
        } finally {
            frame?.remove();if(url)URL.revokeObjectURL(url)
            if(!retained)release()
        }
    }
    const info = page => enqueue(async signal=>{
        const e=await snapshot(page,signal)
        return {page,total:book.sections.length,width:e.width,height:e.height,imageOnly:e.imageOnly,kind:e.kind}
    })
    const inspect = (page,{signal}={})=>enqueue(async inner=>{
        const {release,...e}=await snapshot(page,inner);return e
    },signal)
    const render = request => enqueue(async signal=>{
        const e=await snapshot(request.page,signal)
        if(!e.imageOnly)throw new Error('This section contains text or unsupported image layout. Use the original reader.')
        const mock={getViewport:({scale,rotation=0})=>({width:(rotation%180?e.height:e.width)*scale,
            height:(rotation%180?e.width:e.height)*scale,scale,rotation})}
        const plan=regionRenderPlan(mock,request), enhancement=normalizeEnhancement(request.enhancement)
        if(request.analyzeCrop&&(plan.rotation||Object.values(plan.region).join(',')!=='0,0,1,1'))throw new RangeError('Crop detection needs a full page')
        const canvas=document.createElement('canvas');canvas.width=plan.width;canvas.height=plan.height
        try{
            const ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height)
            ctx.translate(plan.transform[4],plan.transform[5]);ctx.scale(plan.viewport.scale,plan.viewport.scale)
            if(plan.rotation===90){ctx.translate(e.height,0);ctx.rotate(Math.PI/2)}
            else if(plan.rotation===180){ctx.translate(e.width,e.height);ctx.rotate(Math.PI)}
            else if(plan.rotation===270){ctx.translate(0,e.width);ctx.rotate(-Math.PI/2)}
            for(const i of e.images){
                check(signal);const img=new Image();img.src=i.resource;await boundedWait(img.decode(),signal)
                ctx.drawImage(img,i.x,i.y,i.width,i.height);img.src=''
            }
            let cropDetection
            if(request.analyzeCrop||hasEnhancement(enhancement)){
                const pixels=ctx.getImageData(0,0,canvas.width,canvas.height)
                if(request.analyzeCrop)cropDetection=await detectContentCrop(pixels,{signal,margin:request.margin??.03})
                if(hasEnhancement(enhancement)){await enhanceImage(pixels,enhancement,{signal});ctx.putImageData(pixels,0,0)}
            }
            const blob=await new Promise((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(new Error('Encoding failed')),'image/png'))
            check(signal);return {blob,page:request.page,width:plan.width,height:plan.height,cropDetection}
        }finally{canvas.width=0;canvas.height=0}
    })
    return {info,inspect,render,cancel,clear}
}
