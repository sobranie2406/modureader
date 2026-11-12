import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const {JSDOM} = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/desktop-page-input.js', import.meta.url),'utf8');
const {desktopWheelZoomDirection, installDesktopPageInput} = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

for (const modifier of ['ctrl','meta']) {
  test(`${modifier} wheel requires the exact platform modifier`, () => {
    const event = {deltaY:-100, [modifier+'Key']:true};
    assert.equal(desktopWheelZoomDirection(event,modifier),1);
    assert.equal(desktopWheelZoomDirection({...event,deltaY:100},modifier),-1);
    for (const extra of [{shiftKey:true},{altKey:true},{ctrlKey:true,metaKey:true},
      {defaultPrevented:true},{deltaY:0},{deltaY:NaN},{deltaX:200}]) {
      assert.equal(desktopWheelZoomDirection({...event,...extra},modifier),0);
    }
    assert.equal(desktopWheelZoomDirection({deltaY:100},modifier),0);
    assert.equal(desktopWheelZoomDirection({deltaY:100,
      [modifier==='meta'?'ctrlKey':'metaKey']:true},modifier),0);
  });
}

function fixture(modifier='ctrl') {
  const dom=new JSDOM('<body><p>PDF page</p><input><button>Menu</button></body>');
  const doc=dom.window.document,zooms=[];
  let active=true,pdf=true,normalWheel=0;
  const input=installDesktopPageInput(doc,{
    enabled:()=>active,zoomEnabled:()=>active&&pdf,zoomModifier:()=>modifier,
    turnPage:()=>assert.fail('Wheel zoom must not turn a page'),
    onZoom:direction=>zooms.push(direction),
  });
  doc.addEventListener('wheel',()=>normalWheel++);
  const wheel=(target=doc.body,extra={})=>{
    const event=new dom.window.WheelEvent('wheel',{
      bubbles:true,cancelable:true,deltaY:-100,[modifier+'Key']:true,...extra});
    target.dispatchEvent(event);return event;
  };
  return {dom,doc,input,wheel,zooms,set active(v){active=v},set pdf(v){pdf=v},
    get normalWheel(){return normalWheel},close(){input.destroy();dom.window.close()}};
}

for(const modifier of ['ctrl','meta'])test(`${modifier} PDF zoom consumes wheel exactly once and cleans up`,async()=>{
  const h=fixture(modifier);
  try {
    assert.equal(h.wheel().defaultPrevented,true);
    assert.deepEqual(h.zooms,[1]);
    assert.equal(h.normalWheel,0);
    // Rapid events use one trailing change, avoiding one expensive render per tick.
    for(let i=0;i<10;i++) h.wheel();
    assert.equal(h.zooms.length,1);
    await new Promise(resolve=>setTimeout(resolve,100));
    assert.deepEqual(h.zooms,[1,1]);
    h.input.destroy();
    assert.equal(h.wheel().defaultPrevented,false);
    assert.deepEqual(h.zooms,[1,1]);
  } finally {h.close()}
});

test('ordinary reading, menus, input fields and normal scrolling do not zoom',()=>{
  const h=fixture();
  try {
    h.pdf=false;assert.equal(h.wheel().defaultPrevented,false);
    h.pdf=true;h.active=false;assert.equal(h.wheel().defaultPrevented,false);
    h.active=true;
    for(const selector of ['input','button'])
      assert.equal(h.wheel(h.doc.querySelector(selector)).defaultPrevented,false);
    assert.equal(h.wheel(h.doc.body,{ctrlKey:false}).defaultPrevented,false);
    assert.deepEqual(h.zooms,[]);
    assert.equal(h.normalWheel,5);
  } finally {h.close()}
});

test('pending wheel zoom is discarded when an overlay takes reader activity',async()=>{
  const h=fixture();
  try {
    h.wheel();h.wheel();h.active=false;
    await new Promise(resolve=>setTimeout(resolve,100));
    assert.deepEqual(h.zooms,[1]);
  } finally {h.close()}
});

test('reader wiring targets only PDF even when comparison text owns the keyboard',async()=>{
  const book=await readFile(new URL('../assets/foliate-js/src/book.js',import.meta.url),'utf8');
  const method=book.slice(book.indexOf('  installDesktopInput(doc) {'),book.indexOf('  turnFromKeyboard(direction) {'));
  for(const isPdf of [false,true]) {
    const h=fixture('meta'),documents=new WeakMap(),calls=[];
    h.input.destroy();
    h.dom.window.isFootNoteOpen=()=>false;
    const renderer={readerActive:true,getContents:()=>[{doc:h.doc}]};
    const install=new Function('isPdf','style','window','desktopInputDocuments',
      'installDesktopPageInput','callFlutter',`return ({${method}}).installDesktopInput`)(
        isPdf,{desktopPageInput:true,desktopZoomModifier:'meta'},h.dom.window,
        documents,installDesktopPageInput,(...args)=>calls.push(args));
    install.call({keyboardActive:false,view:{renderer}},h.doc);
    try {
      assert.equal(h.wheel().defaultPrevented,isPdf);
      assert.deepEqual(calls,isPdf?[['onReaderWheelZoom',1]]:[]);
      renderer.readerActive=false;
      assert.equal(h.wheel().defaultPrevented,false);
    } finally {documents.get(h.doc).destroy();h.close()}
  }
});
