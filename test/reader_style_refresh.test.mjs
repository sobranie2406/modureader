import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
const source = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url),'utf8');
const start = source.indexOf('  setStyles(styles) {');
const setStyles = source.slice(start, source.indexOf('  get writingMode()', start));
const styleDocument = source.slice(source.indexOf('  #styleDocument(doc) {'), source.indexOf('  #ensureContinuous()'));

function fixture(continuous) {
  const counts = {cleared:0, captured:0, waited:0, writes:0};
  const pair = ['', ''].map(value=>({get textContent(){return value}, set textContent(next){value=next;counts.writes++}}));
  const Harness = vm.runInNewContext(`class Harness {
    #styles; #styleMap = new WeakMap(); #view; #continuous; #preparingView = false;
    constructor(doc, pair, continuous) {
      this.#view = {document:doc, refreshDirection:()=>({changed:false}), expand(){}};
      this.#styleMap.set(doc, pair);
      if (continuous) this.#continuous = {entries:new Map([[0,{index:0,view:this.#view}]])};
    }
    #applyBackground() {} render() {}
    ${styleDocument}
    ${setStyles}
  }; Harness`, {
    clearReaderFontFallback:()=>counts.cleared++,
    captureBookFontFamilies:()=>counts.captured++,
    waitForReaderFonts:async()=>{counts.waited++;return true},
  });
  return {reader:new Harness({},pair,continuous),counts};
}
for (const continuous of [false,true]) {
  test(`unchanged styles do not rewrite CSS, restore failed fonts or rescan chapters: continuous=${continuous}`, async()=>{
    const {reader,counts} = fixture(continuous);
    reader.setStyles(['@font-face{}','p{color:red}']);
    assert.deepEqual(counts,{cleared:1,captured:1,waited:1,writes:2});
    for(let i=0;i<20;i++) reader.setStyles(['@font-face{}','p{color:red}']);
    assert.deepEqual(counts,{cleared:1,captured:1,waited:1,writes:2});
    reader.setStyles(['@font-face{}','p{color:blue}']);
    assert.deepEqual(counts,{cleared:2,captured:2,waited:2,writes:4});
    await Promise.resolve();
  });
}
