import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {runInNewContext} from 'node:vm';

const read = name => readFile(new URL(`../assets/foliate-js/src/${name}.js`,import.meta.url),'utf8');
const importSource = async name => import(`data:text/javascript;base64,${Buffer.from(await read(name)).toString('base64')}`);
const {search,searchMatcher}=await importSource('search');
const {SearchHighlighter}=await importSource('search-highlighter');
const {JSDOM}=createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const walkerSource=await read('text-walker');
const cfiSource=await read('epubcfi');
const rangeText=(strs,r)=>r.startIndex===r.endIndex
  ?strs[r.startIndex].slice(r.startOffset,r.endOffset)
  :strs[r.startIndex].slice(r.startOffset)+strs.slice(r.startIndex+1,r.endIndex).join('')+strs[r.endIndex].slice(0,r.endOffset);

for(const sensitivity of ['base','accent','case','variant']) {
  test(`exact original offsets, node boundaries and overlapping matches (${sensitivity})`,()=>{
    for(const [strs,query,count] of [
      [['革命'],'革命',1], [['','革','','命',''],'革命',1],
      [['革命','革命'],'革命',2], [['革','命革','命'],'革命',2],
      [['革','命','革'],'革命革',1], [['aa','aa'],'aaa',2],
      [['革命','革命'],'革命革命',1], [['abc',''], 'bc',1],
      [[], '革命',0], [[''], '革命',0], [['a'],'',0],
      [['[','.*]'],'[.*]',1], [['😀','革命😀'],'革命',1],
    ]) {
      const hits=[...search(strs,query,{sensitivity,granularity:'grapheme'})];
      assert.equal(hits.length,count,JSON.stringify({strs,query}));
      for(const hit of hits) {
        assert.equal(rangeText(strs,hit.range),query);
        assert.equal(hit.excerpt.match,query);
      }
    }
  });
}

test('case folding does not shift later offsets; original diacritics/whitespace preserved',()=>{
  for(const sensitivity of ['base','accent']) {
    const strs=['İ BEFORE ','Revo','lution'];
    const [hit]=search(strs,'revolution',{sensitivity,granularity:'grapheme'});
    assert.equal(rangeText(strs,hit.range),'Revolution');
  }
  for(const [strs,query,expected] of [
    [['ca','fe','\u0301'],'cafe','cafe\u0301'],
    [['革  ','\n命'],'革 命','革  \n命'],
    [['革命  \n'],'革命 ', '革命  \n'],
    [['革\u200b','命'],'革命','革\u200b命'],
  ]) {
    const [hit]=search(strs,query,{sensitivity:'base',granularity:'grapheme'});
    assert.ok(hit,JSON.stringify({strs,query}));
    assert.equal(rangeText(strs,hit.range),expected);
    assert.equal(hit.excerpt.match,expected);
  }
});

test('whole word search works across inline nodes but excludes partial words',()=>{
  const hits=[...search(['revo','lution revolutionary re','volution'],'revolution',
    {granularity:'word',sensitivity:'base'})];
  assert.equal(hits.length,2);
  assert.ok(hits.every(hit=>hit.excerpt.match==='revolution'));
});

test('default search includes substrings and handles every split of repeated Chinese text',()=>{
  assert.equal([...search(['revolutionary'],'revolution')].length,1);
  const text='甲革命革命乙革命';
  for(let i=0;i<=text.length;i++) for(let j=i;j<=text.length;j++) {
    const strs=[text.slice(0,i),'',text.slice(i,j),'',text.slice(j)];
    const hits=[...search(strs,'革命')];
    assert.equal(hits.length,3);
    for(const hit of hits)assert.equal(rangeText(strs,hit.range),'革命');
  }
});

test('search DOM ranges and restored CFIs select only 革命, including nested inline tags',()=>{
  const dom=new JSDOM('<body><p>第一处革命，第二处<b>革<i>命</i></b>。</p><p>革命</p><p>末尾革命</p></body>');
  const {document,NodeFilter,Range}=dom.window;
  const textWalker=runInNewContext(walkerSource.replace('export const textWalker','const textWalker')+'\ntextWalker', {document,NodeFilter});
  const CFI=runInNewContext(cfiSource.replaceAll('export ','')+'\n({fromRange,toRange,parse})',{document,NodeFilter,Range});
  const matcher=searchMatcher(textWalker,{defaultLocale:'zh'});
  const clone=new JSDOM(document.documentElement.outerHTML);
  clone.window.document.head.append(clone.window.document.createElement('style'));
  const hits=[...matcher(document,'革命')];
  assert.equal(hits.length,4);
  for(const {range,excerpt} of hits) {
    assert.equal(range.toString(),'革命');
    assert.equal(excerpt.match,'革命');
    const cfi=CFI.fromRange(range);
    assert.equal(CFI.toRange(clone.window.document,CFI.parse(cfi)).toString(),'革命');
  }
  dom.window.close(); clone.window.close();
});

test('native highlights use real ranges without changing text, CFI nodes, or selection',()=>{
  const dom=new JSDOM('<body><p>革命与革命</p></body>',{pretendToBeVisual:true});
  const doc=dom.window.document, text=doc.querySelector('p').firstChild;
  dom.window.CSS={highlights:new Map()};
  dom.window.Highlight=class extends Set {};
  const first=doc.createRange();first.setStart(text,0);first.setEnd(text,2);
  const second=doc.createRange();second.setStart(text,3);second.setEnd(text,5);
  const manual=doc.createRange();manual.setStart(text,2);manual.setEnd(text,3);
  doc.getSelection().addRange(manual);
  const original=doc.body.innerHTML;
  const paint=new SearchHighlighter(doc);
  paint.add('one',first);paint.add('two',second);
  const registry=dom.window.CSS.highlights;
  assert.deepEqual([...registry.get('modu-search-match')].map(r=>r.toString()),['革命','革命']);
  assert.equal(doc.getSelection().toString(),'与');
  assert.equal(doc.body.innerHTML,original);
  assert.equal(doc.querySelector('p').firstChild,text);
  assert.equal(doc.querySelector('svg'),null);
  assert.match(doc.head.textContent,/::highlight\(modu-search-match\)/);
  assert.doesNotMatch(doc.head.textContent,/border|font-size|padding|stroke/);
  paint.remove('one');assert.equal(registry.get('modu-search-match').size,1);
  // Keep unrelated highlights (e.g. another document feature) intact.
  registry.set('unrelated',new Set());
  paint.clear();assert.equal(registry.has('modu-search-match'),false);
  assert.equal(registry.has('unrelated'),true);
  assert.equal(doc.head.querySelector('style'),null);
  assert.equal(doc.getSelection().toString(),'与');
  paint.add('again',first);assert.equal(registry.get('modu-search-match').size,1);
  paint.clear();dom.window.close();
});

test('fallback paints clipped text fragments without outer boxes and removes all artifacts',()=>{
  const dom=new JSDOM('<body><p>甲革<b>命乙</b></p></body>',{pretendToBeVisual:true});
  const doc=dom.window.document;
  const nodes=[doc.querySelector('p').firstChild,doc.querySelector('b').firstChild];
  const range=doc.createRange();range.setStart(nodes[0],1);range.setEnd(nodes[1],1);
  const pieces=[];
  dom.window.Range.prototype.getClientRects=function(){
    pieces.push(this.toString());
    return [{left:100+this.startOffset*20,top:80,width:20,height:30}];
  };
  const before=doc.body.innerHTML;
  const paint=new SearchHighlighter(doc);paint.add('cross',range);
  const svg=doc.querySelector('[data-modu-search-overlay]');
  svg.getBoundingClientRect=()=>({left:100,top:50,width:400,height:800});
  paint.redraw();
  assert.deepEqual(pieces,['革','命']);
  assert.equal(svg.children.length,2);
  assert.equal(svg.firstChild.getAttribute('x'),'20');
  assert.equal(svg.firstChild.getAttribute('y'),'30');
  for(const rect of svg.children) {
    assert.equal(rect.getAttribute('width'),'20');
    assert.equal(rect.getAttribute('stroke'),null);
  }
  assert.equal(doc.body.innerHTML,before);
  paint.clear();assert.equal(doc.querySelector('svg'),null);
  dom.window.close();
});
