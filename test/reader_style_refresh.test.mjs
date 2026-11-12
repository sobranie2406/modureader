import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const source = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url),'utf8');
const start = source.indexOf('  setStyles(styles,');
const setStyles = source.slice(start, source.indexOf('  get writingMode()', start));
const styleDocument = source.slice(source.indexOf('  #styleDocument(doc)'), source.indexOf('  #ensureContinuous()'));

test('reader line-height has a safe minimum and controls nested publisher text', async () => {
  const book = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8');
  const getCSS = vm.runInNewContext(
    book.slice(book.indexOf('const getCSS ='), book.indexOf('const fixHeadingColor =')) + '\ngetCSS',
    {isPdf:false, readerFontCSS:()=>({faces:'',family:''}),
      readerSelectionCSS:()=>'', readerFontWeightCSS:()=>'', reducedReaderMotionCSS:''},
  );
  for (const spacing of [0, .3, 1, 1.8, 3]) {
    const css = getCSS({spacing, useBookStyles:false});
    const paragraph = css.slice(css.indexOf('p, li, blockquote'), css.indexOf('.anx-text-center'));
    assert.match(paragraph, new RegExp('line-height: ' + Math.max(1, spacing) + ' !important'));
    assert.match(paragraph, /body :is\(span[^}]+line-height: inherit !important/s);
    assert.match(paragraph, /table \*, pre \*, code \*, ruby \*, math \*, svg \*, sup \*, sub \*/);
    assert.doesNotMatch(css, /line-height: 0(?:[ ;]|$)/);
  }
  const publisherCSS = getCSS({spacing:0, useBookStyles:true});
  assert.doesNotMatch(publisherCSS.slice(0, publisherCSS.indexOf('.anx-text-center')), /line-height:/);
});

test('reader colors reach publisher spans and headings without changing typography', async () => {
  const book = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8');
  const getCSS = vm.runInNewContext(
    book.slice(book.indexOf('const getCSS ='), book.indexOf('const fixHeadingColor =')) + '\ngetCSS',
    {isPdf:false, readerFontCSS:()=>({faces:'',family:''}),
      readerSelectionCSS:()=>'', readerFontWeightCSS:()=>'', reducedReaderMotionCSS:''},
  );
  const options = {fontColor:'#ddd', useBookStyles:false, customCSSEnabled:false};
  const css = getCSS(options);
  const rule = css.match(/body :is\(h1[^}]+\}/)?.[0];
  assert.ok(rule, 'nested publisher text must not retain hard-coded black');
  assert.match(rule, /h6, span, b, strong, em, i/);
  assert.match(rule, /color: var\(--modu-reader-font-color, #ddd\) !important/);
  assert.match(rule, /a \*, svg \*, pre \*, code \*/);
  assert.doesNotMatch(rule, /font-size|line-height|margin|padding|background/);
  assert.doesNotMatch(getCSS({...options,useBookStyles:true}), /body :is\(h1/);
  const eink = getCSS({...options, useBookStyles:true, eInkMode:true, fontColor:'#000000'});
  assert.match(eink, /body, body \*:not\(:where\(svg, svg \*, img, canvas, video\)\)/);
  assert.match(eink, /color: var\(--modu-reader-font-color, #000000\) !important/);
  assert.doesNotMatch(getCSS({...options,eInkMode:false}), /body, body \*:not/);
  assert.ok(getCSS({...options,customCSSEnabled:true,customCSS:'/* user override */'})
    .indexOf('/* user override */') > css.indexOf(rule));
});

function fixture(continuous) {
  const counts = {cleared:0, captured:0, waited:0, writes:0};
  const pair = ['', ''].map(value=>({get textContent(){return value}, set textContent(next){value=next;counts.writes++}}));
  const Harness = vm.runInNewContext(`class Harness {
    #styles; #styleMap = new WeakMap(); #view; #continuous; #preparingView = false; #pendingViews = new Set();
    constructor(doc, pair, continuous) {
      this.#view = {document:doc, refreshDirection:()=>({changed:false}), expand(){}};
      this.#styleMap.set(doc, pair);
      if (continuous) this.#continuous = {entries:new Map([[0,{index:0,view:this.#view}]])};
    }
    renders = 0;
    #applyBackground() {} render() { this.renders++ }
    get savedStyles() { return this.#styles }
    getContents() { return [{doc:this.#view.document}] }
    ${styleDocument}
    ${setStyles}
  }; Harness`, {
    clearReaderFontFallback:()=>counts.cleared++,
    captureBookFontFamilies:()=>counts.captured++,
    prepareReaderFontWeight:()=>{},
    waitForReaderFonts:async()=>{counts.waited++;return true},
  });
  const colors = new Map();
  const doc = {documentElement:{style:{setProperty:(key,value)=>colors.set(key,value)}}};
  return {reader:new Harness(doc,pair,continuous),counts,pair,colors};
}
for (const continuous of [false,true]) {
  test(`unchanged styles do not rewrite CSS, restore failed fonts or rescan chapters: continuous=${continuous}`, async()=>{
    const {reader,counts} = fixture(continuous);
    reader.setStyles(['@font-face{}','p{color:red}']);
    assert.deepEqual(counts,{cleared:1,captured:1,waited:1,writes:2});
    await Promise.resolve();
    const renders = reader.renders;
    for(let i=0;i<20;i++) reader.setStyles(['@font-face{}','p{color:red}']);
    await Promise.resolve();
    assert.equal(reader.renders, renders, 'unchanged styles must not repaginate loaded chapters');
    assert.deepEqual(counts,{cleared:1,captured:1,waited:1,writes:2});
    reader.setStyles(['@font-face{}','p{color:blue}']);
    assert.deepEqual(counts,{cleared:2,captured:2,waited:2,writes:3});
    await Promise.resolve();
  });
  test(`night/day recolors without font reload, layout or selection work: continuous=${continuous}`, async()=>{
    const {reader,counts,pair,colors} = fixture(continuous);
    reader.setStyles(['@font-face{}','p{color:black}']);
    await Promise.resolve();
    const renders = reader.renders;
    for (const color of ['white','black','white']) {
      const css = ['@font-face{}',`p{color:${color}}`];
      reader.setStyles(css, {paintOnly:true,fontColor:color});
      assert.equal(colors.get('--modu-reader-font-color'),color);
      assert.equal(pair[1].textContent, 'p{color:black}'); // never replace the font sheet
      assert.equal(reader.savedStyles, css); // next chapter inherits the current palette
    }
    await Promise.resolve();
    assert.deepEqual(counts,{cleared:1,captured:1,waited:1,writes:2});
    assert.equal(reader.renders, renders);
    reader.setStyles(['@font-face{}','p{font-size:24px}']);
    await Promise.resolve();
    assert.equal(counts.waited,2);
    assert.ok(reader.renders > renders);
  });
}
