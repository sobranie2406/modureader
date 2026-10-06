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
const {createPdfRegionRenderer,createDocumentCanvas,encodeDocumentCanvas}=await import(renderer);
const {imageSectionEvidence,imagePageGeometry}=await import(uri((await source('epub-image-source'))
 .replace("'./document-image-processing.js'",JSON.stringify(processing))
 .replace("'./pdf-region-renderer.js'",JSON.stringify(renderer))));
function raster(width=100,height=120,color=255){const data=new Uint8ClampedArray(width*height*4);for(let p=0;p<data.length;p+=4){data.fill(color,p,p+3);data[p+3]=255}return {data,width,height}}
function rect(image,x,y,w,h,color){for(let yy=y;yy<y+h;yy++)for(let xx=x;xx<x+w;xx++)image.data.fill(color,(yy*image.width+xx)*4,(yy*image.width+xx)*4+3)}
function markedPage(color=[210,210,210]) {
 const image=raster(240,300,250);
 for(let y=50;y<160;y++)for(let dx=0;dx<4;dx++)image.data.set([...color,255],(y*240+y+dx)*4);
 rect(image,20,100,200,2,45); // dark text crossing the watermark
 rect(image,30,200,5,6,210); // faint small print
 rect(image,80,230,100,1,205); // thin rule
 rect(image,190,180,20,25,210); // solid illustration fill
 return image;
}
test('Android document encoding is bounded and lossless; other platforms stay async',async()=>{
 const saved=Object.getOwnPropertyDescriptor(globalThis,'navigator');
 const documentSaved=Object.getOwnPropertyDescriptor(globalThis,'document');
 try {
  const setAgent=userAgent=>Object.defineProperty(globalThis,'navigator',{configurable:true,value:{userAgent}});
  setAgent('Mozilla/5.0 (Linux; Android 15)');
  const bytes=new Uint8Array([137,80,78,71,0,255,128]);
  let sync=0,async=0;
  const canvas={width:900,height:900,toDataURL(type){assert.equal(type,'image/png');sync++;return 'data:image/png;base64,'+Buffer.from(bytes).toString('base64')},toBlob(callback,type){assert.equal(type,'image/png');async++;callback(new Blob([bytes],{type}))}};
  Object.defineProperty(globalThis,'document',{configurable:true,value:{createElement:tag=>{assert.equal(tag,'canvas');return canvas}}});
  assert.equal(createDocumentCanvas(),canvas);
  const blob=await encodeDocumentCanvas(canvas);
  assert.equal(blob.type,'image/png');assert.deepEqual(new Uint8Array(await blob.arrayBuffer()),bytes);
  assert.equal(sync,1);assert.equal(async,0);
  canvas.width=2048;canvas.height=2048;await encodeDocumentCanvas(canvas);
  canvas.width=2049;canvas.height=1;await encodeDocumentCanvas(canvas);
  assert.equal(sync,1);assert.equal(async,2);
  canvas.width=900;canvas.height=900;
  setAgent('Mozilla/5.0 Macintosh');await encodeDocumentCanvas(canvas);
  assert.equal(sync,1);assert.equal(async,3);
  let offscreenCalls=0;
  await encodeDocumentCanvas({convertToBlob:async options=>{assert.equal(options.type,'image/png');offscreenCalls++;return blob}});
  assert.equal(offscreenCalls,1);
  setAgent('Android');canvas.toDataURL=()=> 'data:,';
  await assert.rejects(encodeDocumentCanvas(canvas),/encoding failed/);
  delete canvas.toDataURL;canvas.toBlob=callback=>callback(null);
  await assert.rejects(encodeDocumentCanvas(canvas),/encoding failed/);
 } finally {
  if(saved)Object.defineProperty(globalThis,'navigator',saved);else delete globalThis.navigator;
  if(documentSaved)Object.defineProperty(globalThis,'document',documentSaved);else delete globalThis.document;
 }
});
test('text paper cleanup whitens uneven tinted paper while retaining dark strokes', async()=>{
 const image=raster(256,320);
 for(let y=0;y<image.height;y++)for(let x=0;x<image.width;x++) {
  const v=Math.round(210+25*x/image.width-10*y/image.height);
  image.data.set([v+8,v,v-10,255],(y*image.width+x)*4);
 }
 for(let y=40;y<280;y+=20)rect(image,30,y,180,2,45);
 const before=image.data.slice();
 await enhanceImage(image,{paperMode:'text',whiten:200});
 let total=0,count=0;
 for(let y=5;y<315;y+=10)for(let x=10;x<245;x+=10) {
  const p=(y*image.width+x)*4;
  total+=image.data[p];count++;
  assert.equal(image.data[p],image.data[p+2],'paper colour removed');
 }
 assert.ok(total/count>248);
 assert.deepEqual(image.data.slice((40*256+40)*4,(40*256+40)*4+3),new Uint8ClampedArray([45,45,45]));
 assert.notDeepEqual(image.data,before);
});
test('colour preservation and zero strength do not alter coloured art',async()=>{
 for(const mode of ['preserve','text']) {
  const image=raster(50,50);image.data.set([200,80,60,255],0);
  const before=image.data.slice();await enhanceImage(image,{paperMode:mode,whiten:0});
  assert.deepEqual(image.data,before);
 }
 const image=raster(50,50);image.data.set([200,80,60,255],0);
 await enhanceImage(image,{paperMode:'preserve',whiten:200});
 assert.deepEqual(Array.from(image.data.slice(0,4)),[200,80,60,255]);
 assert.throws(()=>normalizeEnhancement({paperMode:'unknown'}));
 const cancelled=raster(500,500,215),before=cancelled.data.slice(),controller=new AbortController();
 const pending=enhanceImage(cancelled,{paperMode:'text',whiten:200},{signal:controller.signal});controller.abort();
 await assert.rejects(pending,{name:'AbortError'});assert.deepEqual(cancelled.data,before);
});
test('scan cleanup removes pale gray and colored components but keeps dark ink and small print',async()=>{
 for(const color of [[210,210,210],[220,160,170],[155,195,230]]) {
  const image=markedPage(color),before=image.data.slice();
  await enhanceImage(image,{watermark:100});
  const at=(x,y)=>Array.from(image.data.slice((y*240+x)*4,(y*240+x)*4+3));
  assert.deepEqual(at(70,70),[250,250,250]);
  assert.deepEqual(at(101,100),[45,45,45],'overlapping dark stroke retained');
  assert.deepEqual(at(31,202),[210,210,210],'small pale print retained');
  assert.deepEqual(at(100,230),[205,205,205],'thin line retained');
  assert.deepEqual(at(200,190),[210,210,210],'solid illustration retained');
  for(let i=3;i<image.data.length;i+=4)assert.equal(image.data[i],before[i]);
 }
});
test('scan cleanup is off by default, gradual, distinct from whitening and precedes darkening',async()=>{
 const original=markedPage();
 const apply=async options=>{const image={...original,data:original.data.slice()};await enhanceImage(image,options);return image.data};
 assert.deepEqual(await apply({watermark:0}),original.data);
 const at=(70*240+70)*4,half=await apply({watermark:50}),full=await apply({watermark:100});
 assert.ok(half[at]>210 && half[at]<full[at]);
 assert.notDeepEqual(full,await apply({whiten:200}));
 const combined=await apply({watermark:100,darken:35,sharpen:25});
 const expected={...original,data:full.slice()};await enhanceImage(expected,{darken:35,sharpen:25});
 assert.deepEqual(combined,expected.data);
});
test('scan cleanup leaves dark, transparent and dense image pages unchanged',async()=>{
 for(const image of [raster(200,200,80),raster(200,200,255),raster(200,200,0)]) {
  if(image.data[0]===0)for(let i=3;i<image.data.length;i+=4)image.data[i]=0;
  const before=image.data.slice();await enhanceImage(image,{watermark:100});assert.deepEqual(image.data,before);
 }
 const image=raster(200,200,250);rect(image,0,0,170,180,205);
 const before=image.data.slice();await enhanceImage(image,{watermark:100});assert.deepEqual(image.data,before);
});
test('cancelled scan cleanup never commits partially processed pixels and validates strength',async()=>{
 const image=markedPage(),before=image.data.slice(),controller=new AbortController();
 const pending=enhanceImage(image,{watermark:100},{signal:controller.signal});controller.abort();
 await assert.rejects(pending,{name:'AbortError'});assert.deepEqual(image.data,before);
 for(const watermark of [-1,101,NaN,Infinity,'50'])assert.throws(()=>normalizeEnhancement({watermark}));
 assert.equal(normalizeEnhancement({ink:2}).watermark,0);
});
test('scanner outline and binding shadow do not prevent independent text bounds',async()=>{
 for(const border of ['binding','frame']) {
  const img=raster(600,800,240);
  for(let y=140;y<640;y+=24) rect(img,90,y,410,3,35);
  rect(img,285,725,20,8,60); // page number must survive
  if(border==='binding') rect(img,0,0,12,800,15);
  else {rect(img,0,0,600,2,15);rect(img,0,798,600,2,15);rect(img,0,0,2,800,15);rect(img,598,0,2,800,15)}
  const result=await detectContentCrop(img,{margin:.01});
  assert.equal(result.detected,true,border);
  assert.ok(result.crop.x>.1 && result.crop.x<.15,border);
  assert.ok(result.crop.y>.1 && result.crop.y<.175,border);
  assert.ok(result.crop.y+result.crop.height>733/800,'retain page number');
  assert.ok(result.crop.width<.8 && result.crop.height<.8);
 }
});
test('each raster yields its own bounds, blank outlined scans remain full-page',async()=>{
 const first=raster(300,400),second=raster(300,400),blank=raster(300,400);
 rect(first,30,40,180,200,40);rect(second,90,100,160,230,40);rect(blank,0,0,5,400,0);
 const a=await detectContentCrop(first,{margin:0}),b=await detectContentCrop(second,{margin:0});
 assert.notDeepEqual(a.crop,b.crop);assert.ok(a.crop.x<b.crop.x && a.crop.y<b.crop.y);
 assert.equal((await detectContentCrop(blank)).detected,false);
});
function unevenTextScan({paper=238, vertical=false}={}) {
 const img=raster(600,800,paper);
 // Smooth binding shadow and yellow/grey paper variation, not printed content.
 for(let y=0;y<800;y++)for(let x=0;x<600;x++) {
  const shade=Math.round(paper-65*Math.exp(-x/55)-16*y/800);
  img.data.set([shade,shade-7,shade-14,255],(y*600+x)*4);
 }
 for(let y=150;y<630;y+=24)for(let x=100;x<500;x+=16) {
  rect(img,x,y,2,11,65);rect(img,x,y+5,9,2,65);rect(img,x+7,y,2,11,65);
 }
 if(vertical) { // a narrow vertical side note must not be discarded
  for(let y=200;y<320;y+=16)rect(img,75,y,5,9,90);
 }
 rect(img,280,720,5,9,90);rect(img,290,720,5,9,90);
 return img;
}
test('text boundaries ignore paper gradients and inset scanner frames, retaining page numbers',async()=>{
 for(const paper of [238,185]) {
  const img=unevenTextScan({paper,vertical:true});
  rect(img,8,9,584,2,25);rect(img,8,789,584,2,25);
  rect(img,8,9,2,782,25);rect(img,590,9,2,782,25);
  const before=img.data.slice(),r=await detectContentCrop(img,{margin:.01});
  assert.equal(r.detected,true,`paper ${paper}`);
  assert.ok(r.crop.x>.08 && r.crop.x<=75/600,JSON.stringify(r));
  assert.ok(r.crop.y>.14 && r.crop.y<=150/800,JSON.stringify(r));
  assert.ok(r.crop.width<.8 && r.crop.height<.8,JSON.stringify(r));
  assert.ok(r.crop.x+r.crop.width>=493/600);
  assert.ok(r.crop.y+r.crop.height>=729/800,'page number retained');
  assert.deepEqual(img.data,before,'detection never edits pixels');
 }
});
test('blank shaded paper does not invent a content box',async()=>{
 const img=unevenTextScan();
 for(let y=0;y<800;y++)for(let x=0;x<600;x++) {
  const shade=Math.round(238-65*Math.exp(-x/55)-16*y/800);
  img.data.set([shade,shade-7,shade-14,255],(y*600+x)*4);
 }
 assert.equal((await detectContentCrop(img)).detected,false);
});
test('broken scanner edge lines and small margin clusters do not stretch text bounds',async()=>{
 const img=unevenTextScan();
 for(let y=0;y<650;y+=120)rect(img,4,y,1,90,40);
 for(const [x,y] of [[30,45],[560,30],[550,760],[20,650]])rect(img,x,y,2,2,20);
 // A small punctuation mark just outside a main line is retained, not dust.
 rect(img,496,151,2,2,40);
 const r=await detectContentCrop(img,{margin:0});
 assert.equal(r.detected,true);
 assert.ok(r.crop.x>.15 && r.crop.y>.17,JSON.stringify(r));
 assert.ok(r.crop.x+r.crop.width>=498/600,'trailing punctuation');
 assert.ok(r.crop.y+r.crop.height>=729/800,'page number');
 assert.ok(r.crop.y+r.crop.height<.94,'margin dust');
});
test('crop detection can stop during local threshold work without changing original pixels',async()=>{
 const image=unevenTextScan(),before=image.data.slice(),controller=new AbortController();
 const pending=detectContentCrop(image,{signal:controller.signal});
 setTimeout(()=>controller.abort(),1);
 await assert.rejects(pending,{name:'AbortError'});
 assert.deepEqual(image.data,before);
});
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
test('each control changes its intended tones or edges, not just arbitrary bytes',async()=>{
 const pixel=(image,x,y)=>image.data[(y*image.width+x)*4];
 const original=raster(20,20,220);rect(original,10,3,1,14,60);
 const apply=async values=>{const copy={...original,data:original.data.slice()};await enhanceImage(copy,values);return copy};
 const ink=await apply({ink:15});
 assert.ok(pixel(ink,9,8)<220,'stroke expands one pixel');
 assert.equal(pixel(ink,0,8),220,'distant paper stays unchanged');
 assert.equal(pixel(ink,10,8),60,'solid stroke core stays unchanged');
 const contrast=await apply({contrast:25}),lowContrast=await apply({contrast:-25});
 assert.ok(pixel(contrast,0,8)>220 && pixel(contrast,10,8)<60);
 assert.ok(pixel(lowContrast,0,8)<220 && pixel(lowContrast,10,8)>60);
 const dark=await apply({darken:50});
 assert.ok(pixel(dark,0,8)<220 && pixel(dark,10,8)<60);
 const white=await apply({whiten:200});
 assert.ok(pixel(white,0,8)>220);assert.equal(pixel(white,10,8),60);
 const sharp=await apply({sharpen:100});
 assert.ok(pixel(sharp,9,8)>220 && pixel(sharp,10,8)<60);
 assert.equal(pixel(sharp,0,8),220,'uniform paper is not sharpened');
 for(const [key,max] of Object.entries({ink:15,contrast:100,darken:100,whiten:200,sharpen:100})){
  const half=await apply({[key]:max/2}),full=await apply({[key]:max});
  const delta=image=>image.data.reduce((sum,v,i)=>sum+Math.abs(v-original.data[i]),0);
  assert.ok(delta(full)>=delta(half),key+' strength increases');
 }
});
test('PDF renderer applies each enhancement and reset without modifying source pixels',async()=>{
 const original=raster(20,20,220);rect(original,10,3,1,14,60);
 const before=original.data.slice();
 const page={getViewport:({scale,rotation=0})=>({width:20*scale,height:20*scale,scale,rotation}),
  render:({canvasContext})=>{canvasContext.putImageData({...original,data:original.data.slice()});return {promise:Promise.resolve(),cancel(){}}}};
 const source=createPdfRegionRenderer({numPages:1,getPage:async()=>page},{createCanvas:()=>{
  const canvas={width:0,height:0,pixels:null};
  canvas.getContext=()=>({getImageData:()=>({...canvas.pixels,data:canvas.pixels.data.slice()}),putImageData:v=>{canvas.pixels=v}});
  return canvas;
 },encode:async canvas=>new Blob([canvas.pixels.data])});
 const request={page:0,width:20,height:20};
 for(const [key,value] of Object.entries({ink:10,contrast:25,darken:35,whiten:160,sharpen:80})){
  const expected={...original,data:before.slice()};await enhanceImage(expected,{[key]:value});
  const actual=await source.render({...request,enhancement:{[key]:value}});
  assert.deepEqual(new Uint8ClampedArray(await actual.blob.arrayBuffer()),expected.data,key);
 }
 const reset=await source.render(request);
 assert.deepEqual(new Uint8ClampedArray(await reset.blob.arrayBuffer()),before);
 assert.deepEqual(original.data,before);
 source.clear();
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
test('fixed-size Kindle comic page uses raster bounds, not the measurement iframe',()=>{
 const image={x:8,y:8,width:650,height:904,naturalWidth:650,naturalHeight:904,resource:'blob:page',order:0};
 const base={width:1000,height:1200,characters:0,images:[image]};
 assert.equal(imageSectionEvidence(base).imageOnly,false);
 const geometry=imagePageGeometry(base);
 assert.deepEqual([geometry.width,geometry.height],[650,904]);
 assert.deepEqual([geometry.images[0].x,geometry.images[0].y],[0,0]);
 assert.equal(imageSectionEvidence({...base,...geometry}).imageCoverage,1);
 assert.equal(imageSectionEvidence({...base,...geometry}).imageOnly,true);
 assert.deepEqual([image.x,image.y],[8,8],'original DOM geometry remains unchanged');
});
test('image bounds preserve fragment gaps, overlap, source and order without promoting mixed text',()=>{
 const image={x:100,y:50,width:300,height:500,naturalWidth:600,naturalHeight:1000,order:0,resource:'blob:a'};
 const base={width:1000,height:1200,characters:0,images:[image,{...image,x:420,order:1,resource:'blob:b'}]};
 const geometry=imagePageGeometry(base);
 assert.deepEqual([geometry.width,geometry.height],[620,500]);
 assert.deepEqual(geometry.images.map(i=>[i.x,i.y,i.order,i.resource]),[[0,0,0,'blob:a'],[320,0,1,'blob:b']]);
 assert.equal(imageSectionEvidence({...base,...geometry}).imageOnly,true);
 for(const candidate of [{...base,characters:1},{...base,images:[]}])
  assert.deepEqual(imagePageGeometry(candidate),{width:candidate.width,height:candidate.height,images:candidate.images});
 assert.deepEqual(imagePageGeometry(base,false),{width:base.width,height:base.height,images:base.images});
 const icon={...image,width:32,height:32,naturalWidth:32,naturalHeight:32};
 const small={...base,images:[icon]};
 assert.equal(imageSectionEvidence({...small,...imagePageGeometry(small)}).imageOnly,false);
 const sparse={...base,images:[image,{...image,x:1900}]};
 assert.equal(imageSectionEvidence({...sparse,...imagePageGeometry(sparse)}).imageOnly,false);
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
 const detection=await source.render({...request,analyzeCrop:true,detectionOnly:true,margin:.05});
 assert.equal(detection.blob,undefined);assert.ok(detection.cropDetection.crop.width<1);assert.equal(rendered,4,'no PNG encoded for reading detection');
 assert.ok(canvases.every(c=>c.width===0&&c.height===0));source.clear();
});
test('editor reuses one immutable raster across enhancements and original comparison',async()=>{
 let renders=0;
 const original=raster(20,20,220);rect(original,8,3,2,12,50);
 const before=original.data.slice();
 const page={getViewport:({scale,rotation=0})=>({width:20*scale,height:20*scale,scale,rotation}),
  render:({canvasContext})=>{renders++;canvasContext.putImageData({...original,data:before.slice()});return {promise:Promise.resolve(),cancel(){}}}};
 const renderer=createPdfRegionRenderer({numPages:2,getPage:async()=>page},{cacheRaster:true,
  createCanvas:()=>{const c={width:0,height:0};c.getContext=()=>({
   getImageData:()=>({...original,data:c.data.slice()}),
   putImageData:p=>{c.data=p.data.slice()}});return c},encode:async c=>new Blob([c.data])});
 for(const enhancement of [{},{whiten:200},{contrast:20},{darken:15},{sharpen:40},{ink:2},{}]) {
  const result=await renderer.render({page:0,width:20,height:20,enhancement});
  const expected={...original,data:before.slice()};await enhanceImage(expected,enhancement);
  assert.deepEqual(new Uint8ClampedArray(await result.blob.arrayBuffer()),expected.data);
 }
 assert.equal(renders,1,'slider changes do not rasterize PDF again');
 await renderer.render({page:1,width:20,height:20});assert.equal(renders,2);
 await renderer.render({page:0,width:20,height:20,enhancement:{contrast:21}});assert.equal(renders,3,'only one raw page is retained');
 renderer.clear();await renderer.render({page:0,width:20,height:20});assert.equal(renders,4);
 assert.deepEqual(original.data,before);
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
