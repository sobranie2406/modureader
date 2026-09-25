import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const {JSDOM} = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/reader-font-ready.js', import.meta.url), 'utf8');
const {waitForReaderFonts, clearReaderFontFallback} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

function fixture() {
  const dom = new JSDOM(`<html><head><style>.broken{font-family:Missing!important}</style></head><body style="writing-mode:vertical-rl"><p class="broken" style="font-size:24px;line-height:1.6;font-weight:bold;color:red">中文正文</p><p style="font-family:Good">正常字体</p><p class="broken" style="font-family:Missing!important;font-style:italic">English</p></body></html>`, {pretendToBeVisual:true});
  const doc = dom.window.document;
  for (const el of doc.querySelectorAll('p')) el.getClientRects = () => [{}];
  Object.defineProperty(doc, 'fonts', {value:{load:async font => {
    if (font.includes('Missing')) throw Error('failed font');
    return [];
  }}});
  return {dom,doc,paragraphs:[...doc.querySelectorAll('p')]};
}

test('fallback changes only failed text families, retaining typography, text nodes and CFI ranges', async () => {
  const {dom,doc,paragraphs:[bad,good,italic]} = fixture();
  const text = bad.firstChild;
  const range = doc.createRange(); range.setStart(text,1); range.setEnd(text,3);
  assert.equal(await waitForReaderFonts(doc),true);
  assert.equal(bad.style.fontFamily,'serif');
  assert.equal(bad.style.getPropertyPriority('font-family'),'important');
  assert.equal(good.style.fontFamily,'Good');
  assert.equal(italic.style.fontFamily,'serif');
  assert.equal(italic.style.fontStyle,'italic');
  assert.equal(bad.style.fontSize,'24px');
  assert.equal(bad.style.lineHeight,'1.6');
  assert.equal(bad.style.fontWeight,'bold');
  assert.equal(bad.style.color,'red');
  assert.equal(doc.body.style.writingMode,'vertical-rl');
  assert.equal(bad.firstChild,text);
  assert.equal(range.toString(),'文正');
  dom.window.close();
});

test('a new font choice restores original inline styles and can load normally', async () => {
  const {dom,doc,paragraphs:[bad,good,italic]} = fixture();
  await waitForReaderFonts(doc);
  // Repeated readiness checks must not overwrite the saved original style.
  await waitForReaderFonts(doc);
  clearReaderFontFallback(doc);
  assert.equal(bad.style.fontFamily,'');
  assert.equal(italic.style.fontFamily,'Missing');
  assert.equal(italic.style.getPropertyPriority('font-family'),'important');
  bad.className=''; italic.className='';
  bad.style.fontFamily='NewFont'; italic.style.fontFamily='NewFont';
  assert.equal(await waitForReaderFonts(doc),true);
  assert.equal(bad.style.fontFamily,'NewFont');
  assert.equal(good.style.fontFamily,'Good');
  dom.window.close();
});

test('new styles invalidate a pending failure from the old font choice', async () => {
  const {dom,doc,paragraphs:[bad]} = fixture();
  let fail;
  const failure = new Promise((_,reject)=>fail=reject);
  doc.fonts.load = () => failure;
  const pending = waitForReaderFonts(doc);
  clearReaderFontFallback(doc);
  bad.style.fontFamily='NewFont';
  doc.fonts.load = async () => [];
  fail(Error('old font failed'));
  assert.equal(await pending,true, 'new font selection must not fail the pending chapter');
  assert.equal(bad.style.fontFamily,'NewFont');
  dom.window.close();
});

test('overlapping waits for the same document do not cancel each other', async () => {
  const {dom,doc} = fixture();
  const results = await Promise.all([waitForReaderFonts(doc),waitForReaderFonts(doc)]);
  assert.deepEqual(results,[true,true]);
  dom.window.close();
});

test('system-only and fully loaded fonts skip whole-chapter text discovery', async () => {
  for (const faces of [[], [{status:'loaded'}]]) {
    let layouts = 0;
    const fonts = Object.assign(faces, {status:'loaded', load:()=>{throw Error('redundant font load')}});
    const doc = {fonts, body:{getBoundingClientRect(){layouts++}}, createTreeWalker(){throw Error('redundant full text scan')}};
    assert.equal(await waitForReaderFonts(doc), true);
    assert.equal(layouts, 1);
    const cancelled = new AbortController(); cancelled.abort();
    assert.equal(await waitForReaderFonts(doc, cancelled.signal), false);
  }
});

test('ready font groups avoid repeated load calls, but failed groups still fall back', async () => {
  const {dom,doc,paragraphs:[bad,good]} = fixture();
  let requested = [];
  doc.fonts.check = font => !font.includes('Missing');
  doc.fonts.load = async font => {requested.push(font); throw Error('failed')};
  assert.equal(await waitForReaderFonts(doc), true);
  assert.ok(requested.length > 0);
  assert.ok(requested.every(font=>font.includes('Missing')));
  assert.equal(bad.style.fontFamily,'serif');
  assert.equal(good.style.fontFamily,'Good');
  dom.window.close();
});

test('unloaded and broken faces do not take the loaded-font fast path', async () => {
  const {dom, doc, paragraphs:[bad]} = fixture();
  doc.fonts.status = 'loaded';
  doc.fonts[Symbol.iterator] = function*(){yield {status:'error'};yield {status:'unloaded'}};
  assert.equal(await waitForReaderFonts(doc), true);
  assert.equal(bad.style.fontFamily,'serif');
  dom.window.close();
});
