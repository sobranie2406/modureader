import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {runInNewContext} from 'node:vm';
const read=name=>readFile(new URL(`../assets/foliate-js/src/${name}.js`,import.meta.url),'utf8');
const geometry=await read('annotation-geometry');
const {annotationPointMapper,annotationRect}=await import(`data:text/javascript;base64,${Buffer.from(geometry).toString('base64')}`);
const {JSDOM}=createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');

test('chapter padding and parent scrolling are mapped to the real SVG origin',()=>{
  for(const parentScroll of [0,500,2000,5000,-300]) {
    const doc={defaultView:{frameElement:{offsetWidth:400,offsetHeight:2000,clientLeft:0,clientTop:0,
      getBoundingClientRect:()=>({left:20,top:100-parentScroll,width:400,height:2000})}}};
    const svg={getScreenCTM:()=>({inverse:()=>({a:1,b:0,c:0,d:1,e:-20,f:-(68-parentScroll)})})};
    const map=annotationPointMapper(doc,svg);
    const rect=annotationRect({left:10,top:300,right:90,bottom:330},map);
    assert.deepEqual(rect,{left:10,top:332,right:90,bottom:362,width:80,height:30});
    assert.deepEqual(map({x:20,y:310}),{x:20,y:342});
  }
});

test('frame borders and scaling compose with SVG transforms instead of accumulating offsets',()=>{
  const frame={offsetWidth:400,offsetHeight:1000,clientLeft:2,clientTop:3,
    getBoundingClientRect:()=>({left:100,top:300,width:800,height:2000})};
  const svg={getScreenCTM:()=>({inverse:()=>({a:.5,b:0,c:0,d:.5,e:-40,f:-100})})};
  const map=annotationPointMapper({defaultView:{frameElement:frame}},svg);
  assert.deepEqual(map({x:10,y:20}),{x:22,y:73});
  const rect=annotationRect({left:10,top:20,right:30,bottom:40},map);
  assert.equal(rect.width,20);assert.equal(rect.height,20);
});

test('new marks, redraw and hit testing use the same coordinates after iframe scroll',async()=>{
  const dom=new JSDOM('<body><iframe></iframe></body>',{pretendToBeVisual:true});
  const host=dom.window.document,frame=host.querySelector('iframe'),doc=frame.contentDocument;
  doc.body.innerHTML='<p>测试批注与正文</p>';
  Object.defineProperties(frame,{offsetWidth:{value:400},offsetHeight:{value:2000}});
  let outer=0,inner=0;
  frame.getBoundingClientRect=()=>({left:0,top:100-outer,width:400,height:2000});
  const pending=new Map();let sequence=0;
  doc.defaultView.requestAnimationFrame=fn=>{pending.set(++sequence,fn);return sequence;};
  doc.defaultView.cancelAnimationFrame=id=>pending.delete(id);
  const source=await read('overlayer');
  const Overlayer=runInNewContext(source.replace(/^import .*$/gm,'').replace('export class Overlayer','class Overlayer')+'\nOverlayer',
    {document:host,Range:dom.window.Range,navigator:{userAgent:'Chrome'},window:dom.window,
      annotationPointMapper,annotationRect,SearchHighlighter:class {clear(){} remove(){} redraw(){}}});
  const layer=new Overlayer(doc);host.body.append(layer.element);
  layer.element.getScreenCTM=()=>({inverse:()=>({a:1,b:0,c:0,d:1,e:0,f:-(68-outer)})});
  const range=doc.createRange();range.setStart(doc.querySelector('p').firstChild,0);range.setEnd(range.startContainer,4);
  range.getClientRects=()=>[{left:10,top:300-inner,right:90,bottom:330-inner,width:80,height:30}];
  layer.add('note',range,Overlayer.highlight,{color:'#f90'});
  assert.equal(layer.element.querySelector('rect').getAttribute('y'),'332');
  for(const y of [150,800,1900,1000,400,0]) {
    outer=y;layer.redraw();
    assert.equal(layer.element.querySelector('rect').getAttribute('y'),'332');
  }
  inner=72;
  // Hit testing is correct even before the queued redraw has executed.
  assert.equal(layer.hitTest({x:20,y:240})[0],'note');
  doc.dispatchEvent(new dom.window.Event('scroll'));
  doc.dispatchEvent(new dom.window.Event('scroll'));
  assert.equal(pending.size,1);
  const callback=[...pending.values()][0];pending.clear();callback();
  assert.equal(layer.element.querySelector('rect').getAttribute('y'),'260');
  assert.equal(layer.hitTest({x:20,y:310}).length,0);
  doc.dispatchEvent(new dom.window.Event('scroll'));assert.equal(pending.size,1);
  layer.destroy();assert.equal(pending.size,0);assert.equal(layer.element.children.length,0);
  doc.dispatchEvent(new dom.window.Event('scroll'));assert.equal(pending.size,0);
  dom.window.close();
});

test('late overlay attachment initializes layout without recursively activating chapters',async()=>{
  const source=await read('paginator');
  const setter=source.slice(source.indexOf('  set overlayer('),source.indexOf('  get overlayer('));
  const calls=[];
  const View=runInNewContext(`(class {#overlayer;#element={append:()=>{}};expand(notify){calls.push(notify)} ${setter}})`,{calls});
  new View().overlayer={element:{}};
  assert.deepEqual(calls,[false]);
  assert.ok(source.includes('entry.view.overlayer?.redraw()'));
  assert.ok(source.includes('this.#overlayer?.destroy()'));
});
