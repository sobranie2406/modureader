import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';

const fontSource = await readFile(new URL('../assets/foliate-js/src/reader-font-ready.js', import.meta.url), 'utf8');
const {waitForReaderFonts} = await import(`data:text/javascript;base64,${Buffer.from(fontSource).toString('base64')}`);
const source = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
const method = source.slice(source.indexOf('  async load(src,'), source.indexOf('\n  render(layout) {'));

function fixture(ready = Promise.resolve(), waitForFonts = waitForReaderFonts) {
  const timers = new Map(); let id = 0;
  const Harness = runInNewContext(`class Harness {
    #destroyed = false; #cancelLoad; #cleanup = [];
    #iframe; #vertical; #rtl; #writingMode; #layout = {};
    #contentRange = {selectNodeContents(){}}; #observer = {observe(){}};
    constructor(doc) {
      this.#iframe = new EventTarget(); this.#iframe.style = {};
      this.doc = doc; this.renders = 0; this.expansions = 0;
    }
    get document() {return this.doc} get frame() {return this.#iframe}
    render() {this.renders++} expand() {this.expansions++} setImageSize() {}
    close() {this.#destroyed = true; this.#cancelLoad?.(); this.#cleanup.forEach(f => f());}
    ${method}
  }; Harness`, {
    EventTarget, waitForReaderFonts: waitForFonts, getDirection: () => ({}),
    console: {warn(){}},
    setTimeout: (fn, ms) => {timers.set(++id, {fn, ms}); return id;},
    clearTimeout: id => timers.delete(id),
  });
  const doc = new EventTarget(); doc.body = {getBoundingClientRect(){}};
  doc.fonts = new EventTarget(); doc.fonts.ready = ready;
  return {reader: new Harness(doc), doc, timers};
}

test('slow fonts remain hidden beyond 250ms and reveal only after readiness', async () => {
  let release;
  const {reader, doc, timers} = fixture(new Promise(r => release = r));
  const pending = reader.load('blob:chapter', () => {}, () => ({}));
  reader.frame.dispatchEvent(new Event('load'));
  await new Promise(resolve => setTimeout(resolve, 300));
  assert.equal(reader.frame.style.visibility, 'hidden');
  assert.equal(reader.renders, 0, 'no layout using a temporary font');
  release();
  await pending;
  assert.equal(reader.frame.style.visibility, '');
  assert.equal(reader.renders, 1);
  assert.equal(timers.size, 0);
  doc.fonts.dispatchEvent(new Event('loadingdone'));
  assert.equal(reader.expansions, 1);
  reader.close();
  doc.fonts.dispatchEvent(new Event('loadingdone'));
  assert.equal(reader.expansions, 1, 'closed views must not resize');
});

for (const failure of ['timeout', 'rejection', 'failed face']) {
  test(`font ${failure} fails loading without revealing substitute text`, async () => {
    let fail;
    const ready = failure === 'failed face' ? Promise.resolve()
      : new Promise((_, reject) => fail = reject);
    const {reader, doc, timers} = fixture(ready, doc => waitForReaderFonts(doc, 10));
    if (failure === 'failed face') {
      doc.fonts[Symbol.iterator] = function* () { yield {status: 'error'}; };
    }
    const pending = reader.load('blob:chapter', () => {}, () => ({}));
    const rejected = assert.rejects(pending, /font loading timed out or failed/);
    reader.frame.dispatchEvent(new Event('load'));
    if (failure === 'rejection') fail(Error('bad font'));
    await rejected;
    assert.equal(reader.frame.style.visibility, 'hidden');
    assert.equal(reader.renders, 0);
    assert.equal(timers.size, 0);
    doc.fonts.dispatchEvent(new Event('loadingdone'));
    assert.equal(reader.expansions, 0, 'a failed view cannot revive later');
    reader.close();
  });
}

test('unused faces do not block successfully loaded requested fonts', async () => {
  const fonts = [{status: 'loaded'}, {status: 'unloaded'}];
  fonts.ready = Promise.resolve();
  assert.equal(await waitForReaderFonts({fonts}), true);
});

test('iframe timeout rejects navigation and ignores a late load event', async () => {
  const {reader, timers} = fixture();
  const pending = reader.load('blob:chapter', () => {}, () => ({}));
  const rejected = assert.rejects(pending, /chapter loading timed out/);
  const timer = [...timers.values()][0];
  assert.equal(timer.ms, 15000); timer.fn();
  await rejected;
  reader.frame.dispatchEvent(new Event('load'));
  await Promise.resolve();
  assert.equal(reader.renders, 0);
  assert.equal(timers.size, 0);
});

test('closing during font discovery rejects once and never exposes the old view', async () => {
  let release;
  const {reader, timers} = fixture(new Promise(r => release = r));
  const pending = reader.load('blob:chapter', () => {}, () => ({}));
  const rejected = assert.rejects(pending, /closed/);
  reader.frame.dispatchEvent(new Event('load'));
  reader.close(); release();
  await rejected; await Promise.resolve();
  assert.equal(reader.renders, 0);
  assert.equal(timers.size, 0);
});
