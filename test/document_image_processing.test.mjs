import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const uri=code=>`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const source=name=>readFile(new URL(`../assets/foliate-js/src/${name}.js`,import.meta.url),'utf8');
const processing=uri(await source('document-image-processing'));
const {normalizeEnhancement,enhanceImage,detectContentCrop}=await import(processing);
const renderer=uri((await source('pdf-region-renderer'))
 .replace("'./document-image-processing.js'",JSON.stringify(processing))
 .replace("'./document-regions.js'",JSON.stringify(uri(await source('document-regions')))));
const {createPdfRegionRenderer}=await import(renderer);
const {imageSectionEvidence}=await import(uri((await source('epub-image-source'))
 .replace("'./document-image-processing.js'",JSON.stringify(processing))
 .replace("'./pdf-region-renderer.js'",JSON.stringify(renderer))));
function raster(width=100,height=120,color=255){const data=new Uint8ClampedArray(width*height*4);for(let p=0;p<data.length;p+=4){data.fill(color,p,p+3);data[p+3]=255}return {data,width,height}}
function rect(image,x,y,w,h,color){for(let yy=y;yy<y+h;yy++)for(let xx=x;xx<x+w;xx++)image.data.fill(color,(yy*image.width+xx)*4,(yy*image.width+xx)*4+3)}
test('auto crop preserves thin lines, padding, footnotes and ignores isolated dust',async()=>{
 const img=raster();rect(img,20,20,60,65,30);rect(img,15,98,70,1,100);rect(img,1,1,1,1,0);
 const r=await detectContentCrop(img,{margin:0});assert.equal(r.detected,true);
 assert.ok(r.crop.x<=.15&&r.crop.y<=20/120);assert.ok(r.crop.y+r.crop.height>=99/120);
 assert.ok(r.crop.x>.01);const padded=await detectContentCrop(img,{margin:.1});assert.ok(padded.crop.width>r.crop.width);
});
test('blank, faint and full-bleed pages are handled conservatively',async()=>{
 assert.equal((await detectContentCrop(raster())).detected,false);
 const dark=raster(100,120,20);assert.equal((await detectContentCrop(dark)).reason,'uncertain-border');
 const page=raster();rect(page,0,20,100,90,60);const r=await detectContentCrop(page);assert.equal(r.detected,false);assert.equal(r.crop.width,1);
 const alpha=raster(100,120,0);for(let i=3;i<alpha.data.length;i+=4)alpha.data[i]=0;
 assert.equal((await detectContentCrop(alpha)).detected,false);
});
test('defaults are byte-identical and enhancement controls use distinct algorithms',async()=>{
 const img=raster(20,20,215);rect(img,9,4,1,12,55);const original=img.data.slice();
 await enhanceImage(img,{});assert.deepEqual(img.data,original);
 const results=[];
 for(const [key,value] of Object.entries({ink:15,contrast:30,darken:50,whiten:200,sharpen:70})){
  const copy={...img,data:original.slice()};await enhanceImage(copy,{[key]:value});
  assert.notDeepEqual(copy.data,original,key);results.push(Buffer.from(copy.data).toString('base64'));
  for(let p=3;p<copy.data.length;p+=4)assert.equal(copy.data[p],255);
 }
 assert.equal(new Set(results).size,5);
});
test('paper whitening preserves saturated colours',async()=>{
 const img=raster(4,4,230);img.data.set([180,210,250,128],0);await enhanceImage(img,{whiten:200});
 assert.deepEqual([...img.data.slice(0,4)],[180,210,250,128]);assert.ok(img.data[4]>230);
});
test('invalid settings, oversized images and cancellation are rejected',async()=>{
 for(const value of [{ink:16},{contrast:-101},{darken:Infinity},{whiten:-1},{sharpen:NaN}])assert.throws(()=>normalizeEnhancement(value));
 await assert.rejects(enhanceImage({width:5000,height:5000,data:[]},{}));
 await assert.rejects(detectContentCrop(raster(),{margin:.3}));
 const controller=new AbortController();controller.abort();await assert.rejects(enhanceImage(raster(),{ink:1},{signal:controller.signal}),{name:'AbortError'});
 const next=new AbortController();const job=detectContentCrop(raster(900,900),{signal:next.signal});next.abort();await assert.rejects(job,{name:'AbortError'});
});
test('EPUB evidence distinguishes full images, SVG fragments, decorations, cover and mixed text',()=>{
 const image={x:0,y:0,width:1000,height:1200,naturalWidth:1000,naturalHeight:1200};
 const base={page:7,href:'z.xhtml',width:1000,height:1200,characters:0,images:[image]};
 assert.equal(imageSectionEvidence(base).kind,'scanned');assert.equal(imageSectionEvidence(base).page,7);
 assert.equal(imageSectionEvidence({...base,excluded:true}).kind,'illustrated');
 assert.equal(imageSectionEvidence({...base,characters:81}).kind,'text');
 assert.equal(imageSectionEvidence({...base,characters:2}).imageOnly,false);
 assert.equal(imageSectionEvidence({...base,images:[{...image,width:40,height:40,naturalWidth:40,naturalHeight:40}]}).kind,'image-candidate');
 const fragments=[{...image,height:600},{...image,y:600,height:600}];assert.equal(imageSectionEvidence({...base,images:fragments}).imageCoverage,1);
 assert.equal(imageSectionEvidence({...base,images:[image,image]}).imageCoverage,1);
});
test('PDF raster cache keys include enhancement and crop margin; clear frees pixel storage',async()=>{
 let rendered=0;const canvases=[];
 const page={getViewport:({scale,rotation=0})=>({width:100*scale,height:120*scale,rotation,scale}),render:()=>({promise:Promise.resolve(),cancel(){}})};
 const source=createPdfRegionRenderer({numPages:1,getPage:async()=>page},{createCanvas:()=>{
  const canvas={width:0,height:0,getContext:()=>({getImageData:()=>{const img=raster(canvas.width,canvas.height);rect(img,20,20,30,40,0);return img},putImageData(){}})};canvases.push(canvas);return canvas;
 },encode:async()=>new Blob([String(++rendered)])});
 const request={page:0,width:100,height:120};await source.render(request);await source.render(request);assert.equal(rendered,1);
 await source.render({...request,enhancement:{darken:50}});assert.equal(rendered,2);
 const result=await source.render({...request,analyzeCrop:true,margin:0});assert.ok(result.cropDetection.crop.width<1);
 await source.render({...request,analyzeCrop:true,margin:.1});assert.equal(rendered,4);
 assert.ok(canvases.every(c=>c.width===0&&c.height===0));source.clear();
});
test('watermark filtering changes only named OCGs and never original visibility',async()=>{
 const configs=[],renders=[];
 const page={getViewport:({scale,rotation=0})=>({width:100*scale,height:120*scale,rotation,scale}),
   render:args=>{renders.push(args);return {promise:Promise.resolve(),cancel(){}}}};
 const source=createPdfRegionRenderer({numPages:1,getPage:async()=>page,getOptionalContentConfig:async()=>{
   const groups={a:{name:'Watermark',visible:true},b:{name:'Body diagrams',visible:true}};
   const config={getGroups:()=>groups,setVisibility:(id,v)=>groups[id].visible=v};configs.push(config);return config;
 }},{createCanvas:()=>({getContext:()=>({}),width:0,height:0}),encode:async()=>new Blob(['raster'])});
 assert.deepEqual((await source.info(0)).watermarks,[{id:'a',name:'Watermark'}]);
 await source.render({page:0,hideWatermarks:true});
 const filtered=await renders[0].optionalContentConfigPromise;
 assert.equal(filtered.getGroups().a.visible,false);assert.equal(filtered.getGroups().b.visible,true);
 assert.equal(configs[0].getGroups().a.visible,true);
 await source.render({page:0});assert.equal(renders.length,2);assert.equal(renders[1].optionalContentConfigPromise,undefined);
});
