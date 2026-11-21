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
  window.flutter_inappwebview={callHandler(name,text,id,prefetch){return new Promise(resolve=>calls.push({name,text,id,prefetch,resolve}));}};
  const Translator=runInNewContext(source.replace(/export /g,'')+'\nTranslator',
    {window,document:window.document,Node:window.Node,IntersectionObserver:Observer,console});
  const translator=new Translator(), elements=[...window.document.querySelectorAll('p')];
  elements.forEach((el,i)=>{
    el.getBoundingClientRect=()=>({top:i===2?3000:20+i*30,bottom:i===2?3040:45+i*30,left:10,right:150});
    el.getClientRects=()=>{
      const rect=el.getBoundingClientRect();
      return [{...rect,width:rect.right-rect.left,height:rect.bottom-rect.top}];
    };
  });
  translator.observeDocument(window.document);
  return {dom,window,translator,calls,observers,elements};
}

function chapter(s, texts, visible = false) {
  const frame=s.window.document.createElement('iframe');
  s.window.document.body.append(frame);
  const doc=frame.contentDocument;
  Object.defineProperty(doc.defaultView.HTMLElement.prototype,'innerText',{
    get(){return this.textContent;}});
  const elements=texts.map(text=>{
    const el=doc.createElement('p');el.textContent=text;doc.body.append(el);
    el.getBoundingClientRect=()=>({top:20,bottom:50,left:10,right:150});
    el.getClientRects=()=>[{top:20,bottom:50,left:10,right:150,width:140,height:30}];
    return el;
  });
  frame.getBoundingClientRect=()=>({top:visible?0:5000,left:0,width:400,height:800});
  const range=doc.createRange();range.selectNodeContents(doc.body);
  return {frame,doc,elements,range,close(){frame.remove()}};
}

function onlyFirstVisible(s) {
  s.elements[1].getBoundingClientRect=()=>({top:1000,bottom:1050,left:10,right:150});
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

test('pretranslation waits for visible work, caches only the upcoming range and renders on arrival', async()=>{
  const s=setup();
  const [,next,far]=s.elements;
  const future=()=>({top:1000,bottom:1050,left:10,right:150});
  next.getBoundingClientRect=future;
  const range=s.window.document.createRange();
  range.selectNode(next);

  s.translator.addPrefetchRange(range,1);
  assert.equal(s.calls.length,0);
  await s.translator.setTranslationMode('bilingual',6);
  s.translator.addPrefetchRange(range,1);
  assert.deepEqual(s.calls.map(call=>[call.text,call.prefetch]),[['first',0]]);
  s.calls[0].resolve('当前页');await tick();
  assert.deepEqual(s.calls.map(call=>[call.text,call.prefetch]),[['first',0],['second',1]]);
  s.calls[1].resolve('下一页');await tick();
  assert.equal(next.querySelector('.translated-text'),null,'ahead content must not change pagination');
  assert.equal(far.querySelector('.translated-text'),null);

  next.getBoundingClientRect=()=>({top:20,bottom:70,left:10,right:150});
  s.translator.observeVisibleRange(range);
  await tick();
  assert.equal(next.querySelector('.translated-text').textContent,'下一页');
  assert.equal(s.calls.length,2);
  s.translator.destroy();s.dom.window.close();
});

test('closing the prefetch window drops future jobs', async()=>{
  const s=setup();
  const [,next,far]=s.elements;
  next.getBoundingClientRect=()=>({top:1000,bottom:1050,left:10,right:150});
  const range=s.window.document.createRange();
  range.setStartBefore(next);range.setEndAfter(far);
  await s.translator.setTranslationMode('bilingual',7);
  s.translator.addPrefetchRange(range,5);
  s.translator.clearPrefetchQueue();
  s.calls[0].resolve('当前页');await tick();
  assert.equal(s.calls.length,1);
  s.translator.destroy();s.dom.window.close();
});

test('prefetch skips a hidden paragraph between range endpoints', async()=>{
  const s=setup();
  const [,hidden,far]=s.elements;
  hidden.getBoundingClientRect=()=>({top:1000,bottom:1050,left:10,right:150});
  hidden.style.visibility='hidden';
  const range=s.window.document.createRange();
  range.setStartBefore(hidden);range.setEndAfter(far);
  await s.translator.setTranslationMode('bilingual',8);
  s.translator.addPrefetchRange(range,2);
  s.calls[0].resolve('当前页');await tick();
  assert.deepEqual(s.calls.map(call=>call.text),['first','far away']);
  s.translator.destroy();s.calls[1].resolve('后续页');await tick();s.dom.window.close();
});

test('prepared chapter text survives immediate frame disposal and is reused by its visible DOM', async()=>{
  const s=setup();onlyFirstVisible(s);
  const ahead=chapter(s,['next title','next paragraph']);
  await s.translator.setTranslationMode('bilingual',9);
  s.translator.addPrefetchRange(ahead.range,2);
  assert.equal(s.translator.observedElements.has(ahead.elements[0]),false);
  ahead.close();
  s.calls[0].resolve('当前页');await tick();
  assert.equal(s.calls[1].text,'next title');
  s.calls[1].resolve('下一章标题');await tick();
  assert.equal(s.calls[2].text,'next paragraph');
  s.calls[2].resolve('下一章正文');await tick();
  const actual=chapter(s,['next title','next paragraph'],true);
  s.translator.observeDocument(actual.doc);
  assert.equal(actual.doc.querySelector('.translated-text'),null);
  s.translator.observeVisibleRange(actual.range);await tick();
  assert.deepEqual([...actual.doc.querySelectorAll('.translated-text')].map(el=>el.textContent),
    ['下一章标题','下一章正文']);
  assert.equal(s.calls.length,3);
  s.translator.destroy();actual.close();s.dom.window.close();
});

test('range invalidation keeps the active answer, drops old plans and prioritizes newly visible text', async()=>{
  const s=setup();onlyFirstVisible(s);
  const old=chapter(s,['arriving paragraph','discarded plan']);
  const later=chapter(s,['appended plan']);
  await s.translator.setTranslationMode('bilingual',10);
  s.translator.addPrefetchRange(old.range,2);
  s.calls[0].resolve('当前页');await tick();
  assert.equal(s.calls[1].text,'arriving paragraph');
  s.translator.clearPrefetchQueue();old.close();
  const actual=chapter(s,['arriving paragraph','visible first'],true);
  s.translator.observeDocument(actual.doc);
  s.translator.observeVisibleRange(actual.range);
  s.translator.addPrefetchRange(actual.range,2);
  s.translator.addPrefetchRange(later.range,2);
  assert.equal(s.calls.length,2);
  s.calls[1].resolve('到达段落');await tick();
  assert.equal(actual.elements[0].querySelector('.translated-text').textContent,'到达段落');
  assert.deepEqual(s.calls.map(call=>[call.text,call.prefetch]),
    [['first',0],['arriving paragraph',2],['visible first',0]]);
  s.calls[2].resolve('可见内容');await tick();
  assert.equal(s.calls[3].text,'appended plan');
  assert.equal(later.doc.querySelector('.translated-text'),null);
  s.calls[3].resolve('后续内容');await tick();
  assert.equal(s.calls.length,4);
  s.translator.destroy();actual.close();later.close();s.dom.window.close();
});

test('force and session changes invalidate completed and in-flight ahead results', async()=>{
  const s=setup();onlyFirstVisible(s);
  const ahead=chapter(s,['completed source','in-flight source']);
  await s.translator.setTranslationMode('bilingual',11);
  s.translator.addPrefetchRange(ahead.range,1);
  ahead.close();s.calls[0].resolve('当前页');await tick();
  s.calls[1].resolve('旧缓存');await tick();
  assert.equal(s.calls[2].text,'in-flight source');
  s.elements.forEach(el=>el.getBoundingClientRect=()=>({top:3000,bottom:3050,left:10,right:150}));
  s.translator.clearTranslations();
  await s.translator.setTranslationMode('off');
  const actual=chapter(s,['completed source','in-flight source'],true);
  s.translator.observeDocument(actual.doc);
  await s.translator.setTranslationMode('bilingual',12);
  s.calls[2].resolve('晚到的旧译文');await tick();
  assert.deepEqual([s.calls[3].text,s.calls[3].id,s.calls[3].prefetch],['completed source',12,0]);
  s.calls[3].resolve('新译文一');await tick();
  assert.deepEqual([s.calls[4].text,s.calls[4].id,s.calls[4].prefetch],['in-flight source',12,0]);
  s.calls[4].resolve('新译文二');await tick();
  assert.deepEqual([...actual.doc.querySelectorAll('.translated-text')].map(el=>el.textContent),
    ['新译文一','新译文二']);
  s.translator.destroy();actual.close();s.dom.window.close();
});

test('prefetch snapshots exclude hidden, filtered and injected output nodes', async()=>{
  const s=setup();onlyFirstVisible(s);
  const ahead=chapter(s,['display hidden','visibility hidden','injected output','mixed output','kept','valid source']);
  ahead.elements[0].style.display='none';
  ahead.elements[1].style.visibility='hidden';
  ahead.elements[2].className='translated-text';
  const output=ahead.doc.createElement('span');output.className='translated-text';output.textContent='already translated';
  ahead.elements[3].append(output);
  const filtered=ahead.doc.createElement('span');filtered.setAttribute('data-modu-text-filter','');
  filtered.style.display='none';filtered.textContent='filtered secret';ahead.elements[4].append(filtered);
  // Browser innerText omits display:none runs; jsdom has no layout implementation.
  Object.defineProperty(ahead.elements[4],'innerText',{get(){return 'kept'}});
  await s.translator.setTranslationMode('bilingual',13);
  for(const pages of [0,6,1.5,NaN])s.translator.addPrefetchRange(ahead.range,pages);
  s.translator.addPrefetchRange(ahead.range,2);ahead.close();
  s.calls[0].resolve('当前页');await tick();
  assert.equal(s.calls[1].text,'kept');
  s.calls[1].resolve('保留');await tick();
  assert.equal(s.calls[2].text,'valid source');
  s.calls[2].resolve('有效正文');await tick();
  assert.equal(s.calls.length,3);
  s.translator.destroy();s.dom.window.close();
});

test('background and stop cannot start or retain stale speculative work', async()=>{
  const s=setup();onlyFirstVisible(s);
  const ahead=chapter(s,['future source']);
  await s.translator.setTranslationMode('bilingual',14);
  Object.defineProperty(s.window.document,'hidden',{value:true,configurable:true});
  s.translator.addPrefetchRange(ahead.range,1);
  Object.defineProperty(s.window.document,'hidden',{value:false,configurable:true});
  s.translator.addPrefetchRange(ahead.range,1);
  Object.defineProperty(s.window.document,'hidden',{value:true,configurable:true});
  s.calls[0].resolve('当前页');await tick();
  assert.equal(s.calls.length,1);
  Object.defineProperty(s.window.document,'hidden',{value:false,configurable:true});
  s.translator.addPrefetchRange(ahead.range,1);ahead.close();
  assert.equal(s.calls[1].text,'future source');
  await s.translator.setTranslationMode('off');
  const actual=chapter(s,['future source'],true);s.translator.observeDocument(actual.doc);
  await s.translator.setTranslationMode('bilingual',15);
  s.calls[1].resolve('停止后的旧结果');await tick();
  assert.deepEqual([s.calls[2].text,s.calls[2].id,s.calls[2].prefetch],['future source',15,0]);
  s.calls[2].resolve('新请求');await tick();
  assert.equal(actual.elements[0].querySelector('.translated-text').textContent,'新请求');
  s.translator.destroy();actual.close();s.dom.window.close();
});

test('all planned short paragraphs run while the reusable cache retains only its bounded window', async()=>{
  const s=setup();onlyFirstVisible(s);
  const texts=Array.from({length:513},(_,i)=>`future ${i}`),ahead=chapter(s,texts);
  await s.translator.setTranslationMode('bilingual',16);
  s.translator.addPrefetchRange(ahead.range,5);ahead.close();
  s.calls[0].resolve('当前页');await tick();
  for(let i=0;i<texts.length;i++) {
    assert.equal(s.calls[i+1].text,texts[i]);
    s.calls[i+1].resolve(`译文${i}`);await tick();
  }
  const actual=chapter(s,[texts[0],texts.at(-1)],true);
  s.translator.observeDocument(actual.doc);s.translator.observeVisibleRange(actual.range);
  assert.equal(s.calls.length,515);
  assert.equal(s.calls.at(-1).text,texts[0],'oldest speculative entry is evicted');
  s.calls.at(-1).resolve('重新翻译');await tick();
  assert.equal(actual.elements[1].querySelector('.translated-text').textContent,'译文512');
  assert.equal(s.calls.length,515,'latest cached entry is reused');
  s.translator.destroy();actual.close();s.dom.window.close();
});

test('speculative cache also bounds source and answer characters', async()=>{
  const s=setup();onlyFirstVisible(s);
  const ahead=chapter(s,['first large','second large','oversized']);
  await s.translator.setTranslationMode('bilingual',17);
  s.translator.addPrefetchRange(ahead.range,5);ahead.close();
  s.calls[0].resolve('当前页');await tick();
  s.calls[1].resolve('甲'.repeat(256*1024));await tick();
  s.calls[2].resolve('乙'.repeat(256*1024));await tick();
  s.calls[3].resolve('丙'.repeat(512*1024));await tick();
  const actual=chapter(s,['first large','second large','oversized'],true);
  s.translator.observeDocument(actual.doc);s.translator.observeVisibleRange(actual.range);
  assert.equal(s.calls[4].text,'first large');s.calls[4].resolve('新一');await tick();
  assert.equal(actual.elements[1].querySelector('.translated-text').textContent.length,256*1024);
  assert.equal(s.calls[5].text,'oversized');s.calls[5].resolve('新三');await tick();
  assert.equal(s.calls.length,6);
  s.translator.destroy();actual.close();s.dom.window.close();
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
