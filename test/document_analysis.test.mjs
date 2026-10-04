import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
const require = createRequire(import.meta.url);
const moduleFor = async file => import(`data:text/javascript;base64,${Buffer.from(await readFile(
    new URL(`../assets/foliate-js/src/${file}.js`,import.meta.url),'utf8')).toString('base64')}`);
const {analyzePdfPage, createPdfAnalysis, samplePageIndices, analyzeEpubSection, summarizePages} = await moduleFor('document-analysis');
const {PageResourceCache, boundedRenderScale} = await moduleFor('page-resource-cache');
const pdfjs = require('../assets/foliate-js/src/vendor/pdfjs/pdf.js');
pdfjs.GlobalWorkerOptions.workerSrc = fileURLToPath(new URL('../assets/foliate-js/src/vendor/pdfjs/pdf.worker.js',import.meta.url));

// Small, original synthetic PDFs are made in memory. No external book or API.
function pdfBytes(kinds) {
    const objects = ['<< /Type /Catalog /Pages 2 0 R >>', '',
        '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
    const refs = [];
    for (const kind of kinds) {
        const pageId = objects.length+1, streamId = pageId+1;
        refs.push(`${pageId} 0 R`);
        objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Resources << /Font << /F1 3 0 R >> >> /Contents ${streamId} 0 R >>`);
        let data = '';
        if (kind.includes('image')) data += 'q 200 0 0 300 0 0 cm BI /W 1 /H 1 /CS /RGB /BPC 8 ID abc EI Q\n';
        if (kind.includes('text')) data += 'BT /F1 10 Tf 10 260 Td (A readable original sample for document type tests.) Tj ET\n';
        objects.push(`<< /Length ${Buffer.byteLength(data)} >>\nstream\n${data}endstream`);
    }
    objects[1] = `<< /Type /Pages /Kids [${refs.join(' ')}] /Count ${kinds.length} >>`;
    let result = '%PDF-1.4\n'; const offsets = [0];
    for (let i=0;i<objects.length;i++) { offsets.push(Buffer.byteLength(result)); result += `${i+1} 0 obj\n${objects[i]}\nendobj\n`; }
    const xref = Buffer.byteLength(result);
    result += `xref\n0 ${objects.length+1}\n0000000000 65535 f \n`;
    for (const offset of offsets.slice(1)) result += `${String(offset).padStart(10,'0')} 00000 n \n`;
    result += `trailer\n<< /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
    return new Uint8Array(Buffer.from(result));
}

test('bundled PDF.js backend identifies text, scan, image/text, blank and mixed pages', async () => {
    const pdf = await pdfjs.getDocument({data:pdfBytes(['text','image','image-text','blank']), disableFontFace:true,verbosity:0}).promise;
    try {
        const analysis = createPdfAnalysis(pdf,pdfjs.OPS);
        const summary = await analysis.sample();
        assert.deepEqual(summary.pages.map(p=>p.kind),['text','scanned','image-with-text','blank']);
        assert.equal(summary.kind,'mixed'); assert.equal(summary.complete,true);
        const text = await analysis.page(0);
        assert.match(text.text,/readable original sample/);
        assert.ok(text.blocks.every(b=>b.box.left>=0 && b.box.right<=1 && b.box.top>=0 && b.box.bottom<=1));
        assert.equal(text.blocks[0].confidence,null);
        assert.equal(summary.pages[1].imageCoverage,1);
        assert.equal('text' in summary.pages[0],false);
        await assert.rejects(analysis.page(-1),/out of bounds/);
        await assert.rejects(analysis.page(4),/out of bounds/);
    } finally { await pdf.destroy(); }
});

test('sampling is spread over the document and is bounded, not just the cover', () => {
    assert.deepEqual(samplePageIndices(100),[0,25,50,74,99]);
    assert.equal(samplePageIndices(1000,100).length,9);
    assert.deepEqual(samplePageIndices(0),[]);
    assert.deepEqual(samplePageIndices(1),[0]);
    assert.equal(summarizePages([{kind:'blank'},{kind:'text'},{kind:'illustrated'}],20).kind,'text');
});

function mockPage(fnArray, argsArray, items=[]) {
    return {pageNumber:1, getViewport:()=>({width:200,height:300,rotation:0,transform:[1,0,0,-1,0,300]}),
        getTextContent:async()=>({items}),getOperatorList:async()=>({fnArray,argsArray})};
}
test('overlapping small illustrations do not add up to a scanned page', async () => {
    const O=pdfjs.OPS;
    const page=mockPage([O.transform,O.paintImageXObject,O.paintImageXObject],[[100,0,0,150,0,0],[],[]]);
    const result=await analyzePdfPage(page,O);
    assert.equal(result.imageCoverage,.25); assert.equal(result.kind,'unknown');
});
test('tiled images, graphics stack, clipped/rotated images remain conservative', async () => {
    const O=pdfjs.OPS;
    const result=await analyzePdfPage(mockPage(
        [O.save,O.transform,O.paintImageXObject,O.restore,O.transform,O.paintImageXObject],
        [[],[100,0,0,300,0,0],[],[],[100,0,0,300,100,0],[]]),O);
    assert.equal(result.imageCoverage,1); assert.equal(result.kind,'scanned');
    const clipped=await analyzePdfPage(mockPage([O.transform,O.clip,O.paintImageXObject],[[200,0,0,300,0,0],[],[]]),O);
    assert.equal(clipped.kind,'unknown'); assert.equal(clipped.coverageUncertain,true);
});
test('invalid or off-page text is not accepted as a usable OCR text layer', async () => {
    const result=await analyzePdfPage(mockPage([],[],[{str:'This is a bogus off page text layer',width:100,height:10,transform:[10,0,0,10,900,900]}]),pdfjs.OPS);
    assert.equal(result.reliableText,false); assert.equal(result.validCharacters,0);
    assert.equal(result.kind,'unknown');
});
test('cancellation does not continue sampling after the current page', async () => {
    const controller = new AbortController(); let loads=0;
    const analysis=createPdfAnalysis({numPages:99,getPage:async()=>{
        loads++;return mockPage([],[]);
    }},pdfjs.OPS);
    await assert.rejects(analysis.sample({signal:controller.signal,onProgress:()=>controller.abort()}),{name:'AbortError'});
    assert.equal(loads,1);
});
test('page evidence cache is bounded and revisiting an evicted page analyzes again', async () => {
    let loads=0;
    const analysis=createPdfAnalysis({numPages:40,getPage:async()=>{loads++;return mockPage([],[]);}},pdfjs.OPS);
    for(let i=0;i<40;i++) await analysis.page(i);
    await analysis.page(39); assert.equal(loads,40);
    await analysis.page(0); assert.equal(loads,41);
});
test('closing a PDF rejects pending evidence instead of repopulating released cache', async () => {
    let resolve;
    const waiting=new Promise(done=>{resolve=done});
    const analysis=createPdfAnalysis({numPages:1,getPage:()=>waiting},pdfjs.OPS);
    const result=analysis.page(0); analysis.clear(); resolve(mockPage([],[]));
    await assert.rejects(result,{name:'AbortError'});
});
test('resource cache revokes both URLs but retains the current two-page spread', () => {
    const released=[];
    const cache=new PageResourceCache({maxEntries:3,maxBytes:12,release:r=>released.push(...r.urls)});
    for(let i=0;i<8;i++) cache.set(i,{bytes:10,urls:[`html-${i}`,`image-${i}`]});
    assert.deepEqual([...cache.entries.keys()],[6,7]);
    assert.equal(released.length,12); assert.equal(cache.bytes,20);
    cache.clear(); assert.equal(released.length,16); assert.equal(cache.bytes,0);
});
test('large/panoramic pages obey canvas pixel and dimension ceilings', () => {
    for(const [w,h] of [[600,800],[50000,300],[4000,60000]]) {
        const scale=boundedRenderScale(w,h,15);
        assert.ok(w*h*scale*scale<=4*1024*1024+.001);
        assert.ok(Math.max(w,h)*scale<=4096+.001);
    }
    assert.throws(()=>boundedRenderScale(0,300,1),RangeError);
});
test('EPUB uses actual text and ordered img/SVG references; cover alone does not mean scan', () => {
    const {JSDOM}=createRequire(`${process.env.MODU_JSDOM_ROOT ?? '/private/tmp/modu-119-js-tests'}/package.json`)('jsdom');
    const doc=html=>new JSDOM(html).window.document;
    const chapter=analyzeEpubSection(doc('<p>'+('Original text. '.repeat(20))+'</p><img src="cover.jpg">'),{index:3,href:'chapter.xhtml'});
    assert.equal(chapter.kind,'text'); assert.equal(chapter.href,'chapter.xhtml');
    const images=analyzeEpubSection(doc('<svg><image href="z.png"/><image href="a.png"/></svg>'),{index:1});
    assert.equal(images.kind,'image-candidate'); assert.deepEqual(images.images.map(i=>i.resource),['z.png','a.png']);
    assert.equal(analyzeEpubSection(doc('<img src="cover.jpg">'),{excluded:true}).kind,'illustrated');
});
test('MOBI6 record images are candidates, never positive scan evidence without decoded geometry', () => {
    const {JSDOM}=createRequire(`${process.env.MODU_JSDOM_ROOT ?? '/private/tmp/modu-119-js-tests'}/package.json`)('jsdom');
    const dom=new JSDOM('<img recindex="00192" width="900" height="1358"><img recindex=" 00034 "><img src="blob:decoded" recindex="59"><img recindex="0"><img recindex="-1"><img recindex="abc"><img recindex="1e2"><img recindex="9007199254740993"><img><div hidden><img recindex="20"></div>');
    try {
        const result=analyzeEpubSection(dom.window.document);
        assert.equal(result.kind,'image-candidate');
        assert.equal(result.coverageUncertain,true);
        assert.deepEqual(result.images.map(i=>i.resource),['mobi:recindex:192','mobi:recindex:34','blob:decoded']);
        assert.deepEqual(result.images.map(i=>i.order),[0,1,2]);
    } finally {dom.window.close()}
});
