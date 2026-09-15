import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';

const source=await readFile(new URL('../assets/foliate-js/src/view.js',import.meta.url),'utf8');
const History=runInNewContext(`${source.slice(source.indexOf('class History '),source.indexOf('\nconst languageInfo'))};History`,
  {EventTarget,Event,CustomEvent});
const methods=source.slice(source.indexOf('  #recordNavigation('),source.indexOf('\n  deselect()'));
const init=source.slice(source.indexOf('  async init('),source.indexOf('\n  #emit('));
const View=runInNewContext(`(class {
  history=new History(); lastLocation; fail=false;
  #sectionProgress={getSection:f=>[0,f]};
  renderer={goTo:async target=>{if(this.fail)throw Error('fixture');
    this.lastLocation={cfi:target.cfi??'fraction-'+target.anchor};}};
  resolveNavigation(target){return target==null?null:{cfi:target};}
  ${methods}
  ${init}
})`,{History,console:{error(){}}});
const flags=h=>[h.canGoBack,h.canGoForward];

test('opening and repeated automatic restoration seed one position, not a return trail',async()=>{
  const v=new View();await v.init({lastLocation:'start'});
  for(const cfi of ['start','scroll-1','scroll-2']) {
    v.history.replaceState(cfi);v.lastLocation={cfi};
    await v.goTo(cfi,{recordHistory:false});
    assert.deepEqual(flags(v.history),[false,false]);
  }
  await v.goTo('remote-progress',{recordHistory:false});
  assert.deepEqual(flags(v.history),[false,false]);
});
test('deliberate jump retains the exact prior reading position and updates back/forward controls',async()=>{
  const v=new View();await v.init({lastLocation:'start'});
  v.history.replaceState('read-further');v.lastLocation={cfi:'read-further'};
  await v.goTo('footnote');assert.deepEqual(flags(v.history),[true,false]);
  const popped=[],changes=[];
  v.history.addEventListener('popstate',e=>popped.push(e.detail.state));
  v.history.addEventListener('index-change',()=>changes.push(flags(v.history)));
  v.history.back();v.history.forward();
  assert.deepEqual(popped,['read-further','footnote']);
  assert.deepEqual(changes,[[false,true],[true,false]]);
});
test('closing the capsule clears old jumps, stays closed while reading, allows a new deliberate jump',async()=>{
  const v=new View();await v.init({lastLocation:'start'});await v.goTo('note');
  let changed=0;v.history.addEventListener('index-change',()=>changed++);
  v.clearNavigationHistory();assert.equal(changed,1);
  assert.deepEqual(flags(v.history),[false,false]);
  v.history.replaceState('continued');v.lastLocation={cfi:'continued'};
  await v.goTo('sync',{recordHistory:false});assert.deepEqual(flags(v.history),[false,false]);
  await v.goTo('new-note');assert.deepEqual(flags(v.history),[true,false]);
  let target;v.history.addEventListener('popstate',e=>target=e.detail.state);
  v.history.back();assert.equal(target,'sync');
});
test('same position, invalid navigation and failed jumps do not create history',async()=>{
  const v=new View();await v.init({lastLocation:'start'});
  await v.goTo('start');await v.goTo(null);
  v.fail=true;await v.goTo('broken');
  assert.deepEqual(flags(v.history),[false,false]);
});
test('reinitializing a book discards the previous session trail',async()=>{
  const v=new View();await v.init({lastLocation:'start'});await v.goTo('note');
  await v.init({lastLocation:'reopened'});assert.deepEqual(flags(v.history),[false,false]);
});
test('empty history and zero-percent destinations are handled without duplicate entries',()=>{
  const h=new History();h.replaceState('start');h.pushState('note');h.back();
  assert.deepEqual(flags(h),[false,true]);
  h.clear();h.pushState({fraction:0});h.pushState({fraction:0});
  assert.deepEqual(flags(h),[false,false]);
});
test('layout refresh opts out of history and Flutter listens to clear/back/forward as well as push',async()=>{
  const book=await readFile(new URL('../assets/foliate-js/src/book.js',import.meta.url),'utf8');
  const calls=[];
  const refresh=book.slice(book.indexOf('const refreshLayout ='),book.indexOf('\nconst onRelocated ='));
  runInNewContext(`${refresh};refreshLayout()`,{reader:{view:{lastLocation:{cfi:'current'},
    goTo:(cfi,options)=>calls.push([cfi,options.recordHistory])}}});
  assert.deepEqual(calls,[['current',false]]);
  assert.match(book,/view\.history\.addEventListener\('index-change'/);
  assert.match(book,/window\.clearNavigationHistory = \(\) => reader\.view\.clearNavigationHistory\(\)/);
  const dart=await readFile(new URL('../lib/page/book_player/epub_player.dart',import.meta.url),'utf8');
  assert.match(dart,/l10n\.historyClose,\s+closeHistory,/);
  assert.match(dart,/evaluateJavascript\(source: 'clearNavigationHistory\(\)'\)/);
});
