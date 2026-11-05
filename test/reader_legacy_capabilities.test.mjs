import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {runInNewContext} from 'node:vm';
const {JSDOM} = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const read = name => readFile(new URL(`../assets/foliate-js/src/${name}.js`, import.meta.url), 'utf8');
const blob = await read('legacy-blob');
for (const native of [false, true]) test(`Blob reading supports legacy missing methods; native=${native}`, async () => {
  class TestBlob {}
  const originals = {};
  if (native) for (const method of ['text','arrayBuffer','stream']) {
    originals[method] = TestBlob.prototype[method] = () => method;
  }
  const bytes = new Uint8Array([65,66]).buffer;
  const body = {getReader() {}};
  class TestResponse {
    constructor(value) {assert.ok(value instanceof TestBlob); this.body = body}
    text() {return Promise.resolve('AB')}
    arrayBuffer() {return Promise.resolve(bytes)}
  }
  runInNewContext(blob, {Blob: TestBlob, Response: TestResponse});
  if (native) for (const name of Object.keys(originals)) assert.equal(TestBlob.prototype[name], originals[name]);
  else {
    const value = new TestBlob();
    assert.equal(await value.text(), 'AB'); assert.equal(await value.arrayBuffer(), bytes);
    assert.equal(value.stream(), body);
  }
});
const weights = await read('reader-font-weight');
for (const modern of [false,true]) test(`reader CSS preserves headings, links, images and text; modern=${modern}`, () => {
  const CSS = {supports: () => modern};
  const {readerFontWeightCSS,prepareReaderFontWeight} = runInNewContext(
    weights.replaceAll('export function ', 'function ') + '\n({readerFontWeightCSS,prepareReaderFontWeight})', {CSS});
  const dom = new JSDOM('<div id="struct"><p>text</p></div><div id="para">plain <span>text</span></div><h2 id="heading">Title</h2><a><span id="link">Link</span></a><p id="image"><span><img></span></p><svg><text id="vector">Vector</text></svg>');
  dom.window.CSS = CSS;
  const doc = dom.window.document, before = doc.body.textContent;
  const css = readerFontWeightCSS({fontWeight:700,simulateBold:true});
  prepareReaderFontWeight(doc, css);
  assert.equal(doc.body.textContent, before);
  if (modern) {
    assert.equal(doc.querySelector('[data-modu-reader-weight]'), null);
    assert.match(css, /:where/);
  } else {
    assert.doesNotMatch(css, /:where|:has|:is\(/);
    assert.ok(doc.querySelector('#para[data-modu-paragraph]'));
    assert.equal(doc.querySelector('#struct[data-modu-paragraph]'), null);
    assert.ok(doc.querySelector('#image[data-modu-image-paragraph]'));
    assert.equal(doc.querySelector('#heading[data-modu-reader-weight]'), null);
    assert.equal(doc.querySelector('#link[data-modu-reader-color]'), null);
    assert.equal(doc.querySelector('#vector[data-modu-reader-weight]'), null);
    for (const match of css.matchAll(/([^{}]+)\{/g)) doc.querySelectorAll(match[1].replace(/\/\*[\s\S]*?\*\//g,''));
  }
  dom.window.close();
});
const pdf = await read('pdf');
test('PDF selector fallback is restricted to old engines; native CSS stays identical', () => {
  const definition = pdf.slice(pdf.indexOf('const compatiblePDFCSS'), pdf.indexOf('// https:'));
  const css = '.layer :is(span, img) { color: red }';
  for (const supported of [false,true]) {
    const convert = runInNewContext(definition+'\ncompatiblePDFCSS',{CSS:{supports:()=>supported}});
    assert.equal(convert(css), supported ? css : '.layer :-webkit-any(span, img) { color: red }');
  }
});
const fixed = await read('fixed-layout');
test('fixed-layout styles work with and without constructible stylesheet support', () => {
  const start = fixed.indexOf('        const css = `:host');
  const block = fixed.slice(start,fixed.indexOf('        this.#observer.observe',start)).replaceAll('this.#root','root');
  for (const supported of [false,true]) {
    const dom = new JSDOM('<div></div>'), root = dom.window.document.querySelector('div').attachShadow({mode:'open'});
    class Sheet {replaceSync(css) {this.css = css}}
    if (supported) root.adoptedStyleSheets = [];
    runInNewContext(block,{root,document:dom.window.document,CSSStyleSheet:supported?Sheet:undefined});
    assert.match(supported?root.adoptedStyleSheets[0].css:root.querySelector('style').textContent,/display: flex/);
    if (supported) assert.equal(root.childElementCount,0);
    dom.window.close();
  }
});
const view = await read('view');
test('media overlay highlights and releases references without WeakRef', async () => {
  const block = view.slice(view.indexOf('      let lastActive'), view.indexOf('\n    }\n  }\n  async #openRenderer'));
  for (const weak of [undefined,WeakRef]) {
    const listeners = {}, classes = new Set();
    const el = {classList:{add:v=>classes.add(v),remove:v=>classes.delete(v)}};
    const host = {
      mediaOverlay:{addEventListener:(name,fn)=>listeners[name]=fn},
      resolveNavigation:()=>({index:0,anchor:()=>el}),
      renderer:{goTo:()=>Promise.resolve(),getContents:()=>[{index:0,doc:{}}]},
    };
    runInNewContext(`(function(){${block}\nthis.active = () => lastActive}).call(host)`,{host,WeakRef:weak,activeClass:'active'});
    listeners.highlight({detail:{text:'section#p'}});
    await Promise.resolve();
    assert.ok(classes.has('active')); assert.equal(host.active().deref(),el);
    listeners.unhighlight(); assert.equal(classes.size,0);assert.equal(host.active(),null);
  }
});
