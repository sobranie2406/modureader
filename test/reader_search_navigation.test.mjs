import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';
import {createRequire} from 'node:module';

const book=await readFile(new URL('../assets/foliate-js/src/book.js',import.meta.url),'utf8');
const view=await readFile(new URL('../assets/foliate-js/src/view.js',import.meta.url),'utf8');
const bridge=book.slice(book.indexOf('let searchGeneration ='),book.indexOf('\nwindow.back ='));
const deferred=()=>{let resolve;const promise=new Promise(r=>resolve=r);return {promise,resolve};};

test('closing search suppresses late progress/results',async()=>{
  const gate=deferred(), events=[];
  const reader={view:{clearSearch(){},async *search(){await gate.promise;yield {progress:.5};yield {subitems:[{}]};yield 'done';}}};
  const window={};
  runInNewContext(bridge,{window,reader,callFlutter:(...args)=>events.push(args)});
  const pending=window.search('word',{requestId:1});
  window.clearSearch();gate.resolve();await pending;
  assert.equal(events.length,0);
});

test('new query wins and all result/progress messages carry its request ID',async()=>{
  const gate=deferred(), events=[];
  const reader={view:{clearSearch(){},async *search({query}){
    if(query==='old')await gate.promise;
    yield {subitems:[{cfi:query}]};yield 'done';
  }}};
  const window={};runInNewContext(bridge,{window,reader,callFlutter:(name,data)=>events.push(data)});
  const pending=window.search('old',{requestId:1});
  await window.search('new',{requestId:2});gate.resolve();await pending;
  assert.equal(events.length,2);assert.ok(events.every(x=>x.requestId===2));
  assert.equal(events[0].subitems[0].cfi,'new');assert.equal(events[1].process,1);
});

test('search result and origin navigation do not push extra history entries',async()=>{
  const calls=[];const reader={view:{goTo:async(...args)=>{calls.push(args);return {index:1};}}};
  const window={};
  runInNewContext(book.match(/^window\.goToSearchResult = .*$/m)[0],{window,reader});
  assert.equal(await window.goToSearchResult('match-9'),true);
  assert.equal(await window.goToSearchResult('origin'),true);
  assert.deepEqual(calls.map(x=>[x[0],x[1].recordHistory]),[['match-9',false],['origin',false]]);
});

test('view cancellation stops a delayed chapter from adding cleared highlights',async()=>{
  const methods=view.slice(view.indexOf('  async * #searchSection('),view.indexOf('\n  oldValue ='))
    .replace("await import('./search.js')",'await searchModule');
  const View=runInNewContext(`(class {
    #searchResults=new Map(); #searchGeneration=0;
    #tocProgress={getProgress:()=>({label:'chapter'})}; language='en';
    added=[]; addAnnotation(item){this.added.push(item);} deleteAnnotation(){}
    getCFI(index,range){return 'hit-'+range;}
    ${methods}
  })`,{console:{log(){}},SEARCH_PREFIX:'foliate-search:',textWalker:null,
    searchModule:Promise.resolve({searchMatcher:()=>function*(doc){yield {range:doc.id,excerpt:{match:'word'}};}})});
  const gate=deferred();const v=new View();
  v.book={sections:[{createDocument:async()=>{await gate.promise;return {id:1};}}]};
  const search=v.search({query:'word'});
  const pending=search.next();await new Promise(r=>setTimeout(r,0));
  v.clearSearch();gate.resolve();
  assert.equal((await pending).done,true);assert.equal(v.added.length,0);
  const next=[];for await(const result of v.search({query:'word'}))next.push(result);
  assert.equal(v.added.length,1);assert.equal(next.at(-1),'done');
  assert.ok(view.includes('overlayer.addSearch(value, range)'));
});

test('Dart bridge encodes quotes/newlines and validates request IDs',async()=>{
  const dart=await readFile(new URL('../lib/page/book_player/epub_player.dart',import.meta.url),'utf8');
  assert.ok(dart.includes('search(${jsonEncode(sanitized)}, {'));
  assert.ok(dart.includes("search['requestId'] != state.requestId"));
  assert.ok(dart.includes('await pending;'));
  assert.ok(dart.includes('await _goToSearchCfi(origin!)'));
});

test('search arrivals and completion of older navigation never auto-select a result',async()=>{
  const dart=await readFile(new URL('../lib/page/book_player/epub_player.dart',import.meta.url),'utf8');
  const handler=dart.slice(dart.indexOf("handlerName: 'onSearch'"),
    dart.indexOf("handlerName: 'renderAnnotations'"));
  assert.ok(handler.includes('tocSearch.addResult(SearchResultModel.fromJson(search))'));
  assert.doesNotMatch(handler,/navigateSearch|_goToSearchCfi|selectMatch|goToCfi/);
  const navigation=dart.slice(dart.indexOf('Future<void> navigateSearch('),
    dart.indexOf('Future<void> _goToSearchCfi('));
  assert.ok(navigation.includes('_goToSearchCfi(target)'));
  assert.doesNotMatch(navigation.slice(navigation.indexOf('finally')),/navigateSearch|_goToSearchCfi|selectMatch/);
});

test('ordinary note/TTS marks retain their existing appearance',async()=>{
  const requireDOM=createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`);
  const {JSDOM}=requireDOM('jsdom');
  const source=await readFile(new URL('../assets/foliate-js/src/overlayer.js',import.meta.url),'utf8');
  for(const background of ['#fffdf4','#121212']) {
    const dom=new JSDOM(`<body style="background:${background};--overlayer-highlight-opacity:.1"></body>`);
    const Overlayer=runInNewContext(source.replace(/^import .*$/gm,'').replace('export class Overlayer','class Overlayer')+'\nOverlayer',
      {document:dom.window.document});
    const rects=[{left:10,top:20,width:90,height:24},{left:0,top:44,width:30,height:24}];
    const note=Overlayer.highlight(rects,{color:'#39c5bc83'});
    assert.equal(note.getAttribute('fill'),'#39c5bc83');
    assert.equal(note.getAttribute('stroke'),null);
    // jsdom's CSS parser drops var() opacity; the ordinary annotation path
    // must still retain its original theme-controlled opacity in the source.
    assert.ok(source.includes("g.style.opacity = 'var(--overlayer-highlight-opacity, .3)'"));
    assert.notEqual(note.style.opacity,'1');
    dom.window.close();
  }
});
