import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source = await readFile(new URL('../assets/foliate-js/src/continuous-section-window.js', import.meta.url), 'utf8');
const {ContinuousSectionWindow} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const pause = () => new Promise(r => setTimeout(r, 160));

function fixture() {
  const nodes = [], loaded = [], unloaded = [], activated = [];
  let scroll = 0, fail = -1, releases;
  const container = {style:{}, clientHeight:600, getBoundingClientRect:()=>({top:0}),
    ownerDocument:{createElement:()=>element(null)}, append:e=>nodes.push(e),
    get scrollHeight(){return ordered().reduce((h,e)=>h+height(e),0)},
    get scrollTop(){return scroll},set scrollTop(v){scroll=Math.max(0,Math.min(v,this.scrollHeight-this.clientHeight))}};
  const height = e => e.style.display === 'none' || e.style.position === 'absolute' ? 0 : e.index == null ? parseFloat(e.style.height)||0 : 120;
  const ordered = () => nodes.filter(e=>!e.removed).sort((a,b)=>(Number(a.style.order)||0)-(Number(b.style.order)||0));
  function element(index) {return {index,style:{},removed:false,remove(){this.removed=true},
    getBoundingClientRect(){let y=0;for(const e of ordered()){if(e===this)break;y+=height(e)}return {top:y-scroll,height:height(this)}}};}
  const sections=Array.from({length:40},(_,index)=>({size:100,
    async load(){loaded.push(index);if(index===fail)throw Error('fixture load failed');return `blob:${index}`},
    unload(){unloaded.push(index)}}));
  sections[4].linear='no';
  const window=new ContinuousSectionWindow({container,sections,
    async create(index){if(releases)await releases;const el=element(index);el.style.position='absolute';container.append(el);
      return {element:el,document:{getSelection:()=>null},destroy(){this.destroyed=true}}},
    activate:e=>activated.push(e.index)});
  const go=index=>window.goTo(index,0,false,()=>{container.scrollTop=window.top(window.current)});
  return {window,container,loaded,unloaded,activated,go,setFail:i=>fail=i,
    block:promise=>releases=promise};
}
test('short chapters warm a bounded contiguous window, preserve anchor, then stop',async()=>{
  const f=fixture();try {
    await f.go(2);await pause();
    assert.equal(f.window.current.index,2);
    assert.equal(f.container.scrollTop,240);
    assert.equal(f.window.entries.size,9);
    assert.deepEqual(f.window.ordered.map(e=>e.index),[0,1,2,3,5,6,7,8,9]);
    assert.deepEqual(f.activated,[2],'prefetch cannot activate reading, translation or speech');
    const count=f.loaded.length;await pause();assert.equal(f.loaded.length,count);
  }finally{f.window.destroy()}
  assert.equal(f.loaded.length,f.unloaded.length);
});
test('scroll window advances and reverses without gaps or losing the active anchor',async()=>{
  const f=fixture();try {
    await f.go(2);await pause();
    for(const direction of [1,1,1,-1,-1,-1]){
      f.container.scrollTop+=direction*300;f.window.track();
      const active=f.window.current.index;const y=f.window.top(f.window.current)-f.container.scrollTop;
      await pause();assert.equal(f.window.current.index,active);
      assert.equal(f.window.top(f.window.current)-f.container.scrollTop,y);
      const list=f.window.ordered;assert.ok(list.length<=9);
      for(let n=1;n<list.length;n++)assert.equal(f.window.adjacent(list[n-1].index,1),list[n].index);
    }
  }finally{f.window.destroy()}
});
test('distant jumps retain but hide the speaking document; it can be restored without reload',async()=>{
  const f=fixture();try {
    await f.go(2);await pause();const voice=f.window.current;f.window.pinned=2;
    await f.go(25);assert.equal(voice.detached,true);assert.equal(voice.view.destroyed,undefined);
    f.window.select(voice);assert.equal(voice.detached,false);assert.equal(f.window.current,voice);
    assert.equal(f.loaded.filter(i=>i===2).length,1);
  }finally{f.window.destroy()}
});
test('equal-distance neighbors cannot evict each other in an idle warm loop',async()=>{
  const f=fixture();try {
    await f.go(5);await pause();
    const count=f.loaded.length;
    for(let i=0;i<4;i++){f.window.track();await pause()}
    assert.equal(f.loaded.length,count);
  }finally{f.window.destroy()}
});
test('foreground load failure retains the readable chapter and allows a retry',async()=>{
  const f=fixture();try {
    await f.go(2);f.setFail(25);await assert.rejects(f.go(25),/load failed/);
    assert.equal(f.window.current.index,2);assert.equal(f.window.busy,false);
    f.setFail(-1);await f.go(25);assert.equal(f.window.current.index,25);
  }finally{f.window.destroy()}
});
test('closing during preparation releases late resources and cannot revive documents',async()=>{
  const f=fixture();let release;f.block(new Promise(r=>release=r));const pending=f.go(2);
  await new Promise(r=>setImmediate(r));f.window.destroy();release();await pending;
  assert.equal(f.window.current,null);assert.equal(f.window.entries.size,0);
  assert.deepEqual(f.unloaded,[2]);assert.deepEqual(f.activated,[]);
});

test('continuous TTS pins its chapter rather than reinitializing from the viewport',async()=>{
  const code=await readFile(new URL('../assets/foliate-js/src/tts-navigation.js',import.meta.url),'utf8');
  const {TtsNavigator}=await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
  let visual=0, cursor=0;const docs=[{},{},{}];const calls=[];
  const view={book:{sections:[{},{},{}]},renderer:{continuous:true,
    getContents:()=>[{index:visual,doc:docs[visual]}],goTo:async({index})=>{visual=index},pinTtsSection(){}},
    initTTS(_,{force=false}={}){if(this.tts&&!force)return;const index=visual;cursor=-1;
      this.tts={doc:docs[index],sectionIndex:index,start:()=>{cursor=0;return `title ${index}`},
        next:()=>++cursor===1?`body ${index}`:'',prev:()=>'',end:()=>`body ${index}`};calls.push(index)}};
  const nav=new TtsNavigator(()=>view);
  assert.equal(await nav.start(),'title 0');visual=2;
  assert.equal(await nav.move(1),'body 0');assert.deepEqual(calls,[0]);
  assert.equal(await nav.move(1),'title 1');assert.deepEqual(calls,[0,1]);
  assert.equal(await nav.move(1),'body 1');
  assert.equal(await nav.move(1),'title 2');
  assert.equal(await nav.move(1),'body 2');assert.equal(await nav.move(1),'');
});
