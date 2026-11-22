import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const {JSDOM}=createRequire(`${process.env.MODU_JSDOM_ROOT || '/private/tmp/modu-119-js-tests'}/package.json`)('jsdom');
const dom=new JSDOM('<body></body>',{pretendToBeVisual:true});globalThis.document=dom.window.document;globalThis.devicePixelRatio=1;
const uri=code=>`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const source=name=>readFile(new URL(`../assets/foliate-js/src/${name}.js`,import.meta.url),'utf8');
const geometry=uri(await source('document-regions'));
const {regionRenderPlan}=await import(uri((await source('pdf-region-renderer'))
    .replace("'./document-regions.js'",JSON.stringify(geometry))
    .replace("'./document-image-processing.js'",JSON.stringify(uri(await source('document-image-processing'))))));
const viewport=uri((await source('pdf-reading-viewport')).replace("'./document-regions.js'",JSON.stringify(geometry))
    .replace("'./document-reading-options.js'", JSON.stringify(uri(await source('document-reading-options'))))
    .replace("'./document-image-processing.js'",JSON.stringify(uri(await source('document-image-processing')))));
const layout=uri((await source('pdf-reading-layout')).replace("'./document-regions.js'",JSON.stringify(geometry)));
const scrollLayout=uri((await source('pdf-scroll-layout')).replace("'./pdf-reading-viewport.js'",JSON.stringify(viewport))
    .replace("'./document-regions.js'",JSON.stringify(geometry)));
const {scrollPagePlan,scrollVisibleRegion,scrollSourcePoint}=await import(scrollLayout);
const {PdfRenderBudget}=await import(uri(await source('pdf-render-budget')));
const {PdfScrollReader}=await import(uri((await source('pdf-scroll-reader'))
    .replace("'./pdf-zoom-input.js'", JSON.stringify(uri(await source('pdf-zoom-input'))))
    .replace("'./pdf-render-budget.js'", JSON.stringify(uri(await source('pdf-render-budget'))))
    .replace("'./transient-scrollbar.js'", JSON.stringify(uri(await source('transient-scrollbar'))))
    .replace("'./pdf-reading-layout.js'",JSON.stringify(layout)).replace("'./pdf-scroll-layout.js'",JSON.stringify(scrollLayout))));
const near=(a,b)=>assert.ok(Math.abs(a-b)<1e-6,`${a} != ${b}`);
const rect=(left,top,width,height)=>({left,top,right:left+width,bottom:top+height,width,height});
const children=[];
function harness(config={version:1,all:{preset:'single'},pages:{}}) {
    const loaded=[],states=[],locations=[],announced=[];
    const bounds={width:800,height:600};
    const book={sections:Array.from({length:60},(_,index)=>({load:async()=>{loaded.push(index);return String(index)}})),
        readingRegionRenderer:{render:async()=>({blob:new Blob(['png'])})}};
    const flow=new PdfScrollReader({book,layout:config,view:{zoom:1,fit:'width',rotation:0,mode:'scroll'},bounds:()=>bounds,
        onLoad:doc=>announced.push(doc),onRelocate:reason=>locations.push({reason,location:flow.location}),onState:s=>states.push(s),
        createFrame:async(index,src,parent,before)=>{
            const element=document.createElement('div');element.style.position='absolute';parent.insertBefore(element,before);
            const child=new JSDOM('<img><div class="textLayer"><span>Original text</span></div>');children.push(child);
            child.window.HTMLImageElement.prototype.decode=async()=>{};
            Object.defineProperty(element,'offsetTop',{get(){let y=0;for(const node of parent.children){
                if(node===element)break;if(node.style.position!=='absolute')y+=parseFloat(node.style.height)+16;}return y}});
            element.getBoundingClientRect=()=>rect(Math.max(0,(bounds.width-parseFloat(element.style.width))/2)-parent.scrollLeft,
                element.offsetTop-parent.scrollTop,parseFloat(element.style.width),parseFloat(element.style.height));
            return {index,element,width:600,height:800,iframe:{style:{},contentDocument:child.window.document}};
        }});
    document.body.append(flow.element);flow.element.getBoundingClientRect=()=>rect(0,0,bounds.width,bounds.height);
    Object.defineProperty(flow.element,'clientWidth',{get:()=>bounds.width});
    return {flow,book,loaded,states,locations,announced,bounds,close:()=>flow.destroy()};
}
test('rotated continuous geometry maps visible strips to bounded source rectangles',()=>{
    for(const rotation of [0,90,180,270]){
        const crop={x:.1,y:.1,width:.8,height:.8};
        const plan=scrollPagePlan({pageWidth:600,pageHeight:800,width:390,height:844,crop,view:{zoom:15,fit:'width',rotation}});
        assert.ok(plan.height>844);near(plan.width,3120);
        const region=scrollVisibleRegion(plan,crop,rect(-100,-200,plan.width,plan.height),rect(0,0,390,844));
        assert.ok(region.x>=.1-1e-9&&region.y>=.1-1e-9&&region.width<.3&&region.height<.4);
        const p=scrollSourcePoint(plan,crop,100,200);assert.ok(p.x>=.1-1e-9&&p.y>=.1-1e-9);
        assert.equal(scrollVisibleRegion(plan,crop,rect(0,900,plan.width,plan.height),rect(0,0,390,844)),null);
    }
});
test('prepending and recycling preserve source viewport; frames stay bounded in both directions',async()=>{
    const h=harness();try{
        await h.flow.open(20,0);h.flow.activate();const before=h.flow.location;
        await h.flow.ensureNeighbors();near(h.flow.location.center.y,before.center.y);assert.equal(h.flow.location.page,20);
        for(let i=0;i<30;i++){h.flow.pan(0,650);await h.flow.ensureNeighbors();assert.ok(h.flow.entries.length<=7)}
        const forward=h.flow.location.page;assert.ok(forward>25);
        for(let i=0;i<30;i++){h.flow.pan(0,-650);await h.flow.ensureNeighbors();assert.ok(h.flow.entries.length<=7)}
        assert.ok(h.flow.location.page<forward);
        for(let i=1;i<h.flow.entries.length;i++)assert.equal(h.flow.entries[i].index,h.flow.entries[i-1].index+1);
        assert.ok(h.loaded.length<60);
    }finally{h.close()}
});
test('continuous pages restore independent zooms without unbounded frames',async()=>{
    const h=harness();
    try {
        await h.flow.open(0,0);h.flow.activate();await h.flow.ensureNeighbors();
        const signature=h.flow.location.signature;
        const next=h.flow.entries.find(e=>e.index===1);
        h.flow.resize({...h.flow.view,zoom:2});
        assert.equal(next.zoom,2,'unvisited prepared pages inherit zoom');
        h.flow.pageViews['1:0']={signature,zoom:3};
        next.zoom=undefined;h.flow.layoutEntry(next);
        h.flow.resize({...h.flow.view,zoom:2.5});
        assert.equal(h.flow.entries[0].zoom,2.5);
        assert.equal(next.zoom,3);
        assert.ok(h.flow.entries.length<=7);
        h.flow.resetPosition();
        assert.equal(h.flow.location.zoom,2.5);
    } finally {h.close()}
});

test('arrow panning is bounded to the current scroll page and pending position survives suspension',async()=>{
    const h=harness();
    try {
        await h.flow.open(0,0);h.flow.activate();await h.flow.ensureNeighbors();
        h.flow.resize({...h.flow.view,zoom:3});
        h.flow.panWithinPage(100,100);
        assert.equal(h.flow.location.page,0);
        for(let i=0;i<100;i++)h.flow.panWithinPage(60,60);
        assert.equal(h.flow.location.page,0);
        const edge={...h.flow.location};h.flow.panWithinPage(60,60);
        assert.deepEqual(h.flow.location,edge);
        h.flow.suspend();assert.deepEqual(h.locations.at(-1).location,edge);
        assert.equal(h.locations.at(-1).reason,'viewport');
    } finally {h.close()}
});

test('neighbor failure retains current content, blocks repeated retries, and explicit retry recovers',async()=>{
    const h=harness();try{
        await h.flow.open(0,0);h.flow.activate();const doc=h.flow.getContents()[0].doc;
        let attempts=0;h.book.sections[1].load=async()=>{attempts++;throw Error('injected')};
        await h.flow.ensureNeighbors();await h.flow.ensureNeighbors();
        assert.equal(attempts,1);assert.equal(h.flow.getContents()[0].doc,doc);assert.deepEqual(h.states,['failed']);
        h.book.sections[1].load=async()=> '1';assert.equal(await h.flow.retry(),true);
        assert.ok(h.flow.getContents().some(e=>e.index===1));assert.equal(h.states.at(-1),'ready');
        const count=h.announced.length;h.flow.suspend();h.flow.activate();assert.equal(h.announced.length,count);
    }finally{h.close()}
});
test('close during neighbor loading cannot reattach pages or publish late events',async()=>{
    const h=harness();try{
        await h.flow.open(0,0);let release,started;
        const entered=new Promise(r=>started=r);
        h.book.sections[1].load=()=>{started();return new Promise(r=>release=r)};
        h.flow.activate();const pending=h.flow.ensureNeighbors();await entered;
        const count=h.announced.length;h.close();release('1');await pending;
        assert.equal(h.flow.entries.length,0);assert.equal(h.announced.length,count);assert.deepEqual(h.states,[]);
    }finally{h.close()}
});
test('scroll touch gestures do not become page swipes, while selected text keeps its gesture',async()=>{
    const h=harness();try{
        await h.flow.open(0,0);h.flow.activate();await h.flow.ensureNeighbors();
        const doc=h.flow.getContents()[0].doc;const seen=[];
        for(const type of ['touchstart','touchmove','touchend']) doc.addEventListener(type,()=>seen.push(type));
        const send=(type,y)=>{
            const event=new doc.defaultView.Event(type,{bubbles:true,cancelable:true});
            Object.defineProperty(event,'touches',{value:y===null?[]:[{screenX:100,screenY:y}]});
            doc.dispatchEvent(event);return event.defaultPrevented;
        };
        const before=h.flow.element.scrollTop;
        send('touchstart',200);assert.equal(send('touchmove',150),true);assert.equal(send('touchend',null),true);
        assert.equal(h.flow.element.scrollTop,before+50);assert.deepEqual(seen,['touchstart']);
        const range=doc.createRange();range.selectNodeContents(doc.querySelector('span'));
        doc.getSelection().addRange(range);
        send('touchstart',200);assert.equal(send('touchmove',100),false);assert.equal(send('touchend',null),false);
        assert.equal(h.flow.element.scrollTop,before+50);
    }finally{h.close()}
});
test('grid traversal keeps original page numbers and region order, including parity overrides',async()=>{
    const h=harness({version:1,all:{preset:'four',order:'column-rtl'},even:{preset:'vertical2'},pages:{}});try{
        await h.flow.open(0,2);h.flow.activate();await h.flow.ensureNeighbors();
        for(let i=0;i<8;i++){h.flow.pan(0,450);await h.flow.ensureNeighbors()}
        for(let i=1;i<h.flow.entries.length;i++){
            const a=h.flow.entries[i-1],b=h.flow.entries[i],target=h.flow.adjacent(a,1);
            assert.deepEqual({page:b.index,panel:b.panel},target);
        }
        assert.ok(h.flow.location.page>0);
    }finally{h.close()}
});
test('zoom and window resize keep the normalized current point; saved point reopens there',async()=>{
    const h=harness();try{
        await h.flow.open(10,0,null,{x:.5,y:.6});h.flow.activate();await h.flow.ensureNeighbors();
        const before=h.flow.location;
        h.flow.resize({...h.flow.view,zoom:3});near(h.flow.location.center.y,before.center.y);
        const e=h.flow.current;assert.ok(e.plan.height>2000);
        h.bounds.width=390;h.bounds.height=844;h.flow.resize();near(h.flow.location.center.y,before.center.y);
    }finally{h.close()}
});
function momentumClock() {
    const host=dom.window,request=host.requestAnimationFrame,cancel=host.cancelAnimationFrame;
    const pending=new Map();let next=0,now=0;
    host.requestAnimationFrame=fn=>{pending.set(++next,fn);return next};
    host.cancelAnimationFrame=id=>pending.delete(id);
    return {pending,step(ms=16){now+=ms;const callbacks=[...pending.values()];pending.clear();callbacks.forEach(fn=>fn(now))},
        close(){host.requestAnimationFrame=request;host.cancelAnimationFrame=cancel}};
}
function touch(doc,type,y,time,count=1) {
    const event=new doc.defaultView.Event(type,{bubbles:true,cancelable:true});
    Object.defineProperties(event,{timeStamp:{value:time},touches:{value:y===null?[]:
        Array.from({length:count},()=>({screenX:100,screenY:y}))}});
    doc.dispatchEvent(event);
}
test('touch release coasts with decaying velocity across PDF pages and saves the final position',async()=>{
    const h=harness(),clock=momentumClock();try{
        await h.flow.open(0,0);h.flow.activate();await h.flow.ensureNeighbors();
        const doc=h.flow.getContents()[0].doc;
        touch(doc,'touchstart',200,0);touch(doc,'touchmove',150,16);touch(doc,'touchend',null,20);
        const released=h.flow.element.scrollTop;
        assert.equal(clock.pending.size,1);
        clock.step();const first=h.flow.element.scrollTop-released;
        clock.step();const second=h.flow.element.scrollTop-released-first;
        assert.ok(first>second&&second>0);
        for(let i=0;i<200&&clock.pending.size;i++){clock.step();await h.flow.ensureNeighbors()}
        assert.equal(clock.pending.size,0,'coasting naturally stops');
        assert.ok(h.flow.element.scrollTop>released+500);
        assert.ok(h.flow.entries.length<=7);
        near(h.flow.savedLocation.center.y,h.flow.location.center.y);
        await new Promise(r=>setTimeout(r,120));
        assert.equal(h.locations.at(-1).reason,'viewport');
    }finally{h.close();clock.close()}
});
test('new touch, wheel, selection, resize, suspension and close stop coasting; disabled motion stays still',async()=>{
    const h=harness(),clock=momentumClock();try{
        await h.flow.open(0,0);h.flow.activate();await h.flow.ensureNeighbors();
        const doc=h.flow.getContents()[0].doc;
        for(const stop of [
            ()=>touch(doc,'touchstart',100,10),
            ()=>h.flow.wheel({deltaX:0,deltaY:0,deltaMode:0,preventDefault(){},stopImmediatePropagation(){}}),
            ()=>h.flow.resize(),()=>h.flow.suspend(),
        ]) {
            h.flow.activate();h.flow.startMomentum(0,1);stop();
            const top=h.flow.element.scrollTop;clock.step();assert.equal(h.flow.element.scrollTop,top);
            assert.equal(clock.pending.size,0);
        }
        h.flow.activate();h.flow.startMomentum(0,1);
        const range=doc.createRange();range.selectNodeContents(doc.querySelector('span'));
        doc.getSelection().addRange(range);const top=h.flow.element.scrollTop;clock.step();
        assert.equal(h.flow.element.scrollTop,top);assert.equal(clock.pending.size,0);
        doc.getSelection().removeAllRanges();
        h.flow.canAnimate=()=>false;h.flow.startMomentum(0,1);assert.equal(clock.pending.size,0);
        h.flow.canAnimate=()=>true;h.flow.startMomentum(0,1);h.flow.canAnimate=()=>false;
        clock.step();assert.equal(clock.pending.size,0);
        h.flow.canAnimate=()=>true;h.flow.startMomentum(0,1);h.close();assert.equal(clock.pending.size,0);
    }finally{h.close();clock.close()}
});
test('paused finger, touch cancellation and finger-count changes do not launch stale momentum',async()=>{
    const h=harness(),clock=momentumClock();try{
        await h.flow.open(0,0);h.flow.activate();await h.flow.ensureNeighbors();
        const doc=h.flow.getContents()[0].doc;
        for(const type of ['touchend','touchcancel']) {
            touch(doc,'touchstart',200,0);touch(doc,'touchmove',150,16);
            touch(doc,type,null,type==='touchend'?200:20);
            assert.equal(clock.pending.size,0);
        }
        touch(doc,'touchstart',200,300,2);touch(doc,'touchmove',150,316,2);
        touch(doc,'touchend',150,320,1);touch(doc,'touchend',null,325);
        assert.equal(clock.pending.size,0);
        h.flow.startMomentum(0,1);clock.step();const top=h.flow.element.scrollTop;
        clock.step(500);assert.equal(h.flow.element.scrollTop,top);assert.equal(clock.pending.size,0);
        let bounded=100;
        Object.defineProperty(h.flow.element,'scrollTop',{configurable:true,get:()=>bounded,set:v=>{bounded=Math.max(0,Math.min(100,v))}});
        h.flow.startMomentum(0,1);clock.step();assert.equal(clock.pending.size,0,'stops at the scroll boundary');
    }finally{h.close();clock.close()}
});
function nativePdf(h) {
    const rendered=[], frames=[];
    for (const [index,section] of h.book.sections.entries()) {
        section.load=async()=>{throw Error('must not rasterize the unprocessed page')};
        section.loadFrame=async()=>{frames.push(index);return String(index)};
    }
    h.book.scrollRegionRenderer={render:async(request)=>{
        rendered.push(request);
        return {blob:new Blob(['prepared']),width:request.width,height:request.height};
    }};
    return {rendered,frames};
}
test('PDF scroll decodes the backing raster after it replaces the empty image', async () => {
    const h = harness();
    nativePdf(h);
    const create = h.flow.createFrame;
    const decoded = [];
    h.flow.createFrame = async (...args) => {
        const frame = await create(...args);
        frame.iframe.contentDocument.querySelector('img').decode = async function () {
            if (!this.src.startsWith('blob:')) throw new DOMException('Loading error', 'EncodingError');
            decoded.push(this.src);
        };
        return frame;
    };
    try {
        assert.equal(await h.flow.open(0, 0), true);
        assert.deepEqual(decoded, [h.flow.entries[0].baseUrl]);
    } finally { h.close(); }
});

test('desktop and mobile display densities prepare sharp pages before display without idle sharpening',async()=>{
    const oldDpr=globalThis.devicePixelRatio;
    try {
        for(const [userAgent,width,dpr,memory] of [
            ['Windows NT 10.0',1920,1,8],['Windows NT 10.0',1536,1.25,8],['Windows NT 10.0',1280,1.5,8],
            ['Macintosh',1200,2,8],['iPad',1024,2,4],['iPhone',440,3,4],
            ['Android',412,3.5,4],['OpenHarmony',450,3,4],['Linux',1440,1.25,8],
        ]) {
            const h=harness();nativePdf(h);h.bounds.width=width;globalThis.devicePixelRatio=dpr;
            h.flow.budget=new PdfRenderBudget({userAgent,hardwareConcurrency:8,deviceMemory:memory});
            const page={getViewport:({scale,rotation=0})=>({width:600*scale,height:800*scale,scale,rotation})};
            let details=0;
            h.book.scrollRegionRenderer.render=async request=>({blob:new Blob(['sharp']),...regionRenderPlan(page,request,true)});
            h.book.readingRegionRenderer.render=async()=>{details++;throw Error('unnecessary refinement')};
            try {
                await h.flow.open(10,0);h.flow.activate();await h.flow.ensureNeighbors();
                for(const e of h.flow.entries) {
                    assert.ok(e.baseUrl,'backing image decoded before showing a page');
                    assert.ok(e.baseRaster.width>=e.plan.width*dpr-2,userAgent);
                }
                await h.flow.refreshDetail();h.flow.pan(0,500);await h.flow.refreshDetail();
                assert.equal(details,0,'normal reading never replaces a low-resolution base with a sharp overlay');
                const bounded=()=>{
                    assert.ok(h.flow.entries.length<=7);
                    const pixels=h.flow.entries.reduce((sum,e)=>sum+e.baseRaster.width*e.baseRaster.height,0);
                    assert.ok(pixels<=h.flow.budget.maxBasePixels);
                };
                for(let i=0;i<12;i++){h.flow.pan(0,2000);await h.flow.ensureNeighbors();bounded()}
                const forward=h.flow.location.page;
                for(let i=0;i<12;i++){h.flow.pan(0,-2000);await h.flow.ensureNeighbors();bounded()}
                assert.ok(h.flow.location.page<forward);
            }finally{h.close()}
        }
    }finally{globalThis.devicePixelRatio=oldDpr}
    const pdf=await source('pdf');
    assert.match(pdf,/book\.scrollRegionRenderer = createPdfRegionRenderer\(pdf, \{\s*highResolution: true,/);
});

test('screen-density backing pixels are bounded on all platforms, with a smaller constrained-device budget',()=>{
    for(const userAgent of ['Windows NT 10.0','Android','OpenHarmony','iPhone','iPad','Macintosh','Linux']) {
        assert.equal(new PdfRenderBudget({userAgent}).maxBasePixels,4*8388608);
        assert.equal(new PdfRenderBudget({userAgent,deviceMemory:4,hardwareConcurrency:8}).maxBasePixels,3*8388608);
        assert.equal(new PdfRenderBudget({userAgent,deviceMemory:8,hardwareConcurrency:4}).maxBasePixels,3*8388608);
    }
});
test('short PDF pages still fill a tall mobile viewport under a constrained raster budget',async()=>{
    const h=harness();nativePdf(h);h.bounds.width=390;h.bounds.height=844;
    h.flow.budget=new PdfRenderBudget({userAgent:'Android',deviceMemory:4,hardwareConcurrency:8});
    const create=h.flow.createFrame;
    h.flow.createFrame=async(...args)=>({...await create(...args),height:200});
    try {
        await h.flow.open(0,0);h.flow.activate();await h.flow.ensureNeighbors();
        const last=h.flow.entries.at(-1);
        assert.ok(last.element.offsetTop+last.plan.height>=h.bounds.height,'short prepared pages fill the screen');
        assert.ok(h.flow.entries.length<=7);
    }finally{h.close()}
});
test('preprocessing depth uses measured time and conservative device limits',()=>{
    for(const device of [{},{deviceMemory:8,hardwareConcurrency:8}]) {
        const budget=new PdfRenderBudget(device);
        assert.equal(budget.ahead,1);
        budget.record(50);budget.record(60);assert.equal(budget.ahead,1);
        budget.record(70);assert.equal(budget.ahead,2);
        budget.record(1000);assert.equal(budget.ahead,1);assert.equal(budget.delay,250);
        const elapsed=budget.elapsed;budget.record(NaN);budget.record(-1);assert.equal(budget.elapsed,elapsed);
    }
    for(const device of [{deviceMemory:2,hardwareConcurrency:8},{deviceMemory:8,hardwareConcurrency:4}]) {
        const budget=new PdfRenderBudget(device);
        for(let i=0;i<10;i++)budget.record(5);
        assert.equal(budget.ahead,1);
    }
});
test('scroll prepares cropped/enhanced neighboring panels before display, without touching text or progress',async()=>{
    const h=harness({version:1,all:{preset:'single',autoCrop:true},pages:{}});
    const {rendered,frames}=nativePdf(h);
    const crop={x:.1,y:.15,width:.8,height:.7};
    h.book.cropRegionRenderer={render:async()=>({cropDetection:{detected:true,crop}})};
    h.flow.view.enhancement={ink:7,contrast:2,darken:1,whiten:1,sharpen:2,watermark:1};
    h.flow.view.display={hideWatermarks:true};
    let details=0;h.book.readingRegionRenderer.render=async()=>{details++;throw Error('unnecessary detail')};
    try {
        await h.flow.open(10,0);const original=h.flow.entries[0].iframe.contentDocument.querySelector('span').firstChild;
        h.flow.activate();const before=h.flow.location;await h.flow.ensureNeighbors();
        const next=h.flow.entries.find(e=>e.index===11);
        assert.ok(next?.baseUrl,'next page has a decoded processed backing image');
        assert.ok(frames.includes(11));assert.equal(h.flow.location.page,10);
        near(h.flow.location.center.y,before.center.y);
        for(const request of rendered){
            for(const key of Object.keys(crop))near(request.region[key],crop[key]);
            assert.deepEqual(request.enhancement,h.flow.view.enhancement);
            assert.equal(request.hideWatermarks,true);
        }
        const current=h.flow.entries.find(e=>e.index===10);
        assert.equal(current.iframe.contentDocument.querySelector('span').firstChild,original);
        const count=rendered.length;
        h.flow.pan(0,120);await h.flow.refreshDetail();
        assert.equal(details,0);assert.equal(rendered.length,count,'scrolling reuses the full-panel image');
        assert.ok(h.flow.entries.length<=7);
    }finally{h.close()}
});
test('tall PDF pages still prepare a next panel, faster devices prepare two and reverse travel prepares previous',async()=>{
    const h=harness();nativePdf(h);
    h.flow.view.zoom=3;h.flow.budget=new PdfRenderBudget({hardwareConcurrency:8,deviceMemory:8});
    try {
        await h.flow.open(20,0);h.flow.activate();await h.flow.ensureNeighbors();
        assert.ok(h.flow.entries.some(e=>e.index===21),'next page is outside two screen heights');
        for(let i=0;i<3;i++)h.flow.budget.record(10);
        await h.flow.ensureNeighbors();assert.ok(h.flow.entries.some(e=>e.index===22));
        h.flow.pan(0,-10);await h.flow.ensureNeighbors();assert.equal(h.flow.direction,-1);
        assert.ok(h.flow.entries.some(e=>e.index===18));assert.ok(h.flow.entries.length<=7);
    }finally{h.close()}
});
test('suspending/closing cancels unfinished processed pages and never installs their late pixels',async()=>{
    const h=harness();nativePdf(h);let finish,signal,entered;
    try {
        await h.flow.open(0,0);
        const started=new Promise(resolve=>entered=resolve);
        h.book.scrollRegionRenderer.render=(request,options)=>{
            signal=options.signal;entered();return new Promise(resolve=>finish=()=>resolve({blob:new Blob(['late']),width:600,height:800}));
        };
        h.flow.activate();const neighbors=h.flow.ensureNeighbors();await started;
        h.flow.suspend();assert.equal(signal.aborted,true);
        finish();await neighbors;
        assert.equal(h.flow.entries.length,1);assert.deepEqual(h.states,[]);
        assert.equal(h.flow.element.children.length,1);
        h.close();assert.equal(h.flow.element.children.length,0);
    }finally{h.close()}
});
test('processed base reuse invalidates on enhancement/crop changes; zoom requests only visible detail',async()=>{
    const h=harness();const {rendered}=nativePdf(h);const details=[];
    h.book.readingRegionRenderer.render=async request=>{details.push(request);return {blob:new Blob(['detail'])}};
    try {
        await h.flow.open(0,0);h.flow.active=true;const e=h.flow.entries[0];
        const first=e.baseUrl;await h.flow.prepareBase(e);assert.equal(rendered.length,1);
        h.flow.view.enhancement={ink:7};await h.flow.prepareBase(e);
        assert.equal(rendered.length,2);assert.notEqual(e.baseUrl,first);
        e.crop={x:.1,y:.1,width:.8,height:.8};await h.flow.prepareBase(e);
        assert.equal(rendered.length,3);assert.deepEqual(rendered.at(-1).region,e.crop);
        h.flow.resize({...h.flow.view,zoom:15});await h.flow.refreshDetail();
        assert.equal(details.length,1);assert.ok(details[0].region.height<.1);
        assert.ok(details[0].region.width<.15);assert.equal(rendered.length,3);
    }finally{h.close()}
});
test('background reader does not launch neighbor preprocessing',async()=>{
    const h=harness();const {rendered}=nativePdf(h);
    try {
        await h.flow.open(0,0);h.flow.canPrepare=()=>false;h.flow.activate();await h.flow.ensureNeighbors();
        assert.equal(rendered.length,1);assert.equal(h.flow.entries.length,1);
        h.flow.canPrepare=()=>true;await h.flow.ensureNeighbors();assert.ok(rendered.length>1);
    }finally{h.close()}
});
test('processed page failures keep current pixels and recover on retry',async()=>{
    const h=harness();nativePdf(h);const render=h.book.scrollRegionRenderer.render;
    try {
        await h.flow.open(0,0);const first=h.flow.entries[0],url=first.baseUrl;
        h.book.scrollRegionRenderer.render=async request=>{if(request.page===1)throw Error('encode failed');return render(request)};
        h.flow.activate();await h.flow.ensureNeighbors();
        assert.equal(h.flow.entries[0],first);assert.equal(first.baseUrl,url);assert.deepEqual(h.states,['failed']);
        h.book.scrollRegionRenderer.render=render;assert.equal(await h.flow.retry(),true);
        assert.ok(h.flow.entries.some(e=>e.index===1&&e.baseUrl));
    }finally{h.close()}
});
test('scroll recycles prepared bitmap URLs and close releases every retained base image',async()=>{
    const h=harness();nativePdf(h);const revoke=URL.revokeObjectURL,revoked=new Set(),allocated=new Set();
    URL.revokeObjectURL=url=>{revoked.add(url);revoke(url)};
    try {
        await h.flow.open(10,0);h.flow.activate();await h.flow.ensureNeighbors();
        for(let i=0;i<16;i++){
            for(const e of h.flow.entries)allocated.add(e.baseUrl);
            h.flow.pan(0,600);await h.flow.ensureNeighbors();assert.ok(h.flow.entries.length<=7);
        }
        for(const e of h.flow.entries)allocated.add(e.baseUrl);
        assert.ok(revoked.size>0);
        for(const e of h.flow.entries)assert.ok(!revoked.has(e.baseUrl));
        h.close();for(const url of allocated)assert.ok(revoked.has(url));
    }finally{h.close();URL.revokeObjectURL=revoke}
});
test.after(()=>{children.forEach(child=>child.window.close());dom.window.close()});

test('unchanged detail reuses its image while pan and enhancement refresh it',async()=>{
 const h=harness();nativePdf(h);h.flow.view.zoom=3;
 h.flow.ensureNeighbors=async()=>{};
 let renders=0,fail=false;
 h.book.readingRegionRenderer.render=async()=>{renders++;if(fail)throw Error('retry');return {blob:new Blob(['detail'])}};
 try{
   await h.flow.open(10,0);h.flow.activate();clearTimeout(h.flow.timer);
   const e=h.flow.current;e.baseRaster=null;
   await h.flow.refreshDetail();assert.equal(renders,1);const image=e.detail,url=e.url;
   for(let i=0;i<5;i++)await h.flow.refreshDetail();
   assert.equal(renders,1);assert.equal(e.detail,image);assert.equal(e.url,url);
   h.flow.view.enhancement={contrast:10};fail=true;
   await h.flow.refreshDetail();assert.equal(renders,2);assert.equal(e.detail,image);
   fail=false;await h.flow.refreshDetail();assert.equal(renders,3);assert.notEqual(e.detail,image);
   h.flow.element.scrollTop+=30;await h.flow.refreshDetail();assert.equal(renders,4);
 }finally{h.close()}
});
