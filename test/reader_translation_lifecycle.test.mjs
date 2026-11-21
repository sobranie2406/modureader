import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {runInNewContext} from 'node:vm';
const {JSDOM}=createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const source=await readFile(new URL('../assets/foliate-js/src/translator.js',import.meta.url),'utf8');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function setup() {
  const dom=new JSDOM('<body><p>first</p><p>second</p><p>far away</p></body>',{pretendToBeVisual:true});
  const {window}=dom, calls=[], observers=[];
  Object.defineProperty(window.HTMLElement.prototype,'innerText',{get(){return this.textContent;}});
  class Observer {
    constructor(callback,options){this.callback=callback;this.options=options;this.items=new Set();observers.push(this);}
    observe(el){this.items.add(el);}
    unobserve(el){this.items.delete(el);}
    disconnect(){this.items.clear();}
  }
  window.flutter_inappwebview={callHandler(name,text,id){return new Promise(resolve=>calls.push({name,text,id,resolve}));}};
  const Translator=runInNewContext(source.replace(/export /g,'')+'\nTranslator',
    {window,document:window.document,Node:window.Node,IntersectionObserver:Observer,console});
  const translator=new Translator(), elements=[...window.document.querySelectorAll('p')];
  elements.forEach((el,i)=>el.getBoundingClientRect=()=>({top:i===2?3000:20+i*30,bottom:i===2?3040:45+i*30,left:10,right:150}));
  translator.observeDocument(window.document);
  return {dom,window,translator,calls,observers,elements};
}

test('translation style affects only output and switches independent appearances without requests', async()=>{
  const s=setup();
  s.elements[0].style.cssText='font-family: serif; font-size: 18px; font-weight: 400; font-style: normal; color: #343434';
  const original=s.elements[0].getAttribute('style');
  s.translator.setTextStyle({font:'monospace',size:32,bold:true,italic:true,color:'#287D75'});
  await s.translator.setTranslationMode('bilingual',1);
  s.calls[0].resolve('译文'); await tick();
  s.calls[1].resolve('第二段'); await tick();
  let output=s.elements[0].querySelector('.translated-text');
  assert.equal(output.style.fontFamily,'monospace');
  assert.equal(output.style.fontSize,'32px');
  assert.equal(output.style.fontWeight,'700');
  assert.equal(output.style.fontStyle,'italic');
  assert.equal(output.style.color,'rgb(40, 125, 117)');
  assert.equal(s.elements[0].getAttribute('style'),original);
  const count=s.calls.length;
  s.translator.setTextStyle({font:'sans-serif',size:20,bold:false,italic:false,color:'#287FA3'});
  assert.equal(output.style.fontSize,'20px');
  assert.equal(output.style.fontWeight,'400');
  assert.equal(output.style.color,'rgb(40, 127, 163)');
  assert.equal(s.calls.length,count);
  await s.translator.setTranslationMode('translation-only',1);
  assert.equal(output.style.fontSize,'20px');
  await s.translator.setTranslationMode('off');
  s.translator.setTextStyle({font:'serif',size:26,bold:true,italic:false});
  await s.translator.setTranslationMode('bilingual',2);
  assert.equal(output.style.fontFamily,'serif');
  assert.equal(output.style.fontSize,'26px');
  assert.equal(output.style.fontStyle,'normal');
  assert.equal(output.style.color,'');
  assert.equal(s.calls.length,count);
  assert.equal(s.elements[0].getAttribute('style'),original);
  for (const size of [8, 16, 17.6, 48]) {
    s.translator.setTextStyle({size});
    assert.equal(output.style.fontSize, `${size}px`);
    assert.equal(s.elements[0].getAttribute('style'), original);
    assert.equal(s.calls.length, count);
  }
  await s.translator.setTranslationMode('off');
  s.translator.setTextStyle(null);
  assert.equal(output.style.fontSize,'');
  assert.equal(output.style.fontFamily,'');
  assert.equal(s.elements[0].getAttribute('style'),original);
  s.translator.destroy();s.dom.window.close();
});

test('explicit start translates visible paragraphs serially and deduplicates observer events',async()=>{
  const s=setup(); assert.equal(s.calls.length,0);
  await s.translator.setTranslationMode('bilingual',7);
  assert.equal(s.calls.length,1);assert.equal(s.calls[0].id,7);
  s.observers[0].callback(s.elements.map(target=>({target,isIntersecting:true})));
  assert.equal(s.calls.length,1);
  s.calls[0].resolve('一');await tick();
  assert.equal(s.calls.length,2);assert.equal(s.calls[1].text,'second');
  s.calls[1].resolve('二');await tick();assert.equal(s.calls.length,2);
  assert.equal(s.window.document.querySelectorAll('.translated-text').length,2);
  assert.equal(s.observers[0].options.rootMargin,'0px');
  s.translator.destroy();s.dom.window.close();
});

test('stop discards queued and late results; restart has a fresh generation',async()=>{
  const s=setup();await s.translator.setTranslationMode('bilingual',1);
  await s.translator.setTranslationMode('off');
  s.calls[0].resolve('stale');await tick();
  assert.equal(s.calls.length,1);assert.equal(s.window.document.querySelector('.translated-text'),null);
  await s.translator.setTranslationMode('bilingual',3);
  assert.equal(s.calls.length,2);assert.equal(s.calls[1].id,3);
  s.calls[1].resolve('fresh');await tick();
  assert.equal(s.elements[0].querySelector('.translated-text').textContent,'fresh');
  s.translator.destroy();s.calls[2].resolve('late');await tick();
  assert.equal(s.window.document.querySelector('.translated-text'),null);
  assert.equal(s.observers[0].items.size,0);s.dom.window.close();
});

test('preloaded offscreen iframe and horizontal pages are not sent',async()=>{
  const s=setup();const frame=s.window.document.createElement('iframe');s.window.document.body.append(frame);
  frame.contentDocument.body.innerHTML='<p>preloaded chapter</p>';
  const p=frame.contentDocument.querySelector('p');p.getBoundingClientRect=()=>({top:10,bottom:30,left:10,right:100});
  frame.getBoundingClientRect=()=>({top:5000,bottom:6000,left:0,right:400,width:400,height:1000});
  s.elements[1].getBoundingClientRect=()=>({top:10,bottom:30,left:5000,right:5100});
  s.translator.observeDocument(frame.contentDocument);
  await s.translator.setTranslationMode('bilingual',2);
  s.calls[0].resolve('译');await tick();
  assert.equal(s.calls.length,1);s.translator.destroy();s.dom.window.close();
});

test('pagination requeues a displaced paragraph when only its tail becomes visible', async()=>{
  const s=setup();
  const [first,tail,nextPage]=s.elements;
  const visible=()=>({top:20,bottom:60,left:10,right:150});
  s.window.document.addEventListener('modu-translation-layout',()=>{
    if (first.querySelector('.translated-text'))
      tail.getBoundingClientRect=()=>({top:20,bottom:60,left:5000,right:5140});
  });
  await s.translator.setTranslationMode('bilingual',4);
  s.calls[0].resolve('第一段译文');await tick();
  assert.deepEqual(s.calls.map(call=>call.text),['first']);

  tail.getBoundingClientRect=visible;
  nextPage.getBoundingClientRect=visible;
  const range=s.window.document.createRange();
  range.setStart(tail.firstChild,3);
  range.setEnd(tail.firstChild,6);
  // The new page supplies a visible range even if IntersectionObserver missed it.
  s.translator.observeVisibleRange(range);
  s.translator.observeVisibleRange(range);
  assert.deepEqual(s.calls.map(call=>call.text),['first','second']);
  s.calls[1].resolve('完整的第二段译文');await tick();
  assert.equal(tail.querySelector('.translated-text').textContent,'完整的第二段译文');
  s.translator.destroy();s.dom.window.close();
});

test('failure/cancellation never inserts an error string into book content',async()=>{
  const s=setup();await s.translator.setTranslationMode('bilingual',1);
  s.calls[0].resolve(null);await tick();
  assert.equal(s.elements[0].querySelector('.translated-text'),null);
  s.translator.destroy();s.calls[1].resolve('late');await tick();s.dom.window.close();
});

test('translation insertion, display switches and clearing notify layout synchronously',async()=>{
  const s=setup(), displays=[];
  s.window.document.addEventListener('modu-translation-layout',()=>{
    const wrapper=s.elements[0].querySelector('.translated-text');
    displays.push(wrapper?.style.display ?? null);
  });
  await s.translator.setTranslationMode('bilingual',1);
  s.calls[0].resolve('译文');await tick();
  assert.equal(displays.at(-1),'block');
  await s.translator.setTranslationMode('translation-only',1);
  assert.equal(s.elements[0].textContent,'译文');
  assert.equal(displays.at(-1),'block');
  await s.translator.setTranslationMode('off');
  assert.equal(displays.at(-1),'none');
  s.translator.clearTranslations();
  assert.equal(displays.at(-1),null);
  s.translator.destroy();s.calls[1].resolve(null);await tick();s.dom.window.close();
});

test('display switches translate newly visible paragraphs without re-requesting cached ones',async()=>{
  const s=setup();await s.translator.setTranslationMode('bilingual',1);
  s.calls[0].resolve('一');await tick();s.calls[1].resolve('二');await tick();
  s.elements[2].getBoundingClientRect=()=>({top:100,bottom:140,left:10,right:150});
  await s.translator.setTranslationMode('translation-only',1);
  assert.equal(s.calls.length,3);assert.equal(s.calls[2].text,'far away');
  s.calls[2].resolve('三');await tick();
  await s.translator.setTranslationMode('bilingual',1);
  assert.equal(s.calls.length,3);
  s.translator.destroy();s.dom.window.close();
});

test('repeated popup disposal is safe and does not reconnect translation observers',()=>{
  const s=setup();
  s.translator.destroy();
  assert.doesNotThrow(()=>s.translator.destroy());
  assert.equal(s.observers[0].items.size,0);
  assert.equal(s.translator.observedElements.size,0);
  assert.equal(s.calls.length,0);
  s.dom.window.close();
});

test('a chapter container with an inline heading is not treated as one paragraph',async()=>{
  const s=setup();s.translator.destroy();
  // A span heading previously caused the surrounding div's entire chapter
  // innerText to be sent as a single translation request.
  const Translator=runInNewContext(source.replace(/export /g,'')+'\nTranslator',
    {window:s.window,document:s.window.document,Node:s.window.Node,
      IntersectionObserver:class {observe(){} disconnect(){}},console});
  s.window.document.body.innerHTML='<div><span>heading</span><p>first paragraph</p><p>second paragraph</p></div>';
  for(const el of s.window.document.querySelectorAll('*')) {
    el.getBoundingClientRect=()=>({top:10,bottom:30,left:10,right:200});
  }
  const translator=new Translator();translator.observeDocument(s.window.document);
  await translator.setTranslationMode('bilingual',10);
  assert.equal(s.calls[0].text,'heading');
  s.calls[0].resolve('标题');await tick();
  assert.equal(s.calls[1].text,'first paragraph');
  translator.destroy();s.calls[1].resolve(null);await tick();s.dom.window.close();
});

test('opening a book does not restore translation consent and stop remains available',async()=>{
  const player=await readFile(new URL('../lib/page/book_player/epub_player.dart',import.meta.url),'utf8');
  assert.doesNotMatch(player,/setTranslationMode\(\s*Prefs\(\)\.getBookTranslationMode/);
  const dispose = player.match(/void dispose\(\) \{([^}]+)\}/)?.[1];
  assert.ok(dispose, 'Reader must have a disposal hook');
  assert.match(dispose, /_translationSession\.stop\(\);[\s\S]*super\.dispose\(\);/);
  const panel=await readFile(new URL('../lib/widgets/reading_page/translation_widget.dart',import.meta.url),'utf8');
  assert.match(panel,/onPressed: _stopTranslation/);
  assert.doesNotMatch(panel,/setBookTranslationMode\(widget.bookId, _displayMode\)/);
  const page=await readFile(new URL('../lib/page/reading_page.dart',import.meta.url),'utf8');
  assert.doesNotMatch(page,/reader-floating-stop-translation/);
  assert.match(page,/TranslationToolbarAction\(/);
  const toolbar=await readFile(new URL('../lib/widgets/reading_page/translation_toolbar_action.dart',import.meta.url),'utf8');
  assert.match(toolbar,/reader-toolbar-stop-translation/);
  assert.match(toolbar,/onStop\(\)/);
});


test('detached chapter with no window cannot break starting, styling or stopping translation', async()=>{
  const s=setup();
  const old=s.window.document.implementation.createHTMLDocument('old chapter');
  old.body.innerHTML='<p>stale text</p>';
  const stale=old.querySelector('p');
  stale.getBoundingClientRect=()=>({top:10,bottom:30,left:10,right:100});
  assert.equal(stale.isConnected,true);
  assert.equal(old.defaultView,null);
  s.translator.observeDocument(old);
  s.translator.setTextStyle({font:'test',fontUrl:'http://localhost/test.ttf'});
  await s.translator.setTranslationMode('bilingual',1);
  assert.equal(s.calls.length,1);
  assert.equal(s.calls[0].text,'first');
  assert.equal(s.translator.observedElements.has(stale),false);
  assert.equal(s.observers[0].items.has(stale),false);
  await s.translator.setTranslationMode('off');
  s.translator.clearTranslations();
  s.calls[0].resolve('late'); await tick();
  assert.equal(old.querySelector('.translated-text'),null);
  s.translator.destroy();s.dom.window.close();
});
