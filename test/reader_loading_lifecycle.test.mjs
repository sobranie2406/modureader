import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';

const fontSource = await readFile(new URL('../assets/foliate-js/src/reader-font-ready.js', import.meta.url), 'utf8');
const {waitForReaderFonts} = await import(`data:text/javascript;base64,${Buffer.from(fontSource).toString('base64')}`);
const source = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
const method = source.slice(source.indexOf('  async load(src,'), source.indexOf('\n  render(layout) {'));

function inlineStyle() {
  const values = new Map(), priorities = new Map();
  return {
    setProperty(k,v,p) { values.set(k,v); priorities.set(k,p); },
    getPropertyValue: k => values.get(k) ?? '',
    getPropertyPriority: k => priorities.get(k) ?? '',
    removeProperty(k) {values.delete(k); priorities.delete(k);},
  };
}

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
    EventTarget, AbortController, waitForReaderFonts: waitForFonts, getDirection: () => ({}),
    console: {warn(){}},
    setTimeout: (fn, ms) => {timers.set(++id, {fn, ms}); return id;},
    clearTimeout: id => timers.delete(id),
  });
  const doc = new EventTarget(); doc.body = {getBoundingClientRect(){}, style:inlineStyle()};
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

test('a real font rejection displays generic text and completes chapter loading', async () => {
    let fail;
    const ready = new Promise((_, reject) => fail = reject);
    const {reader, doc, timers} = fixture(ready);
    const pending = reader.load('blob:chapter', () => {}, () => ({}));
    reader.frame.dispatchEvent(new Event('load'));
    fail(Error('bad font'));
    await pending;
    assert.equal(doc.body.style.getPropertyValue('font-family'), 'serif');
    assert.equal(reader.frame.style.visibility, '');
    assert.equal(reader.renders, 1);
    assert.equal(timers.size, 0);
    doc.fonts.dispatchEvent(new Event('loadingdone'));
    assert.equal(reader.expansions, 1, 'the recovered view stays interactive');
    reader.close();
});

test('fonts can complete after 8, 15 and 30 seconds without fallback or failure', async t => {
  t.mock.timers.enable({apis: ['setTimeout']});
  let release;
  const {reader, doc, timers} = fixture(new Promise(r => release = r));
  let done = false;
  const pending = reader.load('blob:slow-font', () => {}, () => ({})).then(() => done = true);
  reader.frame.dispatchEvent(new Event('load'));
  t.mock.timers.tick(31000);
  await Promise.resolve();
  assert.equal(done, false);
  assert.equal(reader.renders, 0);
  assert.equal(reader.frame.style.visibility, 'hidden');
  assert.equal(timers.size, 0);
  release(); await pending;
  assert.equal(reader.renders, 1);
  assert.equal(reader.frame.style.visibility, '');
  reader.close();
});

function textDocument({reject = false, hidden = false} = {}) {
  const requests = [];
  const el = {closest: () => null, getClientRects: () => hidden ? [] : [{}], style:inlineStyle()};
  const nodes = [{parentElement: el, textContent: '正文 中文 ABC'},
    {parentElement: el, textContent: '正文 DEF'}];
  const fonts = [{family: 'UnusedBrokenFace', status: 'error'}];
  fonts.ready = new Promise(() => {}); // An unrelated font must not block text.
  fonts.load = async (font, text) => {
    requests.push({font, text});
    if (reject) throw Error('used font broken');
    return [{status:'loaded'}];
  };
  const doc = {fonts, body:{getBoundingClientRect(){}},
    createTreeWalker: () => {let i=0; return {nextNode:()=>nodes[i++]};},
    defaultView:{getComputedStyle:()=>({fontStyle:'normal',fontWeight:'400',fontSize:'24px',
      fontFamily:'"Body", "English"',display:'block',visibility:'visible'})}};
  return {doc,requests,el};
}

test('only actual text faces are requested, with Chinese and Latin coverage', async () => {
  const {doc,requests} = textDocument();
  assert.equal(await waitForReaderFonts(doc), true);
  assert.equal(requests.length, 1, 'one request per font, not per text node');
  assert.equal(requests[0].font, 'normal 400 24px "Body", "English"');
  for (const char of '正文中ABCDEF') assert.ok(requests[0].text.includes(char));
});

test('a genuinely used broken font falls back; hidden text fonts do not block', async () => {
  const broken = textDocument({reject:true});
  assert.equal(await waitForReaderFonts(broken.doc), true);
  assert.equal(broken.el.style.getPropertyValue('font-family'), 'serif');
  const {doc,requests} = textDocument({hidden:true,reject:true});
  assert.equal(await waitForReaderFonts(doc), true);
  assert.equal(requests.length, 0);
});

test('font failure arriving after cancellation cannot alter the old page', async () => {
  const {doc,el} = textDocument();
  let fail;
  doc.fonts.load = () => new Promise((_, reject) => fail = reject);
  const controller = new AbortController();
  const pending = waitForReaderFonts(doc, controller.signal);
  controller.abort();
  assert.equal(await pending, false);
  fail(Error('late error'));
  await Promise.resolve();
  assert.equal(el.style.getPropertyValue('font-family'), '');
});

test('unused faces do not block successfully loaded requested fonts', async () => {
  const fonts = [{status: 'loaded'}, {status: 'unloaded'}];
  fonts.ready = Promise.resolve();
  assert.equal(await waitForReaderFonts({fonts}), true);
});

test('a slow iframe has no fatal deadline; cancellation ignores a late load event', async () => {
  const {reader, timers} = fixture();
  const pending = reader.load('blob:chapter', () => {}, () => ({}));
  const rejected = assert.rejects(pending, /closed/);
  assert.equal(timers.size, 0, 'publisher fonts may delay the native load event');
  reader.close();
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
