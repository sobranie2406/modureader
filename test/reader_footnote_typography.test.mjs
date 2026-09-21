import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const {JSDOM} = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/footnote-typography.js', import.meta.url), 'utf8');
const {sourceBodyFontSize,applyFootnoteTypography} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

test('source is paragraph text, not small superscript or root/preference size', () => {
  const dom = new JSDOM('<body style="font-size:16px"><p style="font-size:30px">这是实际正文<sup style="font-size:12px"><a id="ref" style="font-size:10px">[26]</a></sup></p></body>');
  const doc = dom.window.document;
  const before = doc.body.innerHTML;
  assert.equal(sourceBodyFontSize(doc.querySelector('#ref')),30);
  assert.equal(doc.body.innerHTML,before,'source book must not be edited');
  dom.window.close();
});
test('text spans determine actual size; headings, hidden text and raised markers are excluded', () => {
  const dom = new JSDOM('<body style="font-size:16px"><p style="font-size:20px"><span style="font-size:28px">普通正文文字普通正文文字普通正文文字</span><span style="font-size:60px">大</span><span hidden style="font-size:99px">隐藏内容很多很多很多很多很多很多很多很多</span><span style="vertical-align:super;font-size:9px">1234567890</span><a id="ref" style="font-size:8px">[1]</a></p></body>');
  assert.equal(sourceBodyFontSize(dom.window.document.querySelector('#ref')),28);
  dom.window.close();
});
test('standalone marker falls back to ordinary nearby text, never a heading', () => {
  const dom = new JSDOM('<body style="font-size:16px"><h1 style="font-size:80px">很长很长的章节标题</h1><p style="font-size:26px">正文</p><p style="font-size:8px"><a id="ref">[1]</a></p></body>');
  assert.equal(sourceBodyFontSize(dom.window.document.querySelector('#ref')),26);
  dom.window.close();
});
test('normalization overrides nested and inline-important sizes, preserving emphasis and superscripts', () => {
  const dom = new JSDOM('<body><div style="font-size:50%"><p style="font-size:10px!important"><span style="font-size:.5em"><i style="font-style:italic">注释</i><b style="font-weight:700">重点</b></span><sup><span>2</span></sup></p><math><mi>x</mi></math></div></body>');
  const doc = dom.window.document;
  applyFootnoteTypography(doc,30);
  for (const selector of ['html','body','div','p','i','b']) {
    const el=doc.querySelector(selector);
    assert.equal(el.style.fontSize,'24px');
    assert.equal(el.style.getPropertyPriority('font-size'),'important');
  }
  assert.equal(doc.querySelector('sup span').style.fontSize,'18px');
  assert.equal(doc.querySelector('i').style.fontStyle,'italic');
  assert.equal(doc.querySelector('b').style.fontWeight,'700');
  assert.equal(doc.querySelector('mi').getAttribute('style'),null);
  const link=doc.createElement('a');doc.querySelector('p').append(link);
  assert.equal(sourceBodyFontSize(link),30,'nested notes retain original baseline');
  applyFootnoteTypography(doc,30);
  assert.equal(doc.querySelector('p').style.fontSize,'24px','repeat application does not shrink');
  dom.window.close();
});
test('each note captures the source before asynchronous cross-chapter lookup', async () => {
  const handler = await readFile(new URL('../assets/foliate-js/src/footnotes.js', import.meta.url),'utf8');
  assert.equal((handler.match(/const sourceFontSize = sourceBodyFontSize\(a\)/g)||[]).length,2);
  assert.match(handler,/detail: \{ view, sourceFontSize \}/);
  assert.match(handler,/target: el, sourceFontSize/);
  const book=await readFile(new URL('../assets/foliate-js/src/book.js',import.meta.url),'utf8');
  assert.ok(book.indexOf('applyFootnoteTypography(doc,')<book.indexOf('footnoteSizing = attachFootnoteSizing'));
});
