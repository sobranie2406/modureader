import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {runInNewContext} from 'node:vm';
const require = createRequire(`${process.env.MODU_JSDOM_ROOT || '/private/tmp/modu-119-js-tests'}/package.json`);
const {JSDOM} = require('jsdom');
const dom = new JSDOM('<!doctype html><body></body>', {url:'https://reader.test/', resources:'usable'});
for (const key of ['document','HTMLElement','customElements','CustomEvent']) globalThis[key] = dom.window[key];
globalThis.devicePixelRatio = 1;
globalThis.CSSStyleSheet = class {replaceSync() {}};
const resizeObservers = [];
globalThis.ResizeObserver = class {constructor(callback){this.callback=callback;resizeObservers.push(this)} observe() {} unobserve() {}};
dom.window.HTMLElement.prototype.getBoundingClientRect = () => ({left:0,top:0,right:800,bottom:600,width:800,height:600});
// Each iframe has its own prototype; decode is installed by the simulated source.
const uri = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const source = name => readFile(new URL(`../assets/foliate-js/src/${name}.js`, import.meta.url), 'utf8');
const CFI = await import(uri(await source('epubcfi')));
const {annotationPointMapper, annotationRect, annotationRangeRects} = await import(uri(await source('annotation-geometry')));
const Overlayer = runInNewContext((await source('overlayer')).replace(/^import .*$/gm, '')
    .replace('export class Overlayer', 'class Overlayer') + '\nOverlayer', {
    document, Range: dom.window.Range, navigator: {userAgent:'Chrome'}, window: dom.window,
    annotationPointMapper, annotationRect, annotationRangeRects,
    SearchHighlighter: class {clear() {} remove() {} redraw() {}},
});
const geometry = uri(await source('document-regions'));
const layout = uri((await source('pdf-reading-layout')).replace("'./document-regions.js'", JSON.stringify(geometry)));
const viewport = uri((await source('pdf-reading-viewport')).replace("'./document-regions.js'", JSON.stringify(geometry))
    .replace("'./document-reading-options.js'", JSON.stringify(uri(await source('document-reading-options'))))
    .replace("'./document-image-processing.js'", JSON.stringify(uri(await source('document-image-processing')))));
const scrollLayout = uri((await source('pdf-scroll-layout'))
    .replace("'./pdf-reading-viewport.js'", JSON.stringify(viewport))
    .replace("'./document-regions.js'", JSON.stringify(geometry)));
const scrollReader = uri((await source('pdf-scroll-reader'))
    .replace("'./pdf-zoom-input.js'", JSON.stringify(uri(await source('pdf-zoom-input'))))
    .replace("'./pdf-render-budget.js'", JSON.stringify(uri(await source('pdf-render-budget'))))
    .replace("'./transient-scrollbar.js'", JSON.stringify(uri(await source('transient-scrollbar'))))
    .replace("'./pdf-reading-layout.js'", JSON.stringify(layout))
    .replace("'./pdf-scroll-layout.js'", JSON.stringify(scrollLayout)));
await import(uri((await source('fixed-layout'))
    .replace("'./pdf-zoom-input.js'", JSON.stringify(uri(await source('pdf-zoom-input'))))
    .replace("'./pdf-render-budget.js'", JSON.stringify(uri(await source('pdf-render-budget'))))
    .replace("'./document-reading-options.js'", JSON.stringify(uri(await source('document-reading-options'))))
    .replace("'./frame-script-policy.js'", JSON.stringify(uri(await source('frame-script-policy'))))
    .replace("'./pdf-reading-layout.js'", JSON.stringify(layout))
    .replace("'./pdf-reading-viewport.js'", JSON.stringify(viewport))
    .replace("'./pdf-scroll-reader.js'", JSON.stringify(scrollReader))));
const config = {version:1,all:{preset:'four'},pages:{}};
const html = 'data:text/html,' + encodeURIComponent('<meta name="viewport" content="width=600,height=800"><img data-document-base><div class="textLayer"><span>Original text</span></div>');
function harness() {
    const renderer = document.createElement('foliate-fxl'); document.body.append(renderer);
    const events = [];renderer.addEventListener('relocate', e => events.push(e.detail));
    const source = {cancel() {}, clear() {}, render: async () => {
        // Candidate frame is intentionally not returned by getContents().
        // Use the load event to install decode in its own realm instead.
        return {blob:new Blob(['png'])};
    }};
    const book = {sections:Array.from({length:3}, () => ({load:async () => html})),
        rendition:{spread:'none'}, readingRegionRenderer:source, releasePageResources() {source.cancel()}};
    renderer.open(book);
    return {renderer,source,events,close:()=>{renderer.destroy();renderer.remove()}};
}
// jsdom does not navigate frames inside shadow roots. Simulate only that host
// operation; renderer navigation/commit/cancellation and DOM updates remain real.
const frames=[];
const createElement = dom.window.Document.prototype.createElement;
dom.window.Document.prototype.createElement = function(name, ...rest) {
    const el = createElement.call(this,name,...rest);
    if(name==='iframe') Object.defineProperty(el,'src',{set(value) {
        const child=new JSDOM(decodeURIComponent(value.split(',').slice(1).join(',')),{url:value});
        frames.push(child);
        child.window.Range.prototype.getClientRects = () => [{left:10,top:20,right:110,bottom:40,width:100,height:20}];
        child.window.HTMLImageElement.prototype.decode=async function() {};
        Object.defineProperty(el,'contentDocument',{value:child.window.document,configurable:true});
        Object.defineProperty(el,'contentWindow',{value:child.window,configurable:true});
        queueMicrotask(()=>el.dispatchEvent(new dom.window.Event('load')));
    }});
    return el;
};

test('PDF marks survive page recycling, crop, rotation and switching between page and scroll modes', async () => {
    const h=harness(), layers=[], saved=new Map();
    for(const section of h.renderer.book.sections) section.loadFrame=section.load;
    h.renderer.addEventListener('create-overlayer', ({detail:{doc,index,attach}})=>{
        const layer=new Overlayer(doc);attach(layer);layers.push(layer);
        for(const [key, note] of saved) if(note.index===index)
            layer.add(key,CFI.toRange(doc,CFI.parse(note.cfi)),Overlayer[note.type],{color:note.color});
    });
    try {
        await h.renderer.setPdfLayout({version:1,pages:{}},true);
        await h.renderer.goTo({index:0});
        let {doc,overlayer}=h.renderer.getContents()[0];
        assert.equal(overlayer.element.ownerDocument,doc);
        const range=doc.createRange();
        range.setStart(doc.querySelector('.textLayer span').firstChild,0);
        range.setEnd(range.startContainer,range.startContainer.length);
        const cfi=CFI.fromRange(range);
        saved.set('note',{index:0,cfi,type:'highlight',color:'#f90'});
        overlayer.add('note',range,Overlayer.highlight,{color:'#f90'});
        assert.ok(overlayer.element.querySelector('rect'));
        assert.equal(overlayer.hitTest({x:50,y:30})[0],'note');
        await h.renderer.next();
        assert.equal(overlayer.element.children.length,0,'recycled layers are disposed');
        await h.renderer.prev();
        for(const mode of ['single','scroll','single']) {
            await h.renderer.setPdfLayout(config,true);
            await h.renderer.setPdfView({mode,rotation:90});
            ({doc,overlayer}=h.renderer.getContents().find(x=>x.index===0));
            assert.equal(CFI.toRange(doc,CFI.parse(cfi)).toString(),'Original text',mode+' '+cfi);
            assert.ok(overlayer.element.querySelector('rect'),'saved mark restored in '+mode);
            assert.equal(overlayer.element.ownerDocument,doc);
        }
        saved.get('note').type='underline';
        overlayer.remove('note');
        overlayer.add('note',CFI.toRange(doc,CFI.parse(cfi)),Overlayer.underline,{color:'#08f'});
        assert.ok(overlayer.element.children.length);
        saved.delete('note');overlayer.remove('note');
        await h.renderer.goTo({index:1});await h.renderer.goTo({index:0});
        assert.equal(h.renderer.getContents()[0].overlayer.element.children.length,0,'deleted marks stay deleted');
    } finally {h.close()}
    for(const layer of layers) assert.equal(layer.element.children.length,0);
});

test('zoom and pan remember each original page, inherit new pages and reset without losing crop', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout({version:1,pages:{}},true);
        await h.renderer.goTo({index:0});
        assert.equal(h.renderer.zoomPdfView(2),true);
        h.renderer.panPdfView(50,90);
        const first={...h.renderer.pdfRegionLocation};
        await h.renderer.next();
        assert.equal(h.renderer.pdfRegionLocation.zoom,2);
        assert.deepEqual(h.renderer.pdfRegionLocation.center,first.center);
        h.renderer.zoomPdfView(3);
        await h.renderer.prev();
        assert.equal(h.renderer.pdfRegionLocation.zoom,2);
        assert.deepEqual(h.renderer.pdfRegionLocation.center,first.center);
        await h.renderer.next();
        assert.equal(h.renderer.pdfRegionLocation.zoom,3);
        const signature=h.renderer.pdfRegionLocation.signature;
        assert.equal(h.renderer.zoomPdfView(50),true);
        assert.equal(h.renderer.pdfRegionLocation.zoom,8);
        h.renderer.zoomPdfView(1,true);
        assert.equal(h.renderer.pdfRegionLocation.signature,signature);
        assert.equal(h.renderer.pdfRegionLocation.zoom,1);
        assert.equal(h.renderer.zoomPdfView(NaN),false);
        h.renderer.setPdfPageViews({'0:0':first});
        await h.renderer.goTo({index:0});
        assert.equal(h.renderer.pdfRegionLocation.zoom,2);
    } finally {h.close()}
});

test('two-finger zoom and enlarged-page drag use existing pixels without starting page turns', async () => {
    const h=harness();let renders=0;
    const render=h.source.render;h.source.render=async(...a)=>{renders++;return render(...a)};
    try {
        await h.renderer.setPdfLayout({version:1,pages:{}},true);await h.renderer.goTo({index:0});
        const doc=h.renderer.getContents()[0].doc, before=renders;
        const send=(type,points)=>{
            const e=new doc.defaultView.Event(type,{bubbles:true,cancelable:true});
            Object.defineProperty(e,'touches',{value:points.map(([screenX,screenY])=>({screenX,screenY}))});
            doc.dispatchEvent(e);return e.defaultPrevented;
        };
        assert.equal(send('touchstart',[[100,100],[200,100]]),true);
        assert.equal(send('touchmove',[[50,100],[250,100]]),true);
        assert.equal(h.renderer.pdfRegionLocation.zoom,2);
        send('touchend',[]);
        const center=h.renderer.pdfRegionLocation.center;
        send('touchstart',[[200,300]]);
        assert.equal(send('touchmove',[[200,200]]),true);
        send('touchend',[]);
        assert.ok(h.renderer.pdfRegionLocation.center.y>center.y);
        assert.equal(h.renderer.index,0);
        assert.equal(renders,before,'gesture transforms pixels; refinement is debounced');
    } finally {h.close()}
});

test('formal renderer commits panel locations, returns to source page and retains text DOM', async () => {
    const h=harness();
    try {
        assert.equal(h.renderer.index,-1);
        await h.renderer.setPdfLayout(config,true);
        await h.renderer.goTo({index:0});
        assert.equal(h.renderer.pdfRegionLocation.panel,0);
        assert.equal(h.renderer.getContents()[0].doc.querySelector('.textLayer').textContent,'Original text');
        for(let n=0;n<4;n++) await h.renderer.next();
        assert.equal(h.renderer.index,1);assert.equal(h.renderer.pdfRegionLocation.panel,0);
        await h.renderer.prev();assert.equal(h.renderer.index,0);assert.equal(h.renderer.pdfRegionLocation.panel,3);
        await h.renderer.setPdfLayout(config,false);
        assert.equal(h.renderer.pdfReading,false);assert.equal(h.renderer.index,0);
        assert.equal(h.events.at(-1).pdfRegion,null);
    } finally {h.close()}
});

test('desktop rectangle zoom is explicit and retains the original text layer', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout({version:1,pages:{}},true);await h.renderer.goTo({index:0});
        const doc=h.renderer.getContents()[0].doc;
        const send=(type,x,y,buttons=1)=>{
            const e=new doc.defaultView.MouseEvent(type,{clientX:x,clientY:y,screenX:x,screenY:y,button:0,buttons,bubbles:true,cancelable:true});
            doc.dispatchEvent(e);return e.defaultPrevented;
        };
        assert.equal(send('mousedown',50,50),false);
        h.renderer.setPdfBoxZoom(true);
        assert.equal(send('mousedown',50,50),true);
        send('mousemove',250,250);send('mouseup',250,250,0);
        assert.equal(h.renderer.pdfRegionLocation.zoom,4);
        assert.equal(doc.querySelector('.textLayer').textContent,'Original text');
        assert.equal(doc.querySelectorAll('div[style*="2147483647"]').length,0);
    } finally {h.close()}
});

for(const rotation of [0,90,180,270]) test(`rectangle zoom centers the selected source area inside crop at ${rotation} degrees`, async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout({version:1,all:{crop:{x:.1,y:.1,width:.8,height:.8}},pages:{}},true);
        await h.renderer.goTo({index:0});
        h.renderer.setPdfView({zoom:1,rotation});h.renderer.setPdfBoxZoom(true);
        const doc=h.renderer.getContents()[0].doc;
        const send=(type,x,y)=>doc.dispatchEvent(new doc.defaultView.MouseEvent(type,
            {clientX:x,clientY:y,screenX:x,screenY:y,button:0,buttons:type==='mouseup'?0:1,bubbles:true,cancelable:true}));
        send('mousedown',200,300);send('mousemove',300,500);send('mouseup',300,500);
        const location=h.renderer.pdfRegionLocation;
        assert.ok(Math.abs(location.zoom-3.2)<1e-8);
        assert.ok(Math.abs(location.center.x-250/600)<1e-8);
        assert.ok(Math.abs(location.center.y-.5)<1e-8);
        assert.equal(h.events.at(-1).reason,'viewport','mouse release persists immediately');
        await h.renderer.next();await h.renderer.prev();
        assert.deepEqual(h.renderer.pdfRegionLocation,location);
    } finally {h.close()}
});

test('zoom/pan persistence is not cancelled by a resize or immediate close', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout({version:1,pages:{}},true);await h.renderer.goTo({index:0});
        h.renderer.zoomPdfView(3);h.renderer.panPdfView(50,70);
        const expected={...h.renderer.pdfRegionLocation};
        resizeObservers.at(-1).callback();
        await new Promise(resolve=>setTimeout(resolve,140));
        assert.deepEqual(h.events.at(-1).pdfRegion,expected);
        assert.equal(h.events.at(-1).reason,'viewport');
        h.renderer.panPdfView(-20,30);
        const closing={...h.renderer.pdfRegionLocation};
        h.renderer.destroy();
        assert.deepEqual(h.events.at(-1).pdfRegion,closing);
    } finally {h.close()}
});

test('source-page arrows move only inside the enlarged crop and never change page', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout({version:1,pages:{}},true);await h.renderer.goTo({index:0});
        assert.equal(h.renderer.panPdfArrow('arrowdown'),false);
        h.renderer.zoomPdfView(3);h.renderer.panPdfView(200,200);
        const center=h.renderer.pdfRegionLocation.center;
        h.renderer.panPdfArrow('arrowright');assert.ok(h.renderer.pdfRegionLocation.center.x>center.x);
        h.renderer.panPdfArrow('arrowleft');
        assert.ok(Math.abs(h.renderer.pdfRegionLocation.center.x-center.x)<1e-8);
        h.renderer.panPdfArrow('arrowdown');assert.ok(h.renderer.pdfRegionLocation.center.y>center.y);
        h.renderer.panPdfArrow('arrowup');
        for(let i=0;i<60;i++)assert.equal(h.renderer.panPdfArrow('arrowdown'),true);
        assert.equal(h.renderer.index,0);
        const bottom=h.renderer.pdfRegionLocation.center;
        h.renderer.panPdfArrow('arrowdown');assert.deepEqual(h.renderer.pdfRegionLocation.center,bottom);
    } finally {h.close()}
});

for (const [swipe, dx, dy, expected] of [
    ['horizontal', -150, 0, 2], ['horizontal', 150, 0, 0],
    ['reverse', -150, 0, 0], ['vertical', 0, -150, 2], ['tap', -150, 0, 1],
]) test(`PDF single-page ${swipe} gesture (${dx},${dy}) reaches page ${expected}`, async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout({version:1,pages:{}},true);
        await h.renderer.goTo({index:1});
        await h.renderer.setPdfView({zoom:1,display:{swipe}});
        const doc=h.renderer.getContents()[0].doc;
        const send=(type,points)=>{const e=new doc.defaultView.Event(type,{bubbles:true,cancelable:true});
            Object.defineProperty(e,'touches',{value:points.map(([screenX,screenY])=>({screenX,screenY}))});doc.dispatchEvent(e);return e;};
        // A tap remains available to the normal click/page-region handler.
        send('touchstart',[[200,200]]);
        assert.equal(send('touchend',[]).defaultPrevented,false);
        assert.equal(h.renderer.index,1);
        send('touchstart',[[200,200]]);
        send('touchmove',[[200+dx,200+dy]]);send('touchend',[]);
        assert.equal(doc.dispatchEvent(new doc.defaultView.MouseEvent('click',
            {bubbles:true,cancelable:true})),false,'swipe must not also trigger click paging');
        await new Promise(resolve=>setImmediate(resolve));
        assert.equal(h.renderer.index,expected);
    } finally {h.close()}
});

test('PDF text selection keeps swipe gestures from turning a page', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout({version:1,pages:{}},true);
        await h.renderer.goTo({index:1});
        const doc=h.renderer.getContents()[0].doc;
        const range=doc.createRange();range.selectNodeContents(doc.querySelector('.textLayer span'));
        doc.getSelection().addRange(range);
        for(const [type,points] of [['touchstart',[[200,200]]],['touchmove',[[50,200]]],['touchend',[]]]) {
            const e=new doc.defaultView.Event(type,{bubbles:true,cancelable:true});
            Object.defineProperty(e,'touches',{value:points.map(([screenX,screenY])=>({screenX,screenY}))});
            doc.dispatchEvent(e);
            assert.equal(e.defaultPrevented,false);
        }
        await new Promise(resolve=>setImmediate(resolve));
        assert.equal(h.renderer.index,1);
        assert.equal(doc.getSelection().toString(),'Original text');
    } finally {h.close()}
});

test('PDF night mode inverts only page bitmaps, including new detail tiles, without rerasterizing', async () => {
    const h=harness();let renders=0;
    for(const section of h.renderer.book.sections) section.loadFrame=section.load;
    h.source.render=async()=>{renders++;return {blob:new Blob(['png'])}};
    try {
        h.renderer.setPdfNightMode(true);
        await h.renderer.goTo({index:0});
        for(const mode of ['original','single','scroll']) {
            if(mode!=='original') {
                await h.renderer.setPdfLayout(config,true);
                await h.renderer.setPdfView({mode,rotation:90});
            }
            const {doc}=h.renderer.getContents()[0], win=doc.defaultView;
            const image=doc.querySelector('[data-document-base]');
            const text=doc.querySelector('.textLayer span');
            const range=doc.createRange();range.selectNodeContents(text.firstChild);
            const cfi=CFI.fromRange(range), originalSource=image.src;
            const mark=doc.createElementNS('http://www.w3.org/2000/svg','svg');
            mark.style.color='rgb(0, 128, 255)';doc.body.append(mark);
            const before=renders;
            for(const night of [true,false,true]) {
                h.renderer.setPdfNightMode(night);
                assert.equal(win.getComputedStyle(image).filter,night?'invert(1)':'');
                assert.equal(h.renderer.style.backgroundColor,night?'rgb(0, 0, 0)':'');
                if(night) assert.equal(win.getComputedStyle(doc.body).backgroundColor,'rgb(0, 0, 0)');
                assert.equal(doc.querySelectorAll('#modu-pdf-night-mode').length,night?1:0);
                assert.equal(win.getComputedStyle(text).filter,'');
                assert.equal(win.getComputedStyle(mark).filter,'');
                assert.equal(mark.style.color,'rgb(0, 128, 255)');
                assert.equal(CFI.toRange(doc,CFI.parse(cfi)).toString(),'Original text');
                assert.equal(image.src,originalSource);
            }
            const detail=doc.createElement('img');detail.setAttribute('data-document-detail','');doc.body.append(detail);
            assert.equal(win.getComputedStyle(detail).filter,'invert(1)');
            assert.equal(renders,before,'toggling is display-only');
            await h.renderer.next();
            for(const {doc:next} of h.renderer.getContents())
                assert.ok(next.getElementById('modu-pdf-night-mode'),'new/recycled pages inherit night mode');
            h.renderer.setPdfNightMode(false);
            for(const {doc:next} of h.renderer.getContents())
                assert.equal(next.getElementById('modu-pdf-night-mode'),null);
        }
    } finally {h.close()}
});

test('PDF night filter is not applied to ordinary fixed-layout books', async () => {
    const h=harness();
    try {
        h.renderer.setPdfNightMode(true);
        await h.renderer.goTo({index:0});
        const {doc}=h.renderer.getContents()[0];
        assert.equal(doc.getElementById('modu-pdf-night-mode'),null);
        assert.equal(h.renderer.style.backgroundColor,'');
        assert.equal(doc.defaultView.getComputedStyle(doc.querySelector('img')).filter,'');
    } finally {h.close()}
});

test('PDF formal single-page path uses text frame without the redundant full-page raster', async () => {
    const h=harness();let frames=0,full=0;
    for(const section of h.renderer.book.sections) {
        section.load=async()=>{full++;return html};
        section.loadFrame=async()=>{frames++;return html};
    }
    try {
        await h.renderer.setPdfLayout({version:1,pages:{}},true);
        await h.renderer.goTo({index:0});await h.renderer.next();
        assert.equal(frames,2);assert.equal(full,0);
        assert.equal(h.renderer.getContents()[0].doc.querySelector('.textLayer').textContent,'Original text');
        await h.renderer.setPdfLayout({version:1,pages:{}},false);
        assert.equal(full,1,'ordinary fixed-layout fallback still uses original page');
    } finally {h.close()}
});

test('ordinary fixed-layout books never invoke the PDF frame optimization', async () => {
    const h=harness();let frames=0,full=0;
    h.renderer.book.readingRegionRenderer=undefined;
    for(const section of h.renderer.book.sections) {
        section.load=async()=>{full++;return html};
        section.loadFrame=async()=>{frames++;throw new Error('PDF-only frame')};
    }
    try {
        assert.equal(await h.renderer.setPdfLayout(config,true),false);
        await h.renderer.goTo({index:0});await h.renderer.next();
        assert.equal(frames,0);assert.ok(full>=2);assert.equal(h.renderer.pdfReading,false);
    } finally {h.close()}
});

test('native PDF prefetch warms only the next page without relocating and stops on close', async () => {
    const h=harness(), rendered=[];
    for(const section of h.renderer.book.sections) section.loadFrame=async()=>html;
    h.source.render=async request=>{rendered.push(request.page);return {blob:new Blob(['png']),width:600,height:800}};
    try {
        await h.renderer.setPdfLayout({version:1,pages:{}},true);
        await h.renderer.goTo({index:0});
        const events=h.events.length;
        await new Promise(resolve=>setTimeout(resolve,1100));
        assert.deepEqual(rendered,[0,1],'no redundant detail raster; only one prefetched page');
        assert.equal(h.renderer.index,0);assert.equal(h.events.length,events);
        await h.renderer.next();
        h.close();
        const count=rendered.length;
        await new Promise(resolve=>setTimeout(resolve,1100));
        assert.equal(rendered.length,count,'close cancels delayed prefetch');
    } finally {if(h.renderer.isConnected)h.close()}
});

test('pending PDF prefetch yields to foreground navigation and cannot commit stale pages', async()=>{
    const h=harness(); let pending, cancelled=0;
    for(const section of h.renderer.book.sections) section.loadFrame=async()=>html;
    h.source.cancel=()=>{if(pending){cancelled++;pending();pending=null}};
    h.source.render=async request=>{
        if(request.page===1)await new Promise(resolve=>pending=resolve);
        return {blob:new Blob(['png']),width:600,height:800};
    };
    try {
        await h.renderer.setPdfLayout({version:1,pages:{}},true);await h.renderer.goTo({index:0});
        await new Promise(resolve=>setTimeout(resolve,1100));assert.ok(pending);
        await h.renderer.goTo({index:2});
        assert.equal(cancelled,1);assert.equal(h.renderer.index,2);
        assert.equal(h.events.at(-1).index,2);
    } finally {h.close()}
});
test('single-page preprocessing follows grid order, including the next panel on the same original page',async()=>{
    const h=harness(),requests=[];
    for(const section of h.renderer.book.sections)section.loadFrame=async()=>html;
    h.source.render=async request=>{requests.push(request);return {blob:new Blob(['png']),width:600,height:800}};
    try {
        await h.renderer.setPdfLayout(config,true);await h.renderer.goTo({index:0});
        await new Promise(resolve=>setTimeout(resolve,300));
        assert.equal(requests.length,2);assert.deepEqual(requests.map(r=>r.page),[0,0]);
        assert.equal(requests[0].region.x,0);assert.equal(requests[1].region.x,.5);
        assert.equal(h.renderer.pdfRegionLocation.panel,0);
    }finally{h.close()}
});
for (const scanned of [false, true]) test(`${scanned ? 'scanned ebook' : 'PDF'} image clicks navigate the real renderer, including replacement frames`, async () => {
    const viewSource=await source('view');
    const handlers=viewSource.slice(viewSource.indexOf('  #handleLinks('),viewSource.indexOf('  async addAnnotation('));
    const h=harness(), clicks=[];
    let navigation=Promise.resolve();
    const View=runInNewContext(`class View {
        #emit(type,detail) { emit(type,detail); return false; }
        install(doc) { this.#handleLinks(doc,0); this.#handleClick(doc); this.#handleImage(doc); }
        ${handlers}
    }; View`,{window:{innerWidth:800,isFootNoteOpen:()=>false},imageFootnoteText:()=>null,
        setTimeout,clearTimeout,console,emit:(type,detail)=>{
            clicks.push(type);
            // Same normalized left/right routing as the host, using the actual
            // crop/scale transform attached by the fixed-layout renderer.
            if(type==='click-view') navigation=detail.x>400?h.renderer.next():h.renderer.prev();
        }});
    const view=new View();view.book=h.renderer.book;view.scannedImageDocument=scanned;
    h.renderer.addEventListener('load',e=>view.install(e.detail.doc));
    try {
        await h.renderer.setPdfLayout({version:1,all:{preset:'single'},pages:{}},true);
        await h.renderer.goTo({index:0});
        for(const [x,expected] of [[550,1],[550,2],[50,1],[50,0]]) {
            const doc=h.renderer.getContents()[0].doc;
            doc.querySelector('img').dispatchEvent(new doc.defaultView.MouseEvent('click',
                {bubbles:true,cancelable:true,clientX:x,clientY:400}));
            await navigation;
            assert.equal(h.renderer.index,expected);
        }
        assert.deepEqual(clicks,Array(4).fill('click-view'),'no preview and no duplicate turns');
    } finally {h.close()}
});
test('single-page turns use independently detected bounds, and failed detection shows original', async () => {
    const h=harness(), detections=[], rendered=[];
    const boxes=[{x:.1,y:.2,width:.8,height:.6},{x:.2,y:.1,width:.6,height:.8}];
    try {
        h.renderer.book.cropRegionRenderer={render:async request=>{
            detections.push(request);
            if(request.page===2)throw Error('scan failed');
            return {cropDetection:{detected:true,crop:boxes[request.page]}};
        }};
        h.source.render=async request=>{rendered.push(request);return {blob:new Blob(['png'])}};
        await h.renderer.setPdfLayout({version:1,all:{autoCrop:true,autoMargin:.05},pages:{}},true);
        await h.renderer.goTo({index:0});await h.renderer.next();await h.renderer.next();
        for(let page=0;page<3;page++) {
            const r=rendered.find(x=>x.page===page);
            const {x,y,width,height}=r.region;
            assert.deepEqual({x,y,width,height},boxes[page]??{x:0,y:0,width:1,height:1});
        }
        assert.deepEqual(detections.map(x=>x.page),[0,1,2]);
        assert.ok(detections.every(x=>x.margin===.05));
        await h.renderer.prev();assert.equal(detections.length,3,'return uses this page’s cached coordinates');
        assert.equal(h.renderer.getContents()[0].doc.querySelector('.textLayer').textContent,'Original text');
    } finally {h.close()}
});
test('scroll loads crop each original page and preserve text-section fallback', async () => {
    const {PdfScrollReader}=await import(scrollReader);
    const calls=[],elements=[];
    const book={sections:[0,1,2].map(()=>({load:async()=>html})),nativeTextPages:new Set([2]),
        cropRegionRenderer:{render:async r=>{calls.push(r.page);return {cropDetection:{detected:true,
            crop:{x:r.page===0?.1:.2,y:.1,width:r.page===0?.8:.6,height:.8}}}}}};
    const flow=new PdfScrollReader({book,layout:{version:1,all:{autoCrop:true},pages:{}},view:{},
        createFrame:async page=>{
            const iframe=document.createElement('iframe');iframe.src=html;
            if(page===2)iframe.contentDocument.documentElement.dataset.documentImage='false';
            const element=document.createElement('div');elements.push(element);
            return {index:page,element,iframe,width:600,height:800};
        }});
    try {
        const a=await flow.load({page:0,panel:0}),b=await flow.load({page:1,panel:0}),c=await flow.load({page:2,panel:0});
        assert.equal(a.crop.x,.1);assert.equal(b.crop.x,.2);assert.equal(c.crop.width,1);
        assert.equal(c.fallback,true);assert.deepEqual(calls,[0,1]);
    } finally {flow.destroy();elements.forEach(el=>el.remove())}
});
test('render failure preserves committed frame/location and retry uses intended target', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout(config,true);await h.renderer.goTo({index:0});
        const doc=h.renderer.getContents()[0].doc;const count=h.events.length;
        const render=h.source.render;h.source.render=async()=>{throw Error('injected')};
        assert.equal(await h.renderer.next(),false);
        assert.equal(h.events.length,count);assert.equal(h.renderer.pdfRegionLocation.panel,0);
        assert.equal(h.renderer.getContents()[0].doc,doc);
        h.source.render=render;await h.renderer.retryNavigation();
        assert.equal(h.renderer.pdfRegionLocation.panel,1);
    } finally {h.close()}
});
test('late render cannot replace newer navigation or a closed reader', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout(config,true);await h.renderer.goTo({index:0});
        let release,started;
        const entered=new Promise(r=>started=r);const render=h.source.render;
        h.source.render=()=>{started();return new Promise(r=>release=()=>r({blob:new Blob(['late'])}))};
        const old=h.renderer.next();await entered;
        h.source.render=render;
        await h.renderer.goTo({index:2});release();
        assert.equal(await old,false);assert.equal(h.renderer.index,2);
        const events=h.events.length;
        h.close();assert.equal(await h.renderer.next(),false);assert.equal(h.events.length,events);
    } finally {h.close()}
});
test('failed layout change leaves old layout usable and does not install a stale retry', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout(config,true);await h.renderer.goTo({index:0});
        const before=h.renderer.pdfRegionLocation;const render=h.source.render;
        h.source.render=async()=>{throw Error('injected')};
        assert.equal(await h.renderer.setPdfLayout({version:1,all:{preset:'nine'},pages:{}},true),false);
        assert.deepEqual(h.renderer.pdfRegionLocation,before);
        assert.equal(h.renderer.retryNavigation(),undefined);
        h.source.render=render;await h.renderer.next();
        assert.equal(h.renderer.pdfRegionLocation.total,4);
    } finally {h.close()}
});
test('text anchors choose containing panel or full original page outside the crop', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout(config,true);
        const anchor=()=>({startContainer:{nodeType:1},getClientRects:()=>[{left:400,top:100,width:20,height:12}]});
        await h.renderer.goTo({index:0,textAnchor:true,anchor});
        assert.equal(h.renderer.pdfRegionLocation.panel,1);
        await h.renderer.setPdfLayout({version:1,all:{crop:{x:0,y:.5,width:1,height:.5}},pages:{}},true);
        await h.renderer.goTo({index:0,textAnchor:true,anchor});
        assert.equal(h.renderer.pdfRegionLocation.signature,'original-target');
        await h.renderer.next();assert.equal(h.renderer.index,1);
    } finally {h.close()}
});
test.after(()=>{frames.forEach(frame=>frame.window.close());dom.window.close()});

test('continuous mode switches atomically and falls back to the same original page', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout({version:1,all:{preset:'single'},pages:{}},true);
        await h.renderer.goTo({index:1});
        assert.equal(await h.renderer.setPdfView({mode:'scroll',fit:'width'}),true);
        assert.equal(h.renderer.pdfView.mode,'scroll');assert.equal(h.renderer.index,1);
        assert.equal(h.renderer.getContents()[0].doc.querySelector('.textLayer').textContent,'Original text');
        assert.equal(await h.renderer.setPdfView({mode:'single',fit:'width'}),true);
        assert.equal(h.renderer.index,1);assert.equal(h.renderer.pdfView.mode,'single');
        assert.equal(h.renderer.getContents().length,1);
    } finally {h.close()}
});
test('failed continuous-mode entry preserves current document and previous settings', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout(config,true);await h.renderer.goTo({index:1});
        const doc=h.renderer.getContents()[0].doc;
        h.renderer.book.sections[1].load=async()=>{throw Error('injected')};
        assert.equal(await h.renderer.setPdfView({mode:'scroll'}),false);
        assert.equal(h.renderer.pdfView.mode,'single');assert.equal(h.renderer.getContents()[0].doc,doc);
        assert.equal(h.renderer.index,1);
    } finally {h.close()}
});

test('zoom refresh uses only visible source ROI, preserves original text and records center', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout(config,true);await h.renderer.goTo({index:0});
        const doc=h.renderer.getContents()[0].doc, text=doc.querySelector('.textLayer');
        let request;
        h.source.render=async value=>{request=value;return {blob:new Blob(['detail'])}};
        const ready=new Promise(resolve=>h.renderer.addEventListener('pdf-detail',resolve,{once:true}));
        assert.equal(h.renderer.setPdfView({zoom:15,rotation:90,fit:'width'}),true);
        h.renderer.panPdfView(100,100);
        await ready;
        assert.ok(request.region.width<.1 && request.region.height<.1);
        assert.equal(doc.querySelector('.textLayer'),text);
        assert.equal(doc.querySelectorAll('img').length,2);
        assert.equal(h.events.at(-1).reason,'viewport');
        assert.equal(h.events.at(-1).readingAction,true);
        assert.ok(h.renderer.pdfRegionLocation.center);
        const center=h.renderer.pdfRegionLocation.center;
        const saved={...h.renderer.pdfRegionLocation};
        await h.renderer.setPdfLayout(config,true,saved);
        assert.deepEqual(h.renderer.pdfRegionLocation.center,center);
        // Reopen path restores the saved source coordinates, not pixel offsets.
        await h.renderer.goTo({index:0});
        assert.deepEqual(h.renderer.pdfRegionLocation.center,center);
    } finally {h.close()}
});
test('pending detail cannot append to an obsolete frame after page navigation', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout(config,true);await h.renderer.goTo({index:0});
        let started,release;const entered=new Promise(r=>started=r);
        const render=h.source.render;
        h.source.render=()=>{started();return new Promise(r=>release=()=>r({blob:new Blob(['late'])}))};
        h.renderer.setPdfView({zoom:3});await entered;
        h.source.render=render;await h.renderer.goTo({index:2});release();
        await new Promise(r=>setTimeout(r,0));
        assert.equal(h.renderer.index,2);
        assert.equal(h.renderer.getContents()[0].doc.querySelectorAll('img').length,1);
    } finally {h.close()}
});
test('all enhancements reach formal single-page and scroll renders, next page and reset', async () => {
    const h=harness(),requests=[];
    const waitForRender=async()=>{
        for(let i=0;i<50 && !requests.length;i++) await new Promise(r=>setTimeout(r,10));
    };
    const render=h.source.render;
    h.source.render=async request=>{requests.push(request);return render(request)};
    try {
        await h.renderer.setPdfLayout({version:1,all:{preset:'single'},pages:{}},true);
        await h.renderer.goTo({index:0});
        for(const mode of ['single','scroll']){
            await h.renderer.setPdfView({mode});
            for(const key of ['ink','contrast','darken','whiten','sharpen','watermark']){
                requests.length=0;
                assert.equal(await h.renderer.setPdfView({mode,enhancement:{[key]:10}}),true);
                await waitForRender();
                assert.ok(requests.length>0,mode+' '+key+' repaints');
                assert.ok(requests.every(r=>r.enhancement[key]===10));
            }
            requests.length=0;
            await h.renderer.goTo({index:2});
            await waitForRender();
            assert.ok(requests.length>0);
            assert.ok(requests.every(r=>r.enhancement.watermark===10));
            requests.length=0;
            assert.equal(await h.renderer.setPdfView({mode,enhancement:{}}),true);
            await waitForRender();
            assert.ok(requests.length>0);
            assert.ok(requests.every(r=>Object.values(r.enhancement).every(v=>v===0)));
        }
    } finally {h.close()}
});
test('two-finger gesture stays captured until both fingers lift; single finger stays available', async () => {
    const h=harness();
    try {
        await h.renderer.setPdfLayout(config,true);await h.renderer.goTo({index:0});
        const doc=h.renderer.getContents()[0].doc;const seen=[];
        for(const type of ['touchstart','touchmove','touchend','click']) doc.addEventListener(type,()=>seen.push(type));
        const touch=(type,points)=>{
            const event=new doc.defaultView.Event(type,{bubbles:true,cancelable:true});
            Object.defineProperty(event,'touches',{value:points.map(([x,y])=>({screenX:x,screenY:y}))});
            doc.dispatchEvent(event);return event.defaultPrevented;
        };
        assert.equal(touch('touchstart',[[100,100]]),false);
        assert.equal(touch('touchstart',[[100,100],[200,200]]),true);
        assert.equal(touch('touchmove',[[100,80],[200,180]]),true);
        assert.equal(touch('touchend',[[100,80]]),true);
        assert.equal(touch('touchmove',[[100,60]]),true);
        assert.equal(touch('touchend',[]),true);
        doc.dispatchEvent(new doc.defaultView.MouseEvent('click',{bubbles:true,cancelable:true}));
        assert.deepEqual(seen,['touchstart']);
        assert.equal(touch('touchstart',[[10,10]]),false);
        assert.equal(touch('touchend',[]),false);
        assert.equal(h.renderer.index,0);
    } finally {h.close()}
});
