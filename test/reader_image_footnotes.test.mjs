import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';

const { JSDOM } = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const sourceFor = name => readFile(new URL(`../assets/foliate-js/src/${name}`, import.meta.url), 'utf8');
const moduleURL = source => `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
const imageSource = await sourceFor('image-footnotes.js');
const imageURL = moduleURL(imageSource);
const { repairSelfReferentialNotes } = await import(moduleURL(await sourceFor('footnote-links.js')));
const { imageFootnoteText, createImageFootnoteBook } = await import(imageURL);
const { normalizeKF8Footnotes, restoreMOBI6Footnotes } = await import(moduleURL(await sourceFor('mobi-footnotes.js')));
const typographyURL = moduleURL(await sourceFor('footnote-typography.js'));
const handlerSource = (await sourceFor('footnotes.js'))
  .replace("'./image-footnotes.js'", JSON.stringify(imageURL))
  .replace("'./footnote-typography.js'", JSON.stringify(typographyURL));
const { FootnoteHandler } = await import(moduleURL(handlerSource));
const fixtureXML = await readFile(new URL('./fixtures/qqreader-footnotes.xhtml', import.meta.url), 'utf8');
const fixture = () => new JSDOM(fixtureXML, { contentType: 'application/xhtml+xml' });
const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};

test('only QQ Reader image markers with nonempty alt are annotations', () => {
  const dom = fixture(), doc = dom.window.document;
  assert.equal(imageFootnoteText(doc.getElementById('note')), '词语解释：甲 & 乙，<b>不是 HTML</b>。');
  assert.equal(imageFootnoteText(doc.getElementById('linked-note')), '链接里的图片注释。');
  for (const id of ['cover', 'empty-note', 'standard-icon', 'not-image']) {
    assert.equal(imageFootnoteText(doc.getElementById(id)), null, id);
    assert.equal(createImageFootnoteBook(doc.getElementById(id)), null, id);
  }
  assert.equal(imageFootnoteText(null), null);
  dom.window.close();
});

test('note serialization preserves literal text, Unicode and newlines without changing the source', async () => {
  const dom = fixture(), doc = dom.window.document, img = doc.getElementById('note');
  img.setAttribute('alt', '“注释” & <script>alert(1)</script>\n第二行 <img src="https://example.com/">。');
  const before = doc.documentElement.outerHTML;
  const book = createImageFootnoteBook(img);
  assert.equal(book.sections.length, 1);
  assert.equal(book.metadata.language, 'zh-CN');
  const url = book.sections[0].load();
  assert.equal(book.sections[0].load(), url, 'reuse the live note resource');
  const noteDOM = new JSDOM(await (await fetch(url)).text());
  const note = noteDOM.window.document.querySelector('aside[role="doc-footnote"]');
  assert.equal(note.textContent, img.getAttribute('alt'));
  assert.equal(note.querySelector('p').style.whiteSpace, 'pre-wrap');
  assert.equal(noteDOM.window.document.querySelectorAll('script, img, a').length, 0);
  assert.equal(book.sections[0].createDocument().body.textContent, note.textContent);
  assert.equal(doc.documentElement.outerHTML, before, 'no injected note text or CFI changes');
  book.sections[0].unload();
  await assert.rejects(fetch(url), /fetch failed/);
  const secondURL = book.sections[0].load();
  assert.notEqual(secondURL, url);
  book.destroy();
  await assert.rejects(fetch(secondURL), /fetch failed/);
  noteDOM.window.close();
  dom.window.close();
});

function handlerFixture() {
  const dom = fixture(), doc = dom.window.document, views = [];
  globalThis.document = doc;
  globalThis.getComputedStyle = dom.window.getComputedStyle.bind(dom.window);
  class NoteView extends dom.window.HTMLElement {
    async open(book) {
      this.book = book;
      this.gate = nextGate;
      nextGate = null;
      views.push(this);
      if (this.gate?.phase === 'open') await this.gate.promise;
    }
    async goTo(index) {
      this.doc = this.book.sections[index].createDocument();
      this.url = await this.book.sections[index].load();
      if (this.gate?.phase === 'load') await this.gate.promise;
      this.dispatchEvent(new dom.window.CustomEvent('load', { detail: { doc: this.doc, index } }));
      return { index };
    }
    close() {
      this.closed = true;
      this.book?.sections[0].unload?.();
    }
  }
  let nextGate = null;
  dom.window.customElements.define('foliate-view', NoteView);
  const handler = new FootnoteHandler(), events = [];
  for (const name of ['before-render', 'render']) handler.addEventListener(name, e => {
    events.push({ name, ...e.detail });
  });
  const click = img => {
    const event = new CustomEvent('image-footnote', { cancelable: true, detail: { img } });
    const result = handler.handleImage(event);
    return { event, result };
  };
  return { dom, doc, views, handler, events, click,
    delayNext(phase) { nextGate = { ...deferred(), phase }; return nextGate; },
    close() { handler.close(); dom.window.close(); delete globalThis.document; delete globalThis.getComputedStyle; },
  };
}

test('image annotations reuse popup events and capture actual source text size', async () => {
  const f = handlerFixture(), before = f.doc.body.innerHTML;
  const { event, result } = f.click(f.doc.getElementById('note'));
  assert.equal(event.defaultPrevented, true);
  await result;
  assert.deepEqual(f.events.map(e => e.name), ['before-render', 'render']);
  assert.equal(f.events[0].view, f.events[1].view);
  const rendered = f.events[1];
  assert.equal(rendered.sourceFontSize, 30);
  assert.equal(rendered.type, 'footnote');
  assert.equal(rendered.doc.body.textContent, '词语解释：甲 & 乙，<b>不是 HTML</b>。');
  assert.equal(f.doc.body.innerHTML, before);
  const url = f.views[0].url;
  f.handler.close();
  await assert.rejects(fetch(url), /fetch failed/);
  f.close();
});

test('standard noteref links still extract the referenced EPUB footnote', async () => {
  const f = handlerFixture();
  const sourceDoc = f.doc.cloneNode(true);
  const book = {
    sections: [{ load: () => 'blob:standard-footnote', createDocument: () => sourceDoc.cloneNode(true) }],
    resolveHref: () => ({ index: 0, anchor: doc => doc.getElementById('standard-note') }),
  };
  const event = new CustomEvent('link', { cancelable: true,
    detail: { a: f.doc.getElementById('standard-ref'), href: '#standard-note' } });
  await f.handler.handle(book, event);
  assert.equal(event.defaultPrevented, true);
  assert.equal(f.events[1].type, 'footnote');
  assert.equal(f.events[1].doc.body.textContent, '标准 EPUB 脚注。');
  assert.equal(f.events[1].href, '#standard-note');
  f.close();
});

test('normalized AZW3 notes open even with heuristic detection disabled and are visible in the popup', async () => {
  const f = handlerFixture();
  f.doc.body.innerHTML = '<aside id="n" type="footnote">AZW3 注释</aside><p>正文<a type="noteref" href="#n">①</a></p>';
  normalizeKF8Footnotes(f.doc);
  f.handler.detectFootnotes = false;
  const sourceDoc = f.doc.cloneNode(true);
  const book = {
    sections: [{ load: () => 'blob:azw3-note', createDocument: () => sourceDoc.cloneNode(true) }],
    resolveHref: () => ({ index: 0, anchor: doc => doc.getElementById('n') }),
  };
  const event = new CustomEvent('link', { cancelable: true,
    detail: { a: f.doc.querySelector('a'), href: '#n' } });
  await f.handler.handle(book, event);
  assert.equal(event.defaultPrevented, true);
  assert.equal(f.events[1].type, 'footnote');
  assert.equal(f.events[1].doc.body.textContent, 'AZW3 注释');
  assert.equal(f.events[1].doc.querySelector('[style*="display"]'), null, 'hidden aside wrapper removed');
  assert.equal(f.doc.getElementById('n').style.display, 'none', 'source note still hidden');
  f.close();
});

test('recovered MOBI icons use the same popup without exposing the original paragraph', async () => {
  const f = handlerFixture();
  f.doc.body.innerHTML = '<ol width="0pt"><li value="1" height="0pt" width="0pt">MOBI 注释</li></ol>'
    + '<p>正文<sup><small><img recindex="13" align="baseline" width="11" height="11"/></small></sup></p>';
  restoreMOBI6Footnotes(f.doc);
  const { event, result } = f.click(f.doc.querySelector('img'));
  await result;
  assert.equal(event.defaultPrevented, true);
  assert.equal(f.events[1].type, 'footnote');
  assert.equal(f.events[1].doc.body.textContent, 'MOBI 注释');
  assert.equal(f.events[1].doc.querySelector('[style*="display"]'), null);
  f.close();
});

for (const phase of ['open', 'load']) test(`new note cancels a stale ${phase} without reopening it`, async () => {
  const f = handlerFixture(), gate = f.delayNext(phase);
  const first = f.click(f.doc.getElementById('note')).result;
  await new Promise(resolve => setImmediate(resolve));
  const second = f.click(f.doc.getElementById('linked-note')).result;
  await second;
  gate.resolve();
  await first;
  const rendered = f.events.filter(e => e.name === 'render');
  assert.equal(rendered.length, 1);
  assert.equal(rendered[0].doc.body.textContent, '链接里的图片注释。');
  assert.equal(f.views[0].closed, true);
  f.close();
});

test('closing a pending note prevents a late popup and releases its URL', async () => {
  const f = handlerFixture(), gate = f.delayNext('load');
  const pending = f.click(f.doc.getElementById('note')).result;
  await new Promise(resolve => setImmediate(resolve));
  const url = f.views[0].url;
  f.handler.close();
  gate.resolve();
  await pending;
  assert.equal(f.events.filter(e => e.name === 'render').length, 0);
  await assert.rejects(fetch(url), /fetch failed/);
  f.close();
});

const viewSource = await sourceFor('view.js');
const imageMethod = viewSource.slice(viewSource.indexOf('  #handleImage('), viewSource.indexOf('\n  #handleClick('));
function imageView(touch) {
  const timers = [];
  const View = runInNewContext(`class View extends EventTarget {
    #emit(name, detail, cancelable) { return this.dispatchEvent(new CustomEvent(name, {detail, cancelable})); }
    install(doc) { this.#handleImage(doc); }
    ${imageMethod}
  }; View`, { EventTarget, CustomEvent, imageFootnoteText,
    window: touch ? { ontouchstart: null } : {},
    setTimeout: callback => { timers.push(callback); return timers.length; },
    clearTimeout() {},
  });
  return { view: new View(), timers };
}

for (const touch of [false, true]) test(`scanned document ${touch ? 'touch' : 'mouse'} images keep page taps, never preview`, () => {
  const dom = fixture(), doc = dom.window.document, {view, timers} = imageView(touch);
  view.scannedImageDocument = true;
  const actions = [];
  view.addEventListener('click-image', () => actions.push('preview'));
  view.addEventListener('image-footnote', () => actions.push('note'));
  view.install(doc);
  let clicks = 0;
  doc.addEventListener('click', () => clicks++);
  for (const img of doc.querySelectorAll('img')) {
    img.dispatchEvent(new dom.window.Event('touchstart', {bubbles:true}));
    img.dispatchEvent(new dom.window.MouseEvent('click', {bubbles:true,cancelable:true}));
    const menu = new dom.window.Event('contextmenu', {bubbles:true,cancelable:true});
    img.dispatchEvent(menu);
    assert.equal(menu.defaultPrevented, true);
  }
  assert.equal(clicks, doc.querySelectorAll('img').length);
  assert.equal(timers.length, 0);
  assert.deepEqual(actions, []);
  dom.window.close();
});

for (const touch of [false, true]) test(`${touch ? 'mobile' : 'desktop'} note click opens annotation, never preview or reader menu`, () => {
  const dom = fixture(), doc = dom.window.document, { view, timers } = imageView(touch);
  const notes = [], previews = [];
  let bubbled = 0;
  view.addEventListener('image-footnote', e => notes.push(e.detail.img.id));
  view.addEventListener('click-image', e => previews.push(e.detail.img.id));
  doc.addEventListener('click', () => bubbled++);
  view.install(doc);
  for (const id of ['note', 'linked-note']) {
    const img = doc.getElementById(id);
    img.dispatchEvent(new dom.window.Event('touchstart', { bubbles: true }));
    const event = new dom.window.MouseEvent('click', { bubbles: true, cancelable: true });
    img.dispatchEvent(event);
    assert.equal(event.defaultPrevented, true);
    assert.equal(img.draggable, false);
  }
  assert.deepEqual(notes, ['note', 'linked-note']);
  assert.deepEqual(previews, []);
  assert.equal(timers.length, 0, 'no long-press preview timer for annotation icons');
  assert.equal(bubbled, 0);
  const cover = doc.getElementById('cover');
  if (touch) {
    cover.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
    assert.equal(bubbled, 1, 'ordinary mobile short taps retain page/menu behavior');
    cover.dispatchEvent(new dom.window.Event('touchstart'));
    timers[0]();
  } else cover.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true }));
  assert.deepEqual(previews, ['cover']);
  dom.window.close();
});

test('TTS reads正文 only, not the annotation text stored in alt', async () => {
  const { TTS } = await import(moduleURL(await sourceFor('tts.js')));
  const dom = fixture(), doc = dom.window.document;
  globalThis.document = doc;
  globalThis.NodeFilter = dom.window.NodeFilter;
  globalThis.Range = dom.window.Range;
  const tts = new TTS(doc, null, () => null), text = [];
  for (let sentence = tts.start(); sentence != null; sentence = tts.next()) text.push(sentence);
  assert.match(text.join(''), /第一段正文/);
  assert.match(text.join(''), /正文继续/);
  assert.doesNotMatch(text.join(''), /词语解释|链接里的图片注释|普通封面说明|标准 EPUB 脚注/);
  dom.window.close();
  delete globalThis.document;
  delete globalThis.NodeFilter;
  delete globalThis.Range;
});

test('book wiring uses the existing popup and closes its renderer/resources', async () => {
  const source = await sourceFor('book.js');
  assert.match(source, /view\.addEventListener\('image-footnote', e =>\s+this\.#footnoteHandler\.handleImage\(e\)/);
  assert.match(source, /closeFootnote\(\) \{\s+this\.#footnoteHandler\.close\(\)/);
  const close = source.slice(source.indexOf('const closeFootnote ='), source.indexOf("footnoteDialog.addEventListener('click'"));
  assert.match(close, /reader\.closeFootnote\(\)/);
  assert.match(close, /delete globalThis\.footnoteSelection/);
});

test('real View.close is safe before the asynchronous renderer import completes', () => {
  const closeMethod = viewSource.slice(viewSource.indexOf('  close() {'), viewSource.indexOf('\n  goToTextStart()'));
  const View = runInNewContext(`class View {
    #sectionProgress; #tocProgress; #pageProgress; #searchResults; #translator;
    #lastCfi; #lastChapterLocation;
    #rendererSwitchGeneration = 0; #imageBook;
    history = {clear() {}};
    initTTS() { if (!this.renderer) throw Error('renderer is not ready'); }
    clearSearch() {}
    ${closeMethod}
  }; View`);
  assert.doesNotThrow(() => new View().close());
});


test('self-pointing converted EPUB note pairs open the note and restore return links without moving text', async () => {
  const f = handlerFixture();
  f.doc.body.innerHTML = '<p>正文<sup style="vertical-align:super"><a id="Chapter7.xhtml_note_1" href="#Chapter7.xhtml_note_1">[</a><a href="#Chapter7.xhtml_note_1">†</a><a href="#Chapter7.xhtml_note_1">]</a></sup>继续正文</p>'
    + '<p><span id="Chapter7.xhtml_noteBack_1"><a href="#Chapter7.xhtml_noteBack_1">[*]</a>真正的<b>注释</b>。</span></p>';
  const text = f.doc.body.textContent, nodes = [...f.doc.querySelectorAll('*')];
  repairSelfReferentialNotes(f.doc);
  assert.equal(f.doc.body.textContent, text);
  assert.deepEqual([...f.doc.querySelectorAll('*')], nodes);
  assert.equal(f.doc.querySelector('span a').getAttribute('href'), '#Chapter7.xhtml_note_1');
  const repaired = f.doc.body.innerHTML;
  repairSelfReferentialNotes(f.doc);
  assert.equal(f.doc.body.innerHTML, repaired, 'idempotent on reused chapter documents');
  const sourceDoc = f.doc.cloneNode(true);
  const book = {
    sections: [{load: () => 'blob:converted-note', createDocument: () => sourceDoc.cloneNode(true)}],
    resolveHref: href => ({index: 0, anchor: doc => doc.getElementById(href.split('#')[1])}),
  };
  for (const a of f.doc.querySelectorAll('sup a')) {
    const event = new CustomEvent('link', {cancelable: true, detail: {a, href: a.getAttribute('href')}});
    await f.handler.handle(book, event);
    assert.equal(event.defaultPrevented, true);
    assert.equal(f.events.at(-1).doc.body.textContent, '[*]真正的注释。');
    assert.ok(f.events.at(-1).doc.querySelector('b'), 'preserve note markup');
    f.handler.close();
  }
  assert.equal(f.doc.body.innerHTML, repaired);
  f.close();
});

for (const variant of ['missing pair', 'duplicate ID', 'normal note', 'ordinary link', 'unrelated return', 'nested target']) {
  test(`self-pointing note repair leaves ${variant} unchanged`, () => {
    const dom = fixture(), doc = dom.window.document;
    let html = '<p><sup><a id="c_note_1" href="#c_note_1">*</a></sup></p><p><span id="c_noteBack_1"><a href="#c_noteBack_1">*</a>解释</span></p>';
    if (variant === 'missing pair') html = html.split('</p>')[0] + '</p>';
    if (variant === 'duplicate ID') html += '<span id="c_noteBack_1">其他内容</span>';
    if (variant === 'normal note') html = html.replace('href="#c_note_1"', 'href="#c_noteBack_1"').replace('id="c_noteBack_1"><a href="#c_noteBack_1"', 'id="c_noteBack_1"><a href="#c_note_1"');
    if (variant === 'ordinary link') html = html.replace('>*</a></sup>', '>跳到章节</a></sup>');
    if (variant === 'unrelated return') html += '<a href="#c_noteBack_1">跳到章节</a>';
    if (variant === 'nested target') html = '<span id="c_noteBack_1"><a id="c_note_1" href="#c_note_1">*</a><a href="#c_noteBack_1">*</a>解释</span>';
    doc.body.innerHTML = html;
    const before = doc.body.innerHTML;
    repairSelfReferentialNotes(doc);
    assert.equal(doc.body.innerHTML, before);
    dom.window.close();
  });
}
