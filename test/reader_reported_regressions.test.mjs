import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
const source = name => readFile(new URL(`../assets/foliate-js/src/${name}`, import.meta.url), 'utf8');
const load = async name => import(`data:text/javascript;base64,${Buffer.from(await source(name)).toString('base64')}`);
const { installSettledSelection } = await load('settled-selection.js');
const { waitForReaderFonts } = await load('reader-font-ready.js');
const settle = () => new Promise(resolve => setTimeout(resolve, 15));

test('Android first one-character selection opens without pointercancel or handle drag', async () => {
  for (const endOffset of [1, 4]) {
    const doc = new EventTarget();
    let range, calls = 0;
    const stop = installSettledSelection(doc, {getRange: () => range,
      onSelection: () => calls++, delay: 1});
    doc.dispatchEvent(new Event('pointerdown'));
    range = {startContainer: doc, endContainer: doc, startOffset: 0, endOffset,
      cloneRange() {return {...this};}};
    doc.dispatchEvent(new Event('selectionchange'));
    await settle(); assert.equal(calls, 1);
    doc.dispatchEvent(new Event('contextmenu', {cancelable: true}));
    doc.dispatchEvent(new Event('touchend'));
    await settle(); assert.equal(calls, 1, 'do not open duplicate toolbars');
    range = {...range, endOffset: endOffset + 1};
    doc.dispatchEvent(new Event('selectionchange'));
    await settle(); assert.equal(calls, 2, 'handle changes update the toolbar');
    range = undefined; doc.dispatchEvent(new Event('selectionchange'));
    await settle(); assert.equal(calls, 2);
    stop();
  }
});
test('selection collapse, quick mark and disposed document cancel pending toolbars', async () => {
  for (const mode of ['collapse','quick','dispose']) {
    const doc = new EventTarget(); let calls = 0;
    let range = {cloneRange() {return this;}};
    const stop = installSettledSelection(doc, {getRange: () => range,
      onSelection: () => calls++, delay: 1});
    doc.dispatchEvent(new Event('selectionchange'));
    if (mode === 'collapse') {range = null; doc.dispatchEvent(new Event('selectionchange'));}
    if (mode === 'quick') doc.__moduQuickMarkEnabled = true;
    if (mode === 'dispose') stop();
    await settle(); assert.equal(calls, 0, mode); stop();
  }
});
test('font readiness handles success, failure, timeout and hosts without FontFaceSet', async () => {
  assert.equal(await waitForReaderFonts({}), true);
  assert.equal(await waitForReaderFonts({fonts: {ready: Promise.resolve()}}), true);
  assert.equal(await waitForReaderFonts({fonts: {ready: Promise.reject(Error('font'))}}), false);
  assert.equal(await waitForReaderFonts({fonts: {ready: new Promise(() => {})}}, 1), false);
});
test('actual chapter loader stays hidden until custom font metrics are ready, on every chapter', async () => {
  const paginator = await source('paginator.js');
  const method = paginator.slice(paginator.indexOf('  async load(src,'), paginator.indexOf('\n  render(layout) {'));
  const Harness = runInNewContext(`class Harness {
    #destroyed = false; #cancelLoad; #cleanup = [];
    #iframe; #vertical; #rtl; #writingMode; #layout = {};
    #contentRange = {selectNodeContents(){}}; #observer = {observe(){}};
    constructor(doc) {this.#iframe = new EventTarget(); this.#iframe.style = {}; this.doc = doc; this.renders = [];}
    get document() {return this.doc} get frame() {return this.#iframe}
    render(layout) {this.renders.push(this.doc.loaded)} expand() {} setImageSize() {}
    ${method}
  }; Harness`, {EventTarget, waitForReaderFonts, getDirection: () => ({}), console});
  for (let chapter = 0; chapter < 2; chapter++) {
    const doc = new EventTarget(); let release;
    doc.body = {getBoundingClientRect(){}};
    doc.fonts = {ready: new Promise(r => {release = r;})};
    const reader = new Harness(doc); let done = false;
    const pending = reader.load('chapter', () => {}, () => ({})).then(() => done = true);
    reader.frame.dispatchEvent(new Event('load'));
    await Promise.resolve();
    assert.equal(reader.frame.style.visibility, 'hidden'); assert.equal(done, false);
    assert.equal(reader.renders.length, 0, 'no pagination with fallback metrics');
    doc.loaded = true; release(); await pending;
    assert.equal(reader.frame.style.visibility, '');
    assert.equal(reader.renders.at(-1), true);
    assert.equal(reader.renders.length, 1, 'paginate only once after fonts settle');
  }
});
test('actual scrolled next/previous retain 20 percent overlap; explicit distances are unchanged', async () => {
  const paginator = await source('paginator.js');
  const methods = paginator.slice(paginator.indexOf('  #scrollPrev(distance)'), paginator.indexOf('  get atStart()'));
  const Harness = runInNewContext(`class Harness {
    #view = {}; scrolled = true; start = 0; size = 801; viewSize = 10000;
    get end() {return this.start + this.size}
    #scrollTo(offset) {this.start = offset; return Promise.resolve()}
    #scrollToPage() {} next(distance) {return this.#scrollNext(distance)}
    prev(distance) {return this.#scrollPrev(distance)}
    ${methods}
  }; Harness`);
  const reader = new Harness();
  for (let i = 1; i <= 10; i++) {
    const oldEnd = reader.end;
    await reader.next();
    assert.ok(Math.abs(reader.start - i * 801 * .8) < 1e-8);
    assert.ok(Math.abs(oldEnd - reader.start - 801 * .2) < 1e-8);
  }
  const before = reader.start; await reader.prev();
  assert.ok(Math.abs(before - reader.start - 801 * .8) < 1e-8);
  const current = reader.start; await reader.next(10); assert.equal(reader.start, current + 10);
  reader.start = 1; await reader.prev(); assert.equal(reader.start, 0);
  assert.equal(await reader.prev(), true, 'chapter boundary still navigates');
});
