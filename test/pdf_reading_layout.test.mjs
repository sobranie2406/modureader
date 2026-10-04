import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source = name => readFile(new URL(`../assets/foliate-js/src/${name}.js`, import.meta.url), 'utf8');
const uri = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const G = await import(uri((await source('pdf-reading-layout'))
    .replace("'./document-regions.js'", JSON.stringify(uri(await source('document-regions'))))));
const config = {version: 1, all: {preset: 'four', order: 'row-rtl'}, even: {preset: 'vertical2'}, pages: {2: {preset: 'single'}}};
const auto = {version:1,all:{autoCrop:true,autoMargin:.03,preset:'horizontal2',
    crop:{x:.3,y:.3,width:.3,height:.3}},pages:{}};
test('reflow uses the cropped whole page, not a grid panel, and respects disabled crop',async()=>{
 const crop={x:.1,y:.2,width:.8,height:.6};
 for(const preset of ['single','four','nine']) {
   const region=await G.resolveReflowRegion({version:1,all:{crop,preset},pages:{}},0,{});
   for(const key of Object.keys(crop)) assert.ok(Math.abs(region[key]-crop[key])<1e-9);
 }
 let calls=0;
 const book={cropRegionRenderer:{render:async ({page})=>{calls++;return {cropDetection:{detected:true,
   crop:{x:page*.1,y:.1,width:.8,height:.8}}}}}};
 const first=await G.resolveReflowRegion(auto,0,book),next=await G.resolveReflowRegion(auto,1,book);
 assert.equal(first.width,.8);assert.equal(next.x,.1);assert.equal(calls,2);
 await G.resolveReflowRegion(auto,0,book);assert.equal(calls,2);
 assert.deepEqual(await G.resolveReflowRegion(auto,1,book,{enabled:false}),{x:0,y:0,width:1,height:1});
 assert.equal(calls,2);
});
test('automatic layouts detect per original page, then split, with isolated bounded caches',async()=>{
 const requests=[];
 const book={cropRegionRenderer:{render:async request=>{requests.push(request);return {cropDetection:{detected:true,
    crop:request.page===0?{x:.1,y:.2,width:.8,height:.6}:{x:.2,y:.1,width:.6,height:.8}}}}}};
 const a=await G.resolveReadingRegions(auto,0,book),b=await G.resolveReadingRegions(auto,1,book);
 assert.equal(a[0].x,.1);assert.equal(a[0].width,.4);assert.equal(b[0].x,.2);assert.equal(b[0].width,.3);
 await G.resolveReadingRegions(auto,0,book);assert.equal(requests.length,2);
 assert.ok(requests.every(r=>r.analyzeCrop && r.rotation===0 && r.region.width===1 && r.margin===.03));
 await G.resolveReadingRegions({...auto,all:{...auto.all,autoMargin:.1}},0,book);
 await G.resolveReadingRegions(auto,0,book,{hideWatermarks:true});assert.equal(requests.length,4);
 await G.resolveReadingRegions(auto,0,{cropRegionRenderer:book.cropRegionRenderer});assert.equal(requests.length,5);
 for(let page=2;page<68;page++)await G.resolveReadingRegions(auto,page,book);
 const count=requests.length;await G.resolveReadingRegions(auto,0,book);assert.equal(requests.length,count+1);
});
test('auto crop failure/blank uses full page, manual overrides and text sections skip detection',async()=>{
 let calls=0;
 const book={nativeTextPages:new Set([2]),cropRegionRenderer:{render:async()=>{calls++;throw Error('unavailable')}}};
 const fallback=await G.resolveReadingRegions(auto,0,book);assert.equal(fallback[0].x,0);assert.equal(fallback[0].width,.5);
 await G.resolveReadingRegions(auto,0,book);assert.equal(calls,2,'failed detection is retryable');
 book.cropRegionRenderer.render=async()=>{calls++;return {cropDetection:{detected:false}}};
 assert.deepEqual(await G.resolveReadingRegions(auto,1,book),fallback);
 const text=await G.resolveReadingRegions(auto,2,book);assert.equal(text.length,1);assert.equal(text[0].width,1);
 const manual=await G.resolveReadingRegions({...auto,pages:{0:{crop:{x:.2,y:.1,width:.4,height:.6}}}},0,book);
 assert.equal(manual[0].width,.4);assert.equal(calls,3);
});
test('late automatic detection is discarded; parallel pages do not cancel each other',async()=>{
 let busy=false,active=true,release,entered;
 const started=new Promise(r=>entered=r);
 const book={cropRegionRenderer:{render:async request=>{
    assert.equal(busy,false);busy=true;
    if(request.page===0){entered();await new Promise(r=>release=r)}
    busy=false;return {cropDetection:{detected:true,crop:{x:.1,y:.1,width:.8,height:.8}}};
 }}};
 const old=G.resolveReadingRegions(auto,0,book,{active:()=>active});
 await started;const next=G.resolveReadingRegions(auto,1,book);active=false;release();
 await assert.rejects(old,{name:'AbortError'});assert.equal((await next)[0].x,.1);
});
test('automatic signatures ignore editor preview but track margin and grid settings',()=>{
 const saved={page:0,panel:1,signature:G.layoutSignature(auto,0)};
 assert.equal(G.restoredPanel({...auto,all:{...auto.all,crop:{x:0,y:0,width:1,height:1}}},0,saved),1);
 assert.equal(G.restoredPanel({...auto,all:{...auto.all,autoMargin:.1}},0,saved),0);
 for(const fields of [{autoCrop:'yes'},{autoMargin:-1},{autoMargin:NaN},{autoMargin:.21}])
    assert.throws(()=>G.validateReadingLayout({...auto,all:{...auto.all,...fields}}));
});

test('next/previous traverse panels before original pages, including parity overrides', () => {
    let current = {page: -1, panel: 0};
    const visited = [];
    while ((current = G.adjacentPanel(config, 3, current.page, current.panel, 1))) visited.push(current);
    assert.deepEqual(visited, [
        {page: 0, panel: 0}, {page: 0, panel: 1}, {page: 0, panel: 2}, {page: 0, panel: 3},
        {page: 1, panel: 0}, {page: 1, panel: 1}, {page: 2, panel: 0}]);
    current = visited.at(-1); const reverse = [current];
    while ((current = G.adjacentPanel(config, 3, current.page, current.panel, -1))) reverse.push(current);
    assert.deepEqual(reverse, visited.toReversed());
    assert.equal(G.adjacentPanel(config, 0, -1, 0, 1), null);
});
test('resume requires original page, valid panel and exactly matching layout', () => {
    const saved = {page: 0, panel: 3, signature: G.layoutSignature(config, 0)};
    assert.equal(G.restoredPanel(config, 0, saved), 3);
    assert.equal(G.restoredPanel(config, 1, saved), 0);
    for (const panel of [-1, 4, 1.2]) assert.equal(G.restoredPanel(config, 0, {...saved, panel}), 0);
    assert.equal(G.restoredPanel({...config, all: {preset: 'four', order: 'row-ltr'}}, 0, saved), 0);
    assert.equal(G.restoredPanel(config, 0, null), 0);
});
test('layout snapshot is validated and isolated from later mutation', () => {
    const copy = G.validateReadingLayout(config);
    copy.all.preset = 'nine'; assert.equal(config.all.preset, 'four');
    for (const bad of [{}, {...config, pages: {'-1': {}}}, {...config, odd: {preset: 'bad'}}])
        assert.throws(() => G.validateReadingLayout(bad));
});
