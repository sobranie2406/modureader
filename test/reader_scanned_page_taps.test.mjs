import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {runInNewContext} from 'node:vm';

const {JSDOM} = createRequire(`${process.env.MODU_JSDOM_ROOT || '/private/tmp/modu-119-js-tests'}/package.json`)('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/view.js', import.meta.url), 'utf8');
// Execute the real link/image/click handlers together. Image-only tests miss
// anchors swallowing the event before it reaches the reader's document handler.
const handlers = source.slice(source.indexOf('  #handleLinks('), source.indexOf('  async addAnnotation('));
function harness({scanned = false, touch = false, html = '<img data-document-base>'} = {}) {
  const dom = new JSDOM(html), doc = dom.window.document, events = [], timers = [];
  const View = runInNewContext(`class View {
    #emit(type, detail) { emit(type, detail); return false; }
    install(doc) { this.#handleLinks(doc, 0); this.#handleClick(doc); this.#handleImage(doc); }
    ${handlers}
  }; View`, {
    window: {innerWidth:800, innerHeight:600, isFootNoteOpen:() => false,
      ...(touch ? {ontouchstart:null} : {})},
    imageFootnoteText:() => null, emit:(type, detail) => events.push({type, detail}),
    setTimeout:callback => timers.push(callback), clearTimeout() {}, console,
  });
  const view = new View();
  view.book = {sections:[{}]}; view.scannedImageDocument = scanned;
  return {dom, doc, events, timers, view,
    install:() => view.install(doc),
    click(target, x = 700, y = 300) {
      const event = new dom.window.MouseEvent('click', {bubbles:true, cancelable:true, clientX:x, clientY:y});
      target.dispatchEvent(event); return event;
    }, close:() => dom.window.close()};
}

for (const touch of [false, true]) {
  for (const scanned of [false, true]) {
    test(`${touch ? 'touch' : 'mouse'} ${scanned ? 'scanned ebook' : 'PDF'} raster forwards each page/menu tap exactly once`, () => {
      const h = harness({touch, scanned});
      try {
        h.install();
        const img = h.doc.querySelector('img');
        img.dispatchEvent(new h.dom.window.Event('touchstart', {bubbles:true}));
        img.dispatchEvent(new h.dom.window.Event('touchend', {bubbles:true}));
        for (const x of [60, 400, 740]) h.click(img, x);
        assert.deepEqual(h.events.map(e => e.type), ['click-view','click-view','click-view']);
        assert.deepEqual(h.events.map(e => e.detail.x), [60,400,740]);
        assert.equal(h.timers.length, 0, 'page rasters never install picture long-press preview');
        assert.equal(img.draggable, false);
      } finally {h.close()}
    });
  }
  for (const image of ['<img>', '<svg><image href="page.jpg" /></svg>']) {
    test(`${touch ? 'touch' : 'mouse'} scanned image inside a publisher link turns pages instead of navigating`, () => {
      const h = harness({touch, scanned:true, html:`<a href="page.jpg">${image}</a>`});
      try {
        h.install();
        const e = h.click(h.doc.querySelector('img, image'));
        assert.equal(e.defaultPrevented, true, 'disable the native hyperlink too');
        assert.deepEqual(h.events.map(e => e.type), ['click-view']);
      } finally {h.close()}
    });
  }
}

test('cropped/rotated page coordinates use the renderer transform before hit testing', () => {
  const h = harness();
  try {
    h.doc.position = 'center'; h.doc.pdfRegion = true; h.doc.scale = .5;
    h.doc.pdfClientPoint = (x, y) => ({x:800 - y * .5, y:x * .5});
    h.install(); h.click(h.doc.querySelector('img'), 200, 100);
    assert.equal(h.events.length, 1);
    assert.equal(h.events[0].type, 'click-view');
    assert.equal(h.events[0].detail.x, 750); assert.equal(h.events[0].detail.y, 100);
  } finally {h.close()}
});

test('selected text and gesture-consumed clicks do not turn the scanned page', () => {
  const h = harness({scanned:true, html:'<img data-document-base><p>Selectable OCR text</p>'});
  try {
    h.install();
    const range = h.doc.createRange(); range.selectNodeContents(h.doc.querySelector('p'));
    h.doc.getSelection().addRange(range); h.click(h.doc.querySelector('img'));
    assert.equal(h.events.length, 0);
    h.doc.getSelection().removeAllRanges();
    h.doc.addEventListener('click', e => {e.preventDefault(); e.stopImmediatePropagation()}, true);
    h.click(h.doc.querySelector('img')); assert.equal(h.events.length, 0);
  } finally {h.close()}
});

test('ordinary book pictures still open preview; text links and footnote links still navigate', () => {
  for (const scanned of [false, true]) {
    const h = harness({scanned, html:'<img id="picture"><a href="#note">Footnote</a>'});
    try {
      h.install();
      if (!scanned) {
        h.click(h.doc.querySelector('img'));
        assert.equal(h.events.pop().type, 'click-image');
      }
      h.click(h.doc.querySelector('a'));
      assert.deepEqual(h.events.map(e => e.type), ['link']);
    } finally {h.close()}
  }
  const h = harness({scanned:true, html:'<a href="image.jpg"><img></a>'});
  try {
    h.doc.__isFootNote = true; h.install(); h.click(h.doc.querySelector('img'));
    assert.deepEqual(h.events.map(e => e.type), ['link']);
  } finally {h.close()}
});

test('PDF loader explicitly identifies its generated page raster', async () => {
  const pdf = await readFile(new URL('../assets/foliate-js/src/pdf.js', import.meta.url), 'utf8');
  assert.match(pdf, /<img data-document-base src="\$\{src\}"[^>]*>/);
});
