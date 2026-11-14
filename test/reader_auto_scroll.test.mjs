import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
const source = await readFile(new URL('../assets/foliate-js/src/reader-auto-scroll.js', import.meta.url), 'utf8');
const {ReaderAutoScroll, autoScrollPixelsPerSecond} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const paginator = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
const gateSource = await readFile(new URL('../assets/foliate-js/src/reading-action-gate.js', import.meta.url), 'utf8');
const {ReadingActionGate} = await import(`data:text/javascript;base64,${Buffer.from(gateSource).toString('base64')}`);

function fixture() {
  const doc = Object.assign(new EventTarget(), {visibilityState:'visible', getSelection:()=>''});
  const host = Object.assign(new EventTarget(), {document:doc});
  const pending = new Map(), timers = new Map(), stopped = [], stoppedSessions = [], moves = [], flushed = [], enabled = [];
  let sequence = 0, now = 0, allowed = true;
  host.requestAnimationFrame = fn => { pending.set(++sequence, fn); return sequence };
  host.cancelAnimationFrame = id => pending.delete(id);
  host.performance = {now:()=>now};
  host.setTimeout = (fn,delay) => {timers.set(++sequence,{fn,at:now+delay,delay});return sequence};
  host.clearTimeout = id => timers.delete(id);
  let renderer = {autoScrollSupported:true, readerActive:true, isNavigating:false,
    getContents:()=>[{doc}], setAutoScrolling:value=>enabled.push(value),
    getAutoScrollSpeed:()=>30,
    getAutoScrollStep:()=>60,
    async autoScrollBy(distance, active) { if (!active()) return 'inactive'; moves.push(distance); return 'moved' },
    flushAutoScrollPosition:()=>flushed.push(moves.reduce((a,b)=>a+b,0))};
  const scroll = new ReaderAutoScroll({host, renderer:()=>renderer, canRun:()=>allowed,
    onStop:(reason,session)=>{stopped.push(reason);stoppedSessions.push({reason,session})}});
  const step = async (ms = 100) => {
    now += ms;
    const callbacks = [...pending.values()]; pending.clear();
    callbacks.forEach(fn=>fn(now));
    for(const [id,timer] of [...timers])if(timer.at<=now){timers.delete(id);await timer.fn()}
    await new Promise(resolve=>setImmediate(resolve));
  };
  return {doc, host, scroll, pending, timers, stopped, stoppedSessions, moves, flushed, enabled, step,
    get renderer(){return renderer}, set renderer(value){renderer=value},
    set allowed(value){allowed=value}};
}

test('time-based speed, low-speed whole pixels and position persistence stay bounded', async () => {
  const f = fixture();
  assert.equal(f.scroll.set({enabled:true}), true);
  await f.step(0);
  for (let n=0;n<10;n++) await f.step();
  assert.equal(f.moves.reduce((a,b)=>a+b,0),30);
  assert.deepEqual(f.flushed,[15,30]);
  assert.deepEqual(f.enabled,[true]);
  assert.equal(f.scroll.set({enabled:true,speed:.1}),true);
  for(let n=0;n<64;n++)await f.step(16);
  assert.equal(f.moves.reduce((a,b)=>a+b,0),33);
  assert.deepEqual(f.enabled,[true],'changing speed does not restart the session');
  f.scroll.stop();f.scroll.stop();
  assert.deepEqual(f.stopped,['manual']);
  assert.deepEqual(f.enabled,[true,false]);
  assert.equal(f.flushed.at(-1),33);
  assert.equal(f.pending.size,0);
});

test('stop notifications retain their start session while live speed changes do not restart it',async()=>{
  const f=fixture();
  assert.equal(f.scroll.set({enabled:true,session:'A'}),true);
  await f.step(0);await f.step();
  assert.equal(f.scroll.set({enabled:true,speed:2,session:'A'}),true);
  assert.equal(f.scroll.set({enabled:true,speed:2}),true);
  await f.step();
  assert.equal(f.scroll.session,'A');
  assert.deepEqual(f.moves,[3,6]);
  assert.deepEqual(f.enabled,[true]);
  assert.deepEqual(f.stoppedSessions,[]);
  f.scroll.stop('manual');f.scroll.stop('manual');
  assert.deepEqual(f.stoppedSessions,[{reason:'manual',session:'A'}]);
  assert.equal(f.scroll.set({enabled:true,speed:.5,session:'B'}),true);
  await f.step(0);await f.step();
  assert.equal(f.scroll.session,'B');
  assert.equal(f.moves.at(-1),1);
  f.scroll.stop('input');
  assert.deepEqual(f.stoppedSessions,[{reason:'manual',session:'A'},{reason:'input',session:'B'}]);
  assert.deepEqual(f.enabled,[true,false,true,false]);
  assert.equal(f.pending.size,0);
});

test('explicit stop immediately pauses and awaits the final progress bridge acknowledgement',async()=>{
  const f=fixture(), book=await readFile(new URL('../assets/foliate-js/src/book.js',import.meta.url),'utf8');
  const relocation=book.slice(book.indexOf('const onRelocated ='),book.indexOf('\nconst onAnnotationClick'));
  let acknowledge;
  const progress=new Promise(resolve=>acknowledge=resolve), messages=[];
  const notify=runInNewContext(`${relocation};onRelocated`,{
    window:{readerApplyingSync:false},reader:{view:{renderer:{writingMode:'horizontal-tb'},book:{sections:[]}}},
    style:{},applyVerticalPageChrome(){},callFlutter:(name,data)=>{messages.push({name,data});return progress},
  });
  f.renderer.flushAutoScrollPosition=()=>notify({cfi:'final-visible-position',fraction:.6,
    readingAction:true,chapterLocation:{current:2,total:5},location:{current:7,total:10}});
  const window={},bridge=book.slice(book.indexOf('const autoScroll ='),book.indexOf('\nconst setStyle ='));
  runInNewContext(bridge,{window,onRelocated:notify,ReaderAutoScroll:class{constructor(){return f.scroll}}});
  f.scroll.set({enabled:true,session:42});await f.step(0);await f.step();
  const stopped=window.stopReaderAutoScroll('host');
  assert.equal(f.scroll.running,false,'stopping and final relocation remain synchronous');
  assert.deepEqual(f.stoppedSessions,[{reason:'host',session:42}]);
  assert.equal(messages.at(-1).data.cfi,'final-visible-position');
  assert.equal(messages.at(-1).data.readingAction,true);
  assert.equal(stopped,notify.pending);
  let complete=false;const waiting=stopped.then(()=>{complete=true});
  await new Promise(resolve=>setImmediate(resolve));assert.equal(complete,false);
  acknowledge();await waiting;assert.equal(complete,true);
});

test('speed clamps and delayed frames never create a large jump', async () => {
  const f=fixture();f.scroll.set({enabled:true,speed:1000});await f.step(0);await f.step(30000);
  assert.deepEqual(f.moves,[12]);
  f.scroll.set({enabled:true,speed:-4});for(let n=0;n<4;n++)await f.step(100);
  assert.deepEqual(f.moves,[12,1]);
  f.scroll.set({enabled:true,speed:NaN});await f.step(100);
  assert.equal(f.moves.at(-1),3);
  f.scroll.stop();
});

test('unsupported layouts and existing selections do not begin a session', () => {
  const f=fixture();f.renderer.autoScrollSupported=false;
  assert.equal(f.scroll.set({enabled:true}),false);
  f.renderer.autoScrollSupported=true;f.allowed=false;
  assert.equal(f.scroll.set({enabled:true}),false);
  f.allowed=true;f.doc.getSelection=()=> 'selected';
  assert.equal(f.scroll.set({enabled:true}),false);
  assert.deepEqual(f.stopped,[]);assert.equal(f.pending.size,0);
});

for(const type of ['wheel','keydown','selectionchange'])
  test(`${type} stops once without consuming the manual operation`, () => {
    const f=fixture(), child=Object.assign(new EventTarget(),{getSelection:()=> 'selected'});
    f.scroll.attach(child);f.scroll.attach(child);f.scroll.set({enabled:true});
    const event=new Event(type,{cancelable:true});child.dispatchEvent(event);child.dispatchEvent(event);
    assert.equal(event.defaultPrevented,false);
    assert.deepEqual(f.stopped,[type==='selectionchange'?'selection':'input']);
    assert.equal(f.pending.size,0);
  });

const send = (doc,type,values={}) => {
  const event=new Event(type,{cancelable:true});Object.assign(event,values);doc.dispatchEvent(event);return event;
};
test('a tap or small finger jitter keeps scrolling so the host can reveal the floating bar',async()=>{
  const f=fixture();f.scroll.set({enabled:true});await f.step(0);
  send(f.doc,'pointerdown',{button:0,pointerId:1,clientX:10,clientY:10});
  send(f.doc,'pointermove',{pointerId:1,clientX:13,clientY:12});
  send(f.doc,'pointerup',{pointerId:1,clientX:13,clientY:12});
  send(f.doc,'touchstart',{touches:[{clientX:10,clientY:10}]});
  send(f.doc,'touchmove',{touches:[{clientX:13,clientY:12}]});
  send(f.doc,'touchend',{touches:[]});
  await f.step();assert.deepEqual(f.stopped,[]);assert.deepEqual(f.moves,[3]);f.scroll.stop();
});

for(const pointer of [true,false])test(`${pointer?'mouse':'touch'} dragging pauses without consuming the gesture`,()=>{
  const f=fixture();f.scroll.set({enabled:true});
  if(pointer)send(f.doc,'pointerdown',{button:0,pointerId:1,clientX:10,clientY:10});
  else send(f.doc,'touchstart',{touches:[{clientX:10,clientY:10}]});
  const event=pointer?send(f.doc,'pointermove',{pointerId:1,clientX:10,clientY:30}):
    send(f.doc,'touchmove',{touches:[{clientX:10,clientY:30}]});
  assert.equal(event.defaultPrevented,false);assert.deepEqual(f.stopped,['input']);assert.equal(f.pending.size,0);
});

test('normal pace measures Chinese characters and English words, including mixed pages',()=>{
  assert.equal(autoScrollPixelsPerSecond([{text:'字'.repeat(300),height:600}]),10);
  assert.equal(autoScrollPixelsPerSecond([{text:'word '.repeat(200),height:600}]),10);
  assert.equal(autoScrollPixelsPerSecond([{text:'字'.repeat(150),height:300},{text:'word '.repeat(100),height:300}]),10);
  assert.equal(autoScrollPixelsPerSecond([{text:"don't state-of-the-art ".repeat(100),height:600}]),10);
  assert.equal(autoScrollPixelsPerSecond([{text:'图',height:600}],7),7);
  assert.equal(autoScrollPixelsPerSecond([{text:'',height:600}],7),7);
});

test('layout pace is cached, refreshed after layout change, and multiplier only changes distance',async()=>{
  const f=fixture();let measured=0,base=10;
  f.renderer.getAutoScrollSpeed=()=>{measured++;return base};
  f.scroll.set({enabled:true});await f.step(0);await f.step();
  assert.deepEqual(f.moves,[1]);assert.equal(measured,1);
  f.scroll.set({enabled:true,speed:2});await f.step();
  assert.deepEqual(f.moves,[1,2]);assert.equal(measured,1);
  base=20;f.scroll.refresh();await f.step();
  assert.deepEqual(f.moves,[1,2,4]);assert.equal(measured,2);
  f.renderer.getAutoScrollSpeed=()=>{throw Error('layout pending')};f.scroll.refresh();await f.step();
  assert.equal(f.moves.at(-1),4);assert.equal(f.scroll.running,true);f.scroll.stop();
});

test('hidden documents, inactive readers, layout changes and replacement renderers stop', async () => {
  for (const change of [
    f=>{f.doc.visibilityState='hidden';f.doc.dispatchEvent(new Event('visibilitychange'))},
    f=>f.host.dispatchEvent(new Event('pagehide')),
    f=>{f.renderer.readerActive=false}, f=>{f.renderer.autoScrollSupported=false},
    f=>{f.renderer.isNavigating=true}, f=>{f.renderer={...f.renderer}},
  ]) {
    const f=fixture();f.scroll.set({enabled:true});await f.step(0);change(f);await f.step();
    assert.equal(f.scroll.running,false);assert.deepEqual(f.stopped,['inactive']);assert.deepEqual(f.moves,[]);
  }
});

test('chapter end and failures stop with one final position flush', async () => {
  for(const result of ['end', 'error']) {
    const f=fixture();f.renderer.autoScrollBy=async()=>{if(result==='error')throw Error('failed');return result};
    f.scroll.set({enabled:true});await f.step(0);await f.step();
    assert.equal(f.scroll.running,false);assert.deepEqual(f.stopped,[result]);
    assert.equal(f.flushed.length,1);assert.equal(f.pending.size,0);
  }
});

test('stopping while a chapter loads cannot move later or interfere with a restarted session', async () => {
  const f=fixture();let release;const gate=new Promise(resolve=>release=resolve);
  const advance=f.renderer.autoScrollBy;
  f.renderer.autoScrollBy=async(distance,active)=>{await gate;return advance(distance,active)};
  f.scroll.set({enabled:true});await f.step(0);await f.step();
  assert.equal(f.pending.size,0,'one in-flight step at most');
  f.scroll.stop('navigation');
  f.renderer.autoScrollBy=advance;f.scroll.set({enabled:true,speed:2});await f.step(0);
  release();await new Promise(resolve=>setImmediate(resolve));
  assert.deepEqual(f.moves,[]);assert.equal(f.scroll.running,true);assert.equal(f.pending.size,1);
  await f.step();assert.deepEqual(f.moves,[6]);assert.deepEqual(f.stopped,['navigation']);f.scroll.stop();
});

function paginatorFixture(quantum = 1, lines = []) {
  const methods=paginator.slice(paginator.indexOf('  get autoScrollSupported() {'),paginator.indexOf('  snap(vx, vy, touchState) {'));
  const reader = runInNewContext(`new (class {
    #vertical=false; #destroyed=false; #view={}; #locked=false; #preparingView=false;
    #continuous=null; #container; #autoScrolling=false; #fractionalAutoScroll=null; #fractionalAutoScrollDpr=null;
    #needsLineSettle=true; #lineSettleTimer; #scrollRelocateTimer;
    #justAnchored=false;
    #margin=0;#getVisibleRange(){return {toString:()=> '字'.repeat(300)}}
    scrolled=true;viewSize=2000;size=600;reported=[];
    quantum=1;position=0;writes=0;scrollPageStep=480;
    constructor(){const self=this;this.#container={clientHeight:600,scrollHeight:2000,
      get scrollTop(){return self.position},set scrollTop(v){self.writes++;self.position=Math.round(Math.max(0,Math.min(1400,v))/self.quantum)*self.quantum}}}
    get start(){return this.#container.scrollTop}
    align=true;getAttribute(name){return name==='scroll-auto-align'?String(this.align):null}
    #afterScroll(...args){this.reported.push(args)}
    get top(){return this.#container.scrollTop}
    set vertical(value){this.#vertical=value}
    set continuous(value){this.#continuous=value}
    ${methods}
  })`,{clearTimeout(){},autoScrollPixelsPerSecond,prepareScrollLines:doc=>doc?.lines??lines});
  reader.quantum = quantum;
  return reader;
}

test('ordinary scrolling advances exact pixels, stops at this chapter and has explicit reading actions', async () => {
  const reader=paginatorFixture();assert.equal(reader.autoScrollSupported,true);
  assert.equal(reader.getAutoScrollSpeed(),10);
  reader.setAutoScrolling(true);
  assert.equal(await reader.autoScrollBy(7),7);assert.equal(reader.top,7);
  assert.equal(await reader.autoScrollBy(9000),1393);assert.equal(reader.top,1400);
  assert.equal(await reader.autoScrollBy(3),'end');assert.equal(reader.top,1400);
  reader.flushAutoScrollPosition();assert.deepEqual([...reader.reported[0]],['auto-scroll',true]);
  assert.equal(new ReadingActionGate(()=>100000).isAction('auto-scroll'),true);
  reader.scrolled=false;assert.equal(reader.autoScrollSupported,false);
  reader.scrolled=true;reader.vertical=true;assert.equal(reader.autoScrollSupported,false);
});

test('continuous chapters use their bounded scrolling window and preserve cancellation', async () => {
  const reader=paginatorFixture(),calls=[],active=()=>true;
  reader.continuous={autoScrollBy:async(...args)=>{calls.push(args);return 'moved'}};
  assert.equal(await reader.autoScrollBy(8,active),'moved');
  assert.equal(calls[0][0],8);assert.equal(calls[0][1],active);
  assert.equal(await reader.autoScrollBy(8,()=>false),'inactive');assert.equal(calls.length,1);
});

for(const quantum of [.5,1/3])test(`fractional ${quantum}-pixel quantization retains the intended average speed`,async()=>{
  const f=fixture();let position=0,zero=0;
  f.renderer.getAutoScrollSpeed=()=>10;
  f.renderer.supportsFractionalAutoScroll=()=>true;
  f.renderer.autoScrollBy=async(distance)=>{const before=position;position=Math.round((position+distance)/quantum)*quantum;
    if(position===before)zero++;return position-before};
  f.scroll.set({enabled:true,speed:.1});await f.step(0);
  for(let i=0;i<600;i++)await f.step(1000/60);
  assert.ok(Math.abs(position-10)<=quantum/2+1e-8,`${position} instead of 10`);
  assert.ok(zero>0);assert.equal(f.scroll.running,true,'unmoved fractional requests are not book ends');
  f.scroll.stop();
});

test('fractional capability is probed once, restores scrollTop and keeps integer WebViews safe',async()=>{
  for(const [quantum,expected] of [[1,false],[.5,true],[1/3,true]]){
    const reader=paginatorFixture(quantum);
    assert.equal(reader.supportsFractionalAutoScroll(),expected);
    assert.equal(reader.top,0);
    const writes=reader.writes;
    assert.equal(reader.supportsFractionalAutoScroll(),expected);assert.equal(reader.writes,writes);
    assert.equal(await reader.autoScrollBy(.01),0,'rounding to zero does not mean end');
  }
});

test('partially consumed motion remains available on the next frame',async()=>{
  const f=fixture(),requested=[];let first=true,total=0;
  f.renderer.autoScrollBy=async(distance)=>{requested.push(distance);const actual=first?2:distance;first=false;total+=actual;return actual};
  f.scroll.set({enabled:true});await f.step(0);await f.step();await f.step();
  assert.deepEqual(requested,[3,4]);assert.equal(total,6);f.scroll.stop();
});

test('e-ink waits between whole-screen steps without scheduling animation frames',async()=>{
  const f=fixture();f.scroll.set({enabled:true,eInkMode:true,session:7});
  assert.equal(f.pending.size,0);assert.equal(f.timers.size,1);
  assert.equal([...f.timers.values()][0].delay,2000);
  await f.step(1999);assert.deepEqual(f.moves,[]);
  await f.step(1);assert.deepEqual(f.moves,[60]);assert.deepEqual(f.flushed,[60]);
  f.scroll.set({enabled:true,eInkMode:true,speed:2,session:7});
  assert.equal([...f.timers.values()][0].delay,1000);assert.equal(f.timers.size,1);
  const late=[...f.timers.values()][0].fn;
  send(f.doc,'wheel');assert.equal(f.timers.size,0);
  await late();assert.deepEqual(f.moves,[60]);assert.deepEqual(f.stoppedSessions,[{reason:'input',session:7}]);
});

test('e-ink mode updates cannot overlap a pending chapter load',async()=>{
  const f=fixture();let release;const gate=new Promise(resolve=>release=resolve),advance=f.renderer.autoScrollBy;
  f.renderer.autoScrollBy=async(distance,active)=>{await gate;return advance(distance,active)};
  f.scroll.set({enabled:true,eInkMode:true});
  const timer=[...f.timers.values()][0];f.timers.clear();const moving=timer.fn();
  await Promise.resolve();f.scroll.set({enabled:true,eInkMode:true,speed:4});
  assert.equal(f.timers.size,0);
  f.scroll.stop();release();await moving;
  assert.deepEqual(f.moves,[]);assert.equal(f.timers.size,0);assert.equal(f.pending.size,0);
});

test('late e-ink and animation callbacks cannot orphan a replacement session scheduler',async()=>{
  for(const eInkMode of [true,false]){
    const f=fixture();f.scroll.set({enabled:true,eInkMode,session:1});
    const late=eInkMode?[...f.timers.values()][0].fn:[...f.pending.values()][0];
    f.scroll.stop();f.scroll.set({enabled:true,eInkMode,session:2});
    await late(0);f.scroll.stop();
    assert.equal(f.timers.size,0);assert.equal(f.pending.size,0);assert.deepEqual(f.moves,[]);
  }
});

test('screen steps preserve a real complete line only while automatic alignment is enabled',()=>{
  const lines=Array.from({length:60},(_,i)=>({top:i*20,bottom:i*20+20}));
  const reader=paginatorFixture(1,lines);
  reader.scrollPageStep=600;assert.equal(reader.getAutoScrollStep(),580);
  assert.equal(reader.scrollPageTarget(0,600),20,'backward step retains the first complete old line');
  for(const percent of [80,93]){
    reader.scrollPageStep=600*percent/100;assert.equal(reader.getAutoScrollStep(),600*percent/100);
  }
  reader.align=false;reader.scrollPageStep=600;assert.equal(reader.getAutoScrollStep(),600);
  reader.align=true;
  reader.continuous={ordered:[{top:0,view:{document:{lines:lines.slice(0,30)}}},
    {top:600,view:{document:{lines:lines.slice(0,30)}}}],top:entry=>entry.top};
  assert.equal(reader.scrollPageTarget(1150,550),1120,'one-line overlap uses the neighboring chapter');
});

test('host tap consumption keeps the original reading action only when not handled',async()=>{
  const book=await readFile(new URL('../assets/foliate-js/src/book.js',import.meta.url),'utf8');
  const chunk=book.slice(book.indexOf('const onClickView ='),book.indexOf('\nconst onExternalLink'));
  for(const response of [true,false,null,'error']) {
    const calls=[];
    const click=runInNewContext(`${chunk};onClickView`,{callFlutter:async(name,data)=>{
      calls.push([name,data.x,data.y]);
      if(name==='onReaderTap'){if(response==='error')throw Error('older host');return response}
    }});
    await click(.2,.3);
    assert.deepEqual(calls,response===true?[['onReaderTap',.2,.3]]:[['onReaderTap',.2,.3],['onClick',.2,.3]]);
  }
});

test('reader bridge enables ordinary scrolling only, leaving PDF and fixed layouts unchanged',async()=>{
  const book=await readFile(new URL('../assets/foliate-js/src/book.js',import.meta.url),'utf8');
  const chunk=book.slice(book.indexOf('const autoScroll ='),book.indexOf('\nconst setStyle ='));
  for(const isPdf of [false,true])for(const isFixedLayout of [false,true])for(const mode of ['scroll','slide']) {
    let config;
    runInNewContext(chunk,{ReaderAutoScroll:class{constructor(options){config=options}},
      isPdf,reader:{view:{isFixedLayout}},style:{pageTurnStyle:mode},
      window:{isFootNoteOpen:()=>false},callFlutter:()=>Promise.resolve()});
    assert.equal(config.canRun(),!isPdf&&!isFixedLayout&&mode==='scroll');
  }
});
