import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { runInNewContext } from 'node:vm';
const { JSDOM } = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/text-page-layout.js', import.meta.url), 'utf8');
const { pageLineOffsets, preparePageRuns, alignPaginatedText, resetPageAlignment, fitTextLineSpacing, fittedLineHeight, safeScrollOffset, settledScrollOffset, lineAlignedOffset, prepareScrollLines, invalidateScrollLines } =
  await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const cfiSource = await readFile(new URL('../assets/foliate-js/src/epubcfi.js', import.meta.url), 'utf8');
const CFI = await import(`data:text/javascript;base64,${Buffer.from(cfiSource).toString('base64')}`);

test('full pages align both edges; final page keeps natural gaps', () => {
  for (const count of [10, 15, 25]) {
    const rows = Array.from({length:count}, (_,i)=>({top:25+i*40,bottom:49+i*40}));
    const bottom=rows.at(-1).bottom+12, offsets=pageLineOffsets(rows,20,bottom,false);
    assert.equal(rows[0].top+offsets[0],20);
    assert.equal(rows.at(-1).bottom+offsets.at(-1),bottom);
    assert.ok(offsets.every((x,i)=>!i || x-offsets[i-1]<2));
    assert.deepEqual(pageLineOffsets(rows,20,bottom,true),rows.map(()=>-5));
  }
  assert.equal(pageLineOffsets([{top:20,bottom:40}],20,400,false),null);
});

test('natural two/three-line pages at large sizes also align both edges', () => {
  for (const count of [2, 3]) {
    const rows = Array.from({ length: count }, (_, i) => ({ top: 90 + i * 90, bottom: 140 + i * 90 }));
    const offsets = pageLineOffsets(rows, 60, 330, false);
    assert.ok(offsets, `${count}-line natural page was skipped`);
    assert.equal(rows[0].top + offsets[0], 60);
    assert.equal(rows.at(-1).bottom + offsets.at(-1), 330);
  }
});

test('small line heights remain readable and fit the actual available viewport', () => {
  for (const viewport of [260,493,759,889]) for (const glyph of [19,28,39,56])
    for (const requested of [0,glyph*.8,glyph*1.8]) {
      const fitted=fittedLineHeight(requested,glyph,viewport);
      assert.ok(fitted>=glyph+2);
      const natural=Math.max(requested,glyph+2);
      assert.ok(Math.abs(fitted-natural)<=Math.min(8,natural*.2)+.001);
      if(fitted!==natural)assert.ok(Math.abs((viewport-glyph-1)/fitted-Math.round((viewport-glyph-1)/fitted))<.00001);
    }
});

test('short landscape viewports distribute a spare line and paragraph gap', () => {
  const rows=Array.from({length:5},(_,i)=>({top:89+i*42,bottom:129+i*42}));
  const offsets=pageLineOffsets(rows,80,335,false);
  assert.equal(rows[0].top+offsets[0],80);
  assert.equal(rows.at(-1).bottom+offsets.at(-1),335);
});

test('leading paragraph margin is reclaimed without guessing fullness from whitespace', () => {
  const rows=Array.from({length:5},(_,i)=>({top:146+i*120,bottom:193+i*120}));
  const offsets=pageLineOffsets(rows,50,809,false);
  assert.equal(rows[0].top+offsets[0],50);
  assert.equal(rows.at(-1).bottom+offsets.at(-1),809);
  assert.deepEqual(pageLineOffsets(rows,50,1500,true),rows.map(()=>-96),'chapter ends keep natural spacing');
});

test('a following paragraph margin can legitimately leave more than one line of spare space', () => {
  const rows=Array.from({length:8},(_,i)=>({top:57+i*72,bottom:104+i*72}));
  const offsets=pageLineOffsets(rows,45,770,false);
  assert.equal(rows[0].top+offsets[0],45);
  assert.equal(rows.at(-1).bottom+offsets.at(-1),770);
  const tallLines=Array.from({length:7},(_,i)=>({top:105+i*84,bottom:138+i*84}));
  const fitted=pageLineOffsets(tallLines,80,789,false);
  assert.equal(tallLines[0].top+fitted[0],80);
  assert.equal(tallLines.at(-1).bottom+fitted.at(-1),789,'the bottom half of a CSS line box also consumes space');
});

test('font measurement repairs zero line-height and resets without overwriting settings', () => {
  const dom=new JSDOM('<style>html{--modu-align-pages:1}p{line-height:0!important}</style><p>段中第一行第二行</p>');
  const doc=dom.window.document, p=doc.querySelector('p'), original=p.firstChild;
  dom.window.Range.prototype.getClientRects=()=>[{width:100,height:28,top:-14,bottom:14}];
  fitTextLineSpacing(doc,759);
  assert.ok(parseFloat(p.style.lineHeight)>=30);
  const first=p.style.lineHeight;
  resetPageAlignment(doc);
  assert.equal(p.style.lineHeight,'');
  fitTextLineSpacing(doc,759);
  assert.equal(p.style.lineHeight,first,'repeated preparation must not accumulate adjustments');
  resetPageAlignment(doc);
  doc.documentElement.style.setProperty('--modu-align-pages','0');
  fitTextLineSpacing(doc,759);
  assert.equal(p.style.lineHeight,'','publisher styles are preserved');
  assert.equal(p.firstChild,original);
  dom.window.close();
});

test('overlapping font boxes retain separate lines instead of merging entire paragraphs', () => {
  const dom=new JSDOM('<p>第一行第二行第三行</p>'),doc=dom.window.document;
  const overlapping=Array.from({length:30},(_,i)=>({top:i*24,bottom:i*24+28,width:100,height:28}));
  dom.window.Range.prototype.getClientRects=()=>overlapping;
  assert.equal(prepareScrollLines(doc).length,30);
  dom.window.Range.prototype.getClientRects=()=>[
    {top:0,bottom:40,width:100,height:40}, {top:4,bottom:18,width:30,height:14},
    {top:30,bottom:70,width:100,height:40}, {top:35,bottom:50,width:30,height:15},
  ];
  invalidateScrollLines(doc);
  assert.deepEqual(prepareScrollLines(doc),[{top:0,bottom:40},{top:30,bottom:70}],
    'nested mixed-size fragments must keep bottom edges sorted for binary searches');
  dom.window.close();
});

function fixture({enabled='1', unsafe=false, long=false}={}) {
  const dom=new JSDOM(`<body>${[10,10,2].map((n,i)=>`<p data-page="${i}">${'字'.repeat(n)}</p>`).join('')}${unsafe?'<img>':''}</body>`);
  const doc=dom.window.document;
  doc.documentElement.style.setProperty('--modu-align-pages',enabled);
  if(long)doc.body.textContent='字'.repeat(50001);
  dom.window.Element.prototype.getClientRects=function(){
    if(this.localName==='img')return [{left:10,top:100,bottom:120,width:20,height:20}];
    if(!this.__moduPageRun)return [];
    const i=[...this.parentElement.children].indexOf(this),page=Number(this.parentElement.dataset.page);
    const top=25+i*40+(parseFloat(this.style.top)||0);
    return [{left:page*320+10,top,bottom:top+24,width:20,height:24}];
  };
  return {dom,doc};
}
const layout={height:450,topMargin:20,bottomMargin:20,columnWidth:300,gap:20};
test('new translations clear stale offsets and keep source/translation in the same flow', () => {
  const {doc,dom}=fixture();
  alignPaginatedText(doc,layout,false);
  const {runs}=preparePageRuns(doc);
  assert.notEqual(runs[0].style.top,'0px');
  const translated=doc.createElement('span');
  translated.className='translated-text';translated.textContent='译文';
  translated.getClientRects=()=>translated.style.display==='none'?[]:
    [{left:10,top:420,bottom:445,width:200,height:25}];
  doc.querySelector('p').append(translated);
  for(const height of [450,500]) {
    resetPageAlignment(doc);alignPaginatedText(doc,{...layout,height},false);
    assert.ok(runs.slice(0,10).every(run=>run.style.top==='0px'));
    assert.notEqual(runs[10].style.top,'0px','untranslated pages retain alignment');
  }
  translated.style.display='none';
  resetPageAlignment(doc);alignPaginatedText(doc,layout,false);
  assert.notEqual(runs[0].style.top,'0px','stopping restores original alignment');
  dom.window.close();
});

test('run preparation clones one styled template and preserves text and namespace', () => {
  const {doc, dom} = fixture();
  const original = doc.body.textContent;
  const create = doc.createElementNS.bind(doc);
  let templates = 0;
  doc.createElementNS = (namespace, name) => {
    if (name === 'modu-page-run') templates++;
    return create(namespace, name);
  };
  const {runs} = preparePageRuns(doc);
  assert.equal(templates, 1);
  assert.equal(runs.length, 22);
  assert.equal(doc.body.textContent, original);
  for (const run of runs) {
    assert.equal(run.namespaceURI, 'http://www.w3.org/1999/xhtml');
    assert.equal(run.__moduPageRun, true);
    assert.equal(run.style.display, 'inline');
    assert.equal(run.style.getPropertyPriority('font'), 'important');
    assert.equal(run.style.top, '0px');
  }
  assert.equal(preparePageRuns(doc).runs, runs);
  assert.equal(templates, 1, 'prepared chapters retain their stable nodes');
  dom.window.close();
});

test('alignment timings are content-free and reset does not rewrite unchanged offsets', () => {
  const {doc, dom} = fixture();
  const events = [];
  alignPaginatedText(doc, layout, false, (stage, since) => {
    assert.ok(Number.isFinite(since) && since <= Date.now());
    events.push(stage);
  });
  assert.deepEqual(events, ['layout_runs', 'layout_geometry', 'layout_offsets']);
  resetPageAlignment(doc);
  let writes = 0;
  for (const run of preparePageRuns(doc).runs) {
    const set = run.style.setProperty.bind(run.style);
    run.style.setProperty = (...args) => { writes++; return set(...args); };
  }
  resetPageAlignment(doc);
  assert.equal(writes, 0);
  alignPaginatedText(doc, layout, false);
  assert.ok(writes > 0, 'real alignment changes still apply');
  assert.equal(preparePageRuns(doc).runs[0].getClientRects()[0].top, 20);
  dom.window.close();
});

test('page extent is measured before offset writes and is not cached across reflows', () => {
  const {doc, dom} = fixture();
  const {runs} = preparePageRuns(doc);
  let writes = 0, measurements = 0;
  for (const run of runs) {
    const set = run.style.setProperty.bind(run.style);
    run.style.setProperty = (...args) => { writes++; return set(...args); };
  }
  for (const height of [450, 500]) {
    resetPageAlignment(doc); writes = 0;
    const extent = alignPaginatedText(doc, {...layout, height}, false, undefined, () => {
      assert.equal(writes, 0, 'measurement must share the read-only geometry pass');
      return ++measurements * 1000;
    });
    assert.equal(extent, measurements * 1000);
    assert.ok(writes > 0);
  }
  assert.equal(measurements, 2);
  dom.window.close();
});

test('transformed publisher content retains post-alignment extent measurement', () => {
  for (const selector of ['html', 'body', 'p']) for (const property of ['transform', 'rotate']) {
    const {doc, dom} = fixture();
    doc.querySelector(selector).style.setProperty(property, property === 'transform' ? 'rotate(2deg)' : '2deg');
    let measured = false;
    const extent = alignPaginatedText(doc, layout, false, undefined, () => { measured = true; return 1000; });
    assert.equal(measured, false);
    assert.equal(extent, undefined);
    dom.window.close();
  }
});

test('line fitting batches reader runs without skipping glyphs or reading generated styles', () => {
  const {doc, dom} = fixture();
  const {runs} = preparePageRuns(doc);
  const computed = dom.window.getComputedStyle.bind(dom.window);
  let generatedReads = 0, glyphReads = 0;
  const measured = [];
  dom.window.getComputedStyle = el => {
    if (el.__moduPageRun) generatedReads++;
    return computed(el);
  };
  dom.window.Range.prototype.getClientRects = function() {
    glyphReads++;
    measured.push(this.toString());
    return [{width: 20, height: 28}];
  };
  fitTextLineSpacing(doc, 759);
  assert.equal(generatedReads, 0);
  assert.equal(glyphReads, doc.querySelectorAll('p').length);
  assert.equal(measured.join(''), runs.map(run => run.textContent).join(''));
  for (const p of doc.querySelectorAll('p')) assert.ok(parseFloat(p.style.lineHeight) >= 30);
  dom.window.close();
});

function chapterOpening({bodyLines=6, titleOnly=false}={}) {
  const {doc,dom}=fixture();
  const first=doc.querySelector('p');
  first.textContent='字'.repeat(bodyLines);
  const heading=doc.createElement('h2');
  heading.innerHTML='<span style="border-bottom:1px solid gray">章节标题</span>';
  doc.body.prepend(heading);
  heading.getClientRects=()=>[{left:10,top:80,bottom:150,width:250,height:70}];
  const originalRects=dom.window.Element.prototype.getClientRects;
  dom.window.Element.prototype.getClientRects=function(){
    const rects=originalRects.call(this);
    return this.__moduPageRun && this.parentElement===first
      ? rects.map(r=>({...r,top:r.top+155,bottom:r.bottom+155})) : rects;
  };
  if(titleOnly)doc.querySelectorAll('p').forEach(p=>p.remove());
  return {doc,dom,heading,first};
}

test('chapter opening aligns only prose below fixed titles and preserves anchors, markers and resize',()=>{
  const {doc,dom,heading,first}=chapterOpening();
  const number=doc.createElement('h1');number.textContent='第一章';doc.body.prepend(number);
  number.getClientRects=()=>[{left:10,top:20,bottom:60,width:250,height:40}];
  const originalNumber=number.outerHTML;
  const originalTitle=heading.outerHTML;
  const titleRange=doc.createRange();titleRange.selectNodeContents(heading.firstChild.firstChild);
  const titleCFI=CFI.fromRange(titleRange);
  const textRange=doc.createRange();textRange.selectNodeContents(first.firstChild);
  const proseCFI=CFI.fromRange(textRange),originalText=first.textContent;
  const note=doc.createElement('sup');note.textContent='注';first.append(note);
  note.getBoundingClientRect=()=>({left:10,top:375,bottom:390,width:10,height:15});
  for(const height of [450,500,450]) {
    resetPageAlignment(doc);
    alignPaginatedText(doc,{...layout,height},false);
    const runs=preparePageRuns(doc).runs.filter(r=>r.parentElement===first);
    assert.equal(runs[0].getClientRects()[0].top,180,'title-to-prose gap stays fixed');
    assert.equal(runs.at(-1).getClientRects()[0].bottom,height-20);
    assert.equal(heading.outerHTML,originalTitle);
    assert.equal(number.outerHTML,originalNumber);
    assert.equal(CFI.toRange(doc,CFI.parse(titleCFI)).toString(),'章节标题');
    assert.equal(CFI.toRange(doc,CFI.parse(proseCFI)).toString(),originalText);
    assert.equal(parseFloat(note.style.top),height-20-404,'note follows its last prose line');
  }
  resetPageAlignment(doc);
  assert.equal(note.style.top,'');
  assert.equal(first.querySelector('modu-page-run').style.top,'0px');
  dom.window.close();
});

test('short endings, title-only, explicit breaks, mid-page headings and mixed media keep natural spacing',()=>{
  for(const kind of ['last','title-only','break','middle','image','single-line','multi-column-title']) {
    const {doc,dom,heading,first}=chapterOpening({titleOnly:kind==='title-only',bodyLines:kind==='single-line'?1:6});
    if(kind==='last')doc.querySelectorAll('p').forEach(p=>{if(p!==first)p.remove()});
    if(kind==='break') {
      first.style.breakAfter='column';
      first.getClientRects=()=>[{left:10,top:180,bottom:404,width:250,height:224}];
    }
    if(kind==='middle')heading.getClientRects=()=>[{left:10,top:200,bottom:250,width:250,height:50}];
    if(kind==='image')doc.body.append(doc.createElement('img'));
    if(kind==='multi-column-title')heading.getClientRects=()=>[0,1].map(page=>({left:page*320+10,top:80,bottom:150,width:250,height:70}));
    const title=heading.outerHTML;
    alignPaginatedText(doc,layout,false);
    assert.equal(heading.outerHTML,title,kind);
    assert.ok(preparePageRuns(doc).runs.filter(r=>r.parentElement===first).every(r=>r.style.top==='0px'),kind);
    dom.window.close();
  }
});

test('an illustration opening the next page preserves the preceding text spacing', () => {
  for (const placement of ['opening', 'image-only', 'inline', 'after-text']) {
    const { doc, dom } = fixture();
    const [preceding, following] = doc.querySelectorAll('p');
    preceding.textContent = '字'.repeat(5);
    const image = doc.createElement('img');
    const imageTop = placement === 'after-text' ? 100 : 20;
    const imageHeight = placement === 'inline' ? 24 : 240;
    image.getClientRects = () => [{
      left: 330, top: imageTop, bottom: imageTop + imageHeight, width: 280, height: imageHeight,
    }];
    following.before(image);
    if (placement === 'opening') {
      following.textContent = '字'.repeat(4);
      const getClientRects = dom.window.Element.prototype.getClientRects;
      dom.window.Element.prototype.getClientRects = function () {
        return getClientRects.call(this).map(rect => this.parentElement === following
          ? { ...rect, top: rect.top + 250, bottom: rect.bottom + 250 } : rect);
      };
    }
    if (placement === 'image-only') following.remove();
    alignPaginatedText(doc, layout, false);
    const lines = [...preceding.children].map(run => run.getClientRects()[0]);
    const natural = placement === 'opening' || placement === 'image-only';
    assert.equal(lines[0].top, 20, placement);
    assert.equal(lines[1].top - lines[0].top, natural ? 40 : 96.5, placement);
    assert.equal(lines.at(-1).bottom, natural ? 204 : 430, placement);
    dom.window.close();
  }
});

test('publisher numbered headings keep text, floating border and CFI together', () => {
  const { doc, dom } = fixture();
  const heading = doc.createElement('h4');
  heading.innerHTML = '<span style="float:left;border-right:2px solid gray;margin-left:-2.6em">035</span>带编号的小标题';
  doc.body.prepend(heading);
  const original = heading.innerHTML;
  const text = heading.lastChild;
  const range = doc.createRange();
  range.selectNodeContents(text);
  const cfi = CFI.fromRange(range);
  // A heading split over two columns protects both fragments.
  heading.getClientRects = () => [0, 2].map(page => ({
    left: page * 320 + 10, top: 100, bottom: 150, width: 250, height: 50,
  }));
  for (const height of [450, 500, 450]) {
    resetPageAlignment(doc);
    alignPaginatedText(doc, { ...layout, height }, false);
    assert.equal(heading.innerHTML, original);
    assert.equal(CFI.toRange(doc, CFI.parse(cfi)).toString(), text.textContent);
    assert.equal(doc.querySelector('p modu-page-run').style.top, '0px');
    assert.equal(doc.querySelectorAll('p')[1].lastChild.getClientRects()[0].bottom, height - 20,
      'ordinary pages still align');
    assert.equal(doc.querySelectorAll('p')[2].firstChild.style.top, '0px');
  }
  dom.window.close();
});

test('line-spacing fitting leaves headings and decorated/float paragraphs intact', () => {
  const dom = new JSDOM(`<style>html{--modu-align-pages:1}p,h4{line-height:10px}</style>
    <h4>标题</h4><p id="float"><span style="float:left">编号</span>标题正文</p>
    <p id="border" style="border-left:2px solid gray">边框段落</p><p id="plain">普通正文</p>`);
  const doc = dom.window.document;
  dom.window.Range.prototype.getClientRects = () => [{ width: 100, height: 28 }];
  const before = [...doc.querySelectorAll('h4,#float,#border')].map(el => el.outerHTML);
  fitTextLineSpacing(doc, 759);
  assert.ok(parseFloat(doc.querySelector('#plain').style.lineHeight) >= 30);
  preparePageRuns(doc);
  assert.deepEqual([...doc.querySelectorAll('h4,#float,#border')].map(el => el.outerHTML), before);
  resetPageAlignment(doc);
  assert.equal(doc.querySelector('#plain').style.lineHeight, '');
  dom.window.close();
});

test('new publisher decorations after settings changes protect already prepared runs', () => {
  const { doc, dom } = fixture();
  alignPaginatedText(doc, layout, false);
  resetPageAlignment(doc);
  const p = doc.querySelector('p');
  p.style.borderLeft = '2px solid gray';
  p.getClientRects = () => [{ left: 10, top: 25, bottom: 409, width: 250, height: 384 }];
  alignPaginatedText(doc, layout, false);
  assert.equal(p.lastChild.style.top, '0px');
  assert.equal(doc.querySelectorAll('p')[1].lastChild.getClientRects()[0].bottom, 430);
  dom.window.close();
});

test('explicit break-before and break-after preserve a sparse publisher page', () => {
  for (const kind of ['before', 'after']) {
    const { doc, dom } = fixture();
    const target = doc.querySelectorAll('p')[kind === 'before' ? 1 : 0];
    target.style.setProperty(`break-${kind}`, 'column');
    const originalRects = dom.window.Element.prototype.getClientRects;
    dom.window.Element.prototype.getClientRects = function () {
      if (this === target) return [{ left: Number(this.dataset.page) * 320 + 10, width: 200, height: 384 }];
      return originalRects.call(this);
    };
    alignPaginatedText(doc, layout, false);
    const { runs } = preparePageRuns(doc);
    assert.equal(runs[0].style.top, '0px');
    assert.equal(runs[9].style.top, '0px');
    assert.equal(runs[19].getClientRects()[0].bottom, 430, 'following natural page still aligns');
    resetPageAlignment(doc);
    target.style.removeProperty(`break-${kind}`);
    alignPaginatedText(doc, layout, false);
    assert.equal(runs[9].getClientRects()[0].bottom, 430, 'layout change recomputes break boundaries');
    dom.window.close();
  }
});

test('compression cannot overlap glyphs and a single line is never stretched', () => {
  assert.equal(pageLineOffsets([{ top: 0, bottom: 30 }, { top: 35, bottom: 65 }], 0, 60, false), null);
  assert.equal(pageLineOffsets([{ top: 0, bottom: 30 }], 0, 300, false), null);
});
test('stable runs preserve text and live ranges across relayout and re-enable', () => {
  const {doc}=fixture(),text=doc.body.textContent;
  alignPaginatedText(doc,layout,false);
  const {runs}=preparePageRuns(doc), first=runs[0], last=runs[9];
  assert.equal(first.getClientRects()[0].top,20);
  assert.equal(last.getClientRects()[0].bottom,430);
  assert.equal(runs.at(-1).getClientRects()[0].bottom,84);
  const range=doc.createRange();range.setStart(first.firstChild,0);range.setEnd(last.firstChild,1);
  const nodes=[range.startContainer,range.endContainer];
  resetPageAlignment(doc);
  assert.equal(first.getClientRects()[0].top,25);
  alignPaginatedText(doc,{...layout,height:455},false);
  assert.equal(last.getClientRects()[0].bottom,435);
  assert.equal(doc.body.textContent,text);
  assert.deepEqual([range.startContainer,range.endContainer],nodes);
  assert.equal(range.toString(),'字'.repeat(10));
  assert.equal(preparePageRuns(doc).runs,runs);
});
test('publisher/custom CSS, vertical/RTL, oversized, invalid and illustrated pages stay native', () => {
  for(const [options,vertical,dimensions] of [
    [{enabled:'0'},false,layout],[{},true,layout],[{long:true},false,layout],[{},false,{...layout,height:0}],
  ]) {
    const {doc}=fixture(options);
    alignPaginatedText(doc,dimensions,vertical);
    assert.equal(doc.querySelector('modu-page-run'),null);
  }
  const {doc}=fixture({unsafe:true});alignPaginatedText(doc,layout,false);
  assert.equal(preparePageRuns(doc).runs[0].style.top,'0px');
  assert.equal(preparePageRuns(doc).runs[10].getClientRects()[0].top,20);
});
test('old/new CFIs retain text across nested markup, adjacent nodes and graphemes', () => {
  const dom=new JSDOM('<p id="one">甲乙<em>南宋😀行暮</em>丙丁<a href="#note">链接</a>尾声</p><p>第二段 é office العربية</p><aside id="note">注释</aside>');
  const doc=dom.window.document,original=doc.cloneNode(true),walker=doc.createTreeWalker(doc.body,4),checks=[];
  for(let n=walker.nextNode();n;n=walker.nextNode())for(let i=0;i<n.length;i++) {
    const r=doc.createRange();r.setStart(n,i);r.setEnd(n,n.length);
    checks.push({cfi:CFI.fromRange(r),text:r.toString()});
  }
  const cross=doc.createRange();cross.setStart(doc.querySelector('p').firstChild,1);cross.setEnd(doc.querySelectorAll('p')[1].firstChild,5);
  checks.push({cfi:CFI.fromRange(cross),text:cross.toString()});
  preparePageRuns(doc);
  for(const {cfi,text} of checks) {
    const restored=CFI.toRange(doc,CFI.parse(cfi));
    assert.equal(restored.toString(),text);
    assert.equal(CFI.toRange(original,CFI.parse(CFI.fromRange(restored))).toString(),text);
  }
  const first=doc.querySelector('modu-page-run'),r=doc.createRange();r.selectNodeContents(first);
  assert.equal(CFI.toRange(original,CFI.parse(CFI.fromRange(r))).toString(),first.textContent);
  assert.equal(doc.body.textContent,original.body.textContent);
  assert.ok([...doc.querySelectorAll('modu-page-run')].some(el=>el.textContent==='office'));
  assert.ok([...doc.querySelectorAll('modu-page-run')].some(el=>el.textContent==='العربية'));
});
test('TTS and word selection cross inline runs without reading note markers',async()=>{
  const moduleURL=async name=>{
    let code=await readFile(new URL(`../assets/foliate-js/src/${name}.js`,import.meta.url),'utf8');
    if(name==='smart-selection')code=code.replace('./annotation-geometry.js',await moduleURL('annotation-geometry'));
    return `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
  };
  const load=async name=>import(await moduleURL(name));
  const {TTS}=await load('tts');
  const dom=new JSDOM('<p>南宋的故事。<em>第二句话。</em><sup role="doc-noteref">12</sup></p><p>另一段。</p>');
  const doc=dom.window.document;
  globalThis.NodeFilter=dom.window.NodeFilter;globalThis.Range=dom.window.Range;
  const collect=()=>{
    const tts=new TTS(doc,null,()=>{},r=>r.toString()),out=[];
    for(let text=tts.start();text!=null;text=tts.next())out.push(text);
    return out;
  };
  const before=collect();preparePageRuns(doc);
  assert.deepEqual(collect(),before);
  assert.equal(before.join(''),'南宋的故事。第二句话。另一段。');
  const {smartSelectionRange}=await load('smart-selection');
  const first=doc.querySelector('modu-page-run');
  assert.equal(smartSelectionRange(doc,{node:first.firstChild,offset:0},{locale:'zh-CN'}).toString(),'南宋');
});
test('annotation rects contain only text once, not duplicate inline boxes',async()=>{
  const geometry=await readFile(new URL('../assets/foliate-js/src/annotation-geometry.js',import.meta.url),'utf8');
  const {annotationRangeRects}=await import(`data:text/javascript;base64,${Buffer.from(geometry).toString('base64')}`);
  const {doc,dom}=fixture();preparePageRuns(doc);
  dom.window.Range.prototype.getClientRects=function(){
    const left=[...this.startContainer.parentElement.parentElement.children].indexOf(this.startContainer.parentElement)*10;
    return [{left,right:left+10,top:25,bottom:45,width:10,height:20}];
  };
  const range=doc.createRange();range.selectNodeContents(doc.querySelector('p'));
  assert.deepEqual(annotationRangeRects(range),[{left:0,right:100,top:25,bottom:45,width:100,height:20}]);
});
const rows=Array.from({length:100},(_,i)=>({top:10+i*40,bottom:34+i*40}));
const cuts=(y,edges=rows)=>edges.some(r=>y>r.top&&y<r.bottom);
test('80/100 percent steps use gaps without losing overlap',()=>{
  for(const viewport of [400,413])for(const percent of [.8,1])for(const direction of [-1,1]){
    const current=1000,target=current+direction*viewport*percent,result=safeScrollOffset(rows,target,current,viewport);
    assert.ok(direction*(result-current)>0);
    assert.ok(Math.abs(result-current)<=Math.abs(target-current));
    assert.ok(!cuts(direction>0?result+viewport:result));
    if(viewport===400)assert.ok(!cuts(result)&&!cuts(result+viewport));
  }
});
test('mixed sizes prefer both edges when possible',()=>{
  const edges=[{top:90,bottom:120},{top:490,bottom:520},{top:530,bottom:565}];
  const result=safeScrollOffset(edges,100,0,400);
  assert.ok(!cuts(result,edges)&&!cuts(result+400,edges));
  assert.equal(safeScrollOffset([],100,0,400),100);
  assert.equal(safeScrollOffset(rows,0,0,400),0);
});
test('short viewports search far enough to clear large glyphs on taps and idle stops',()=>{
  for(const viewport of [255,315]) for(const glyph of [40,56]) {
    const edges=Array.from({length:100},(_,i)=>({top:i*(glyph+8),bottom:i*(glyph+8)+glyph}));
    for(const direction of [-1,1]) for(let target=500;target<650;target++) {
      const current=target-direction*viewport;
      const paged=safeScrollOffset(edges,target,current,viewport);
      assert.ok(!cuts(paged+(direction>0?viewport:0),edges));
      const settled=settledScrollOffset(edges,target,target-direction,viewport);
      assert.ok(!cuts(settled+(direction>0?viewport:0),edges));
    }
  }
});
test('settling follows reading direction, never masks/reflows and becomes stable at its target',()=>{
  // At viewport 20, these 24px glyphs / 40px rows cannot fit both edges in gaps.
  for(const direction of [-1,1])for(const target of [995,1008,1025,1040]) {
    const result=settledScrollOffset(rows,target,target-direction,20);
    assert.ok(Math.abs(result-target)<=1.6);
    // Use a realistic viewport for a full-glyph correction window.
    const settled=settledScrollOffset(rows,target,target-direction,420);
    assert.ok(!cuts(direction>0?settled+420:settled));
    assert.equal(settledScrollOffset(rows,settled,settled-direction,420),settled);
  }
});
test('document offsets include adjacent continuous chapters',()=>{
  const {doc,dom}=fixture();
  dom.window.Range.prototype.getClientRects=()=>[{top:10,bottom:34,width:100,height:24}];
  const result=lineAlignedOffset([{doc,offset:30},{doc,offset:480}],500,0,400);
  assert.ok(result>0&&result<=500);
});
test('scroll geometry is prepared once, reused on turns, and invalidated by layout/content changes',async()=>{
  const dom=new JSDOM('<p>正文</p><p>另一段</p>'),doc=dom.window.document;
  let calls=0, shift=0;
  dom.window.Range.prototype.getClientRects=function(){calls++;return [{top:100+shift,bottom:124+shift,width:20,height:24}];};
  assert.deepEqual(prepareScrollLines(doc),[{top:100,bottom:124}]);
  assert.equal(calls,2);
  for(let i=0;i<20;i++)lineAlignedOffset([{doc,offset:i}],90,0,400);
  assert.equal(calls,2,'page turns must not measure text again');
  shift=10;invalidateScrollLines(doc);
  assert.deepEqual(prepareScrollLines(doc),[{top:110,bottom:134}]);
  assert.equal(calls,4);
  shift=20;doc.querySelector('p').firstChild.data='更新正文';
  assert.deepEqual(prepareScrollLines(doc),[{top:120,bottom:144}]);
  await Promise.resolve();
  prepareScrollLines(doc);
  assert.equal(calls,6,'synchronous mutation invalidates only once');
  shift=30;doc.body.style.fontSize='20px';await Promise.resolve();
  assert.deepEqual(prepareScrollLines(doc),[{top:130,bottom:154}]);
  assert.equal(calls,8);
  dom.window.close();
});
test('cached scroll stops match raw rectangles in both directions, after chapter offsets change',()=>{
  const dom=new JSDOM('<p>正文</p>'),doc=dom.window.document;
  dom.window.Range.prototype.getClientRects=()=>rows.flatMap(row=>[
    {...row,width:20,height:row.bottom-row.top},{...row,width:20,height:row.bottom-row.top}]);
  for(const offset of [0,250,-400])for(const viewport of [400,420])for(const direction of [-1,1])
    for(const target of [500,999,1200])for(const settled of [false,true]){
      const current=target-direction*(settled?1:viewport*.8);
      const expected=(settled?settledScrollOffset:safeScrollOffset)(rows.map(r=>({top:r.top+offset,bottom:r.bottom+offset})),target,current,viewport);
      assert.equal(lineAlignedOffset([{doc,offset}],target,current,viewport,settled),expected);
    }
  dom.window.close();
});
test('visible range searches only page boundaries, preserving the exhaustive traversal result',async()=>{
  const paginator=await readFile(new URL('../assets/foliate-js/src/paginator.js',import.meta.url),'utf8');
  const code=paginator.slice(paginator.indexOf('const makeRange ='),paginator.indexOf('const getDirection ='));
  const old=code.replace(/  const from = walker.nextNode\(\) \?\? doc.body[\s\S]*?for \(let node = walker.lastChild\(\); node; node = walker.lastChild\(\)\) to = node/,
    `  const nodes=[];for(let n=walker.nextNode();n;n=walker.nextNode())nodes.push(n)
       const from=nodes[0]??doc.body,to=nodes.at(-1)??from`);
  assert.notEqual(old,code);
  const dom=new JSDOM(`<body>${Array.from({length:30},(_,p)=>`<p>${Array.from({length:80},(_,i)=>`<span data-x="${Math.floor((p*80+i)/400)*300+(i%20)*10}">字</span>`).join('')}</p>`).join('')}<script>ignored</script></body>`);
  const doc=dom.window.document;let reads=0;
  const bounds=el=>{
    const spans=el.matches('span')?[el]:[...el.querySelectorAll('span')];
    const left=Math.min(...spans.map(s=>+s.dataset.x)),right=Math.max(...spans.map(s=>+s.dataset.x+10));
    return {left,right,width:right-left,height:20};
  };
  dom.window.Element.prototype.getBoundingClientRect=function(){reads++;return bounds(this)};
  dom.window.Range.prototype.getBoundingClientRect=function(){reads++;return bounds(this.startContainer.parentElement)};
  const fast=runInNewContext(`${code};getVisibleRange`,{NodeFilter:dom.window.NodeFilter});
  const exhaustive=runInNewContext(`${old};getVisibleRange`,{NodeFilter:dom.window.NodeFilter});
  for(const [start,end] of [[0,300],[300,600],[750,900],[1800,2100]]){
    reads=0;const expected=exhaustive(doc,start,end,r=>r),slow=reads;
    reads=0;const actual=fast(doc,start,end,r=>r);
    assert.equal(actual.startContainer,expected.startContainer);
    assert.equal(actual.endContainer,expected.endContainer);
    assert.equal(actual.startOffset,expected.startOffset);
    assert.equal(actual.endOffset,expected.endOffset);
    if(start<1800)assert.ok(reads<slow/4,`${reads} boundary reads versus ${slow} exhaustive reads`);
  }
  dom.window.close();
});
test('hidden chapter-end notes cannot extend the first page visible range or suppress speech following',async()=>{
  const paginator=await readFile(new URL('../assets/foliate-js/src/paginator.js',import.meta.url),'utf8');
  const code=paginator.slice(paginator.indexOf('const makeRange ='),paginator.indexOf('const getDirection ='));
  for(const vertical of [false,true]) {
    const dom=new JSDOM('<body><div id="empty"></div><h1 data-page="0">章</h1><div style="display:contents"><p id="speech"><span data-page="0">甲</span><span data-page="1">乙</span></p></div><div id="overflow"><span data-page="1">丙</span></div><aside style="display:none"><p><span>隐藏脚注</span></p></aside></body>');
    const doc=dom.window.document;
    const rect=(left,width)=>vertical
      ? {left:20,right:40,top:left,bottom:left+width,width:20,height:width}
      : {left,right:left+width,top:20,bottom:40,width,height:20};
    const empty={left:0,right:0,top:0,bottom:0,width:0,height:0};
    const bounds=el=>{
      if(el.closest('aside') || el.id==='empty' || el.style.display==='contents')return empty;
      if(el.id==='overflow')return {...rect(410,20),height:0};
      const spans=el.hasAttribute('data-page')?[el]:[...el.querySelectorAll('[data-page]')];
      if(!spans.length)return empty;
      const positions=spans.map(s=>+s.dataset.page*400+10);
      return rect(Math.min(...positions),Math.max(...positions)-Math.min(...positions)+20);
    };
    dom.window.Element.prototype.getBoundingClientRect=function(){return bounds(this)};
    dom.window.Range.prototype.getBoundingClientRect=function(){return bounds(this.startContainer.nodeType===3?this.startContainer.parentElement:this.startContainer)};
    const visible=runInNewContext(`${code};getVisibleRange`,{NodeFilter:dom.window.NodeFilter});
    const map=vertical?r=>({left:r.top,right:r.bottom}):r=>r;
    const first=visible(doc,0,400,map),second=visible(doc,400,800,map);
    assert.equal(first.toString(),'章甲');
    assert.equal(second.toString(),'乙丙','boxless and zero-height containers must not hide visible descendants');
    const point=doc.createRange();point.setStart(doc.querySelector('#speech span[data-page="1"]').firstChild,0);point.collapse(true);
    const end=first.cloneRange();end.collapse(false);
    assert.ok(point.compareBoundaryPoints(0,end)>=0,'the in-paragraph speech cursor on page two must be outside page one');
    dom.window.close();
  }
});
test('prepare before display, never reflow after a page turn; settle changes only scroll offset',async()=>{
  const paginator=await readFile(new URL('../assets/foliate-js/src/paginator.js',import.meta.url),'utf8');
  assert.equal(paginator.match(/alignPaginatedText\(doc,/g)?.length,1);
  const render = paginator.indexOf('this.render(layout, timing)');
  assert.ok(render >= 0 && render < paginator.indexOf("this.#iframe.style.visibility = ''"));
  assert.match(paginator,/reason === 'page' && !this.#vertical/);
  assert.doesNotMatch(source,/requestAnimationFrame|setTimeout|innerHTML/);
});

test('line spacing measures adjacent reader runs together without losing tall glyphs or inline styles', () => {
  const dom = new JSDOM('<style>html{--modu-align-pages:1}p{line-height:10px}span{display:inline}</style>' +
    '<p>' + '普通文字 '.repeat(20) + '<span>高字</span>' + '正文 '.repeat(20) + '<sup>注</sup></p>');
  const doc = dom.window.document;
  preparePageRuns(doc);
  let measurements = 0;
  dom.window.Range.prototype.getClientRects = function() {
    measurements++;
    const text = this.cloneContents().textContent;
    // Different glyph/font boxes within a range must still contribute their maximum.
    return [{width:10,height:12}, {width:10,height:text.includes('高') ? 40 : 24}];
  };
  fitTextLineSpacing(doc);
  assert.ok(parseFloat(doc.querySelector('p').style.lineHeight) >= 42);
  assert.equal(measurements, 3, 'one contiguous run group before, inside and after the styled span');
  assert.equal(doc.querySelector('sup').style.lineHeight, '', 'notes retain publisher metrics');
  dom.window.close();
});

test('scroll after pagination measures adjacent runs once and retains only line unions',()=>{
 const dom=new JSDOM('<p>'+ '甲'.repeat(60) +'</p><p>'+ '乙'.repeat(40) +'</p>');
 const doc=dom.window.document;preparePageRuns(doc);
 let calls=0;
 dom.window.Range.prototype.getClientRects=function(){
   calls++;const top=this.toString().includes('甲')?10:50;
   return Array.from({length:this.toString().length},()=>({top,bottom:top+24,width:12,height:24}));
 };
 assert.deepEqual(prepareScrollLines(doc),[{top:10,bottom:34},{top:50,bottom:74}]);
 assert.equal(calls,2,'measure paragraph runs together after switching to scrolling');
 prepareScrollLines(doc);assert.equal(calls,2,'unchanged scroll geometry is reused');
 invalidateScrollLines(doc);prepareScrollLines(doc);assert.equal(calls,4);
 dom.window.close();
});
