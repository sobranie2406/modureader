import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
const { JSDOM } = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const sourceFor = name => readFile(new URL(`../assets/foliate-js/src/${name}`, import.meta.url), 'utf8');
const moduleURL = source => `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
const { normalizeKF8Footnotes, restoreMOBI6Footnotes } = await import(moduleURL(await sourceFor('mobi-footnotes.js')));
const { imageFootnoteText, createImageFootnoteBook } = await import(moduleURL(await sourceFor('image-footnotes.js')));
const { TTS } = await import(moduleURL(await sourceFor('tts.js')));
const ns = 'http://www.idpf.org/2007/ops';
const note = text => `<ol width="0pt"><li value="1" height="0pt" width="0pt">${text}</li></ol>`;
const icon = '<sup><small><img recindex="00013" align="baseline" width="11" height="11"></small></sup>';

for (const contentType of ['text/html', 'application/xhtml+xml']) {
  test(`KF8 recognizes stripped note types and survives serialization: ${contentType}`, () => {
    const dom = new JSDOM(`<html xmlns="http://www.w3.org/1999/xhtml"><head></head><body>
      <aside id="n" type="footnote">注释</aside><p>正文<a type="noteref" href="#n">①</a></p>
      <a type="text/html" href="#chapter">章节</a><aside type="sidebar">旁栏</aside>
      </body></html>`, { contentType });
    const doc = dom.window.document, nodes = [...doc.body.querySelectorAll('*')];
    normalizeKF8Footnotes(doc);
    assert.equal(doc.getElementById('n').getAttributeNS(ns, 'type'), 'footnote');
    assert.equal(doc.querySelector('a').getAttribute('role'), 'doc-noteref');
    assert.equal(doc.getElementById('n').style.display, 'none');
    assert.equal(doc.getElementById('n').style.getPropertyPriority('display'), 'important');
    assert.equal(doc.querySelector('a[type="text/html"]').hasAttribute('role'), false);
    assert.equal(doc.querySelector('aside[type="sidebar"]').style.display, '');
    assert.deepEqual([...doc.body.querySelectorAll('*')], nodes, 'CFI node positions unchanged');
    const before = doc.body.innerHTML;
    normalizeKF8Footnotes(doc);
    assert.equal(doc.body.innerHTML, before, 'idempotent');
    const rendered = new JSDOM(new dom.window.XMLSerializer().serializeToString(doc), { contentType });
    assert.equal(rendered.window.document.getElementById('n').getAttribute('role'), 'doc-footnote');
    assert.equal(rendered.window.document.getElementById('n').style.display, 'none');
    rendered.window.close(); dom.window.close();
  });
}

test('existing namespaced EPUB notes and ordinary content remain byte-for-byte unchanged', () => {
  const dom = new JSDOM(`<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="${ns}"><head/><body>
    <aside id="note" epub:type="footnote" type="sidebar">注释</aside>
    <p><a epub:type="noteref" href="#note" type="text/html">①</a>正文</p>
    <ol><li>正常列表</li></ol><p>图标${icon}</p>
    </body></html>`.replace(/<img ([^>]+)>/, '<img $1/>'), { contentType: 'application/xhtml+xml' });
  const doc = dom.window.document, before = doc.documentElement.outerHTML;
  normalizeKF8Footnotes(doc); restoreMOBI6Footnotes(doc);
  assert.equal(doc.documentElement.outerHTML, before);
  dom.window.close();
});

test('KF8 uses explicit embedded image notes instead of stale targets, never ordinary alt text', () => {
  const dom = new JSDOM(`<aside id="wrong" type="footnote">错误链接的注释</aside>
    <a type="noteref" href="#wrong"><img id="explicit" class="epub-footnote1" alt="正确注释" zy-footnote="正确注释"></a>
    <a type="noteref" href="#wrong"><img id="mismatch" class="epub-footnote" alt="描述" zy-footnote="注释"></a>
    <a type="noteref" href="#wrong"><img id="alt-only" class="epub-footnote" alt="描述"></a>
    <a type="text/html" href="#wrong"><img id="ordinary" class="epub-footnote" alt="描述" zy-footnote="描述"></a>`);
  const doc = dom.window.document;
  normalizeKF8Footnotes(doc);
  assert.equal(imageFootnoteText(doc.getElementById('explicit')), '正确注释');
  assert.equal(doc.getElementById('explicit').parentElement.getAttribute('href'), '#wrong');
  for (const id of ['mismatch', 'alt-only', 'ordinary']) assert.equal(imageFootnoteText(doc.getElementById(id)), null);
  dom.window.close();
});

test('legacy MOBI pairs consecutive note lists with icons, preserving nodes, text and popup escaping', async () => {
  const dom = new JSDOM(`${note('注释甲 &amp; &lt;script&gt;')}${note('注释乙')}<p>正文甲${icon}正文乙${icon}</p>`);
  const doc = dom.window.document;
  const walker = doc.createTreeWalker(doc.body), nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  const text = doc.body.textContent;
  restoreMOBI6Footnotes(doc);
  const images = [...doc.querySelectorAll('img')];
  assert.deepEqual(images.map(imageFootnoteText), ['注释甲 & <script>', '注释乙']);
  assert.equal(doc.body.textContent, text);
  walker.currentNode = doc.body;
  const after = []; while (walker.nextNode()) after.push(walker.currentNode);
  assert.deepEqual(after, nodes);
  for (const ol of doc.querySelectorAll('ol')) {
    assert.equal(ol.style.display, 'none');
    assert.equal(ol.getAttribute('role'), 'doc-footnote');
  }
  const before = doc.body.innerHTML;
  restoreMOBI6Footnotes(doc);
  assert.equal(doc.body.innerHTML, before);
  const book = createImageFootnoteBook(images[0]);
  const popup = book.sections[0].createDocument();
  assert.equal(popup.body.textContent, '注释甲 & <script>');
  assert.equal(popup.querySelector('script'), null);
  assert.equal(popup.querySelector('aside').style.display, '');
  const url = book.sections[0].load();
  assert.match(await (await fetch(url)).text(), /&lt;script&gt;/);
  book.destroy(); dom.window.close();
});

for (const [name, html] of [
  ['missing icon', `${note('注释')}<p>正文</p>`],
  ['count mismatch', `${note('注释')}<p>正文${icon}${icon}</p>`],
  ['ordinary list', `<ol><li>项目</li></ol><p>正文${icon}</p>`],
  ['multiple list items', `<ol width="0pt"><li value="1" height="0pt" width="0pt">项目</li><li>项目</li></ol><p>${icon}</p>`],
  ['body text between', `${note('注释')}不可隐藏的正文<p>${icon}</p>`],
  ['body text outside list item', `${note('注释').replace('<ol width="0pt">', '<ol width="0pt">正文')}<p>${icon}</p>`],
  ['partially recognizable list group', `<ol><li>未知项目</li></ol>${note('注释')}<p>${icon}</p>`],
  ['intervening block', `${note('注释')}<div>正文</div><p>${icon}</p>`],
  ['linked icon', `${note('注释')}<p><a href="filepos:123">${icon}</a></p>`],
  ['large illustration', `${note('注释')}<p>${icon.replaceAll('"11"', '"100"')}</p>`],
  ['superscript text', `${note('注释')}<p>${icon.replace('<sup>', '<sup>公式')}</p>`],
  ['existing note link', `${note('<a href="filepos:123">注释</a>')}<p>${icon}</p>`],
  ['empty note', `${note(' ')}<p>${icon}</p>`],
]) test(`ambiguous MOBI remains visible and unchanged: ${name}`, () => {
  const dom = new JSDOM(html), doc = dom.window.document, before = doc.body.innerHTML;
  restoreMOBI6Footnotes(doc);
  assert.equal(doc.body.innerHTML, before);
  dom.window.close();
});

test('TTS reads body text but not restored MOBI or KF8 notes', () => {
  const dom = new JSDOM(`${note('不应朗读甲')}<p>保留正文甲${icon}</p>
    <aside type="footnote" id="n">不应朗读乙</aside><p>保留正文乙<a type="noteref" href="#n">①</a></p>`);
  const doc = dom.window.document;
  restoreMOBI6Footnotes(doc); normalizeKF8Footnotes(doc);
  for (const key of ['document', 'NodeFilter', 'Range']) globalThis[key] = dom.window[key];
  try {
    const tts = new TTS(doc, null, () => null);
    const speech = [];
    for (let text = tts.start(); text; text = tts.next()) speech.push(text);
    assert.match(speech.join(''), /保留正文甲/);
    assert.match(speech.join(''), /保留正文乙/);
    assert.doesNotMatch(speech.join(''), /不应朗读|①/);
  } finally {
    for (const key of ['document', 'NodeFilter', 'Range']) delete globalThis[key];
    dom.window.close();
  }
});
