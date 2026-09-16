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

test('failure/cancellation never inserts an error string into book content',async()=>{
  const s=setup();await s.translator.setTranslationMode('bilingual',1);
  s.calls[0].resolve(null);await tick();
  assert.equal(s.elements[0].querySelector('.translated-text'),null);
  s.translator.destroy();s.calls[1].resolve('late');await tick();s.dom.window.close();
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
  assert.match(player,/void dispose\(\) \{\s*_translationSession.stop\(\)/);
  const panel=await readFile(new URL('../lib/widgets/reading_page/translation_widget.dart',import.meta.url),'utf8');
  assert.match(panel,/onPressed: _stopTranslation/);
  assert.doesNotMatch(panel,/setBookTranslationMode\(widget.bookId, _displayMode\)/);
  const page=await readFile(new URL('../lib/page/reading_page.dart',import.meta.url),'utf8');
  assert.match(page,/reader-floating-stop-translation/);
});
