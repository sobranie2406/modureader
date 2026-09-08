import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
const requireDOM = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`);
const { JSDOM } = requireDOM('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/quick-mark.js', import.meta.url), 'utf8');
const { installQuickMark, rangeBetween, caretAt } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

function fixture() {
  const dom = new JSDOM('<p>一二三四五六七八九十</p><p>第二段内容</p>');
  const doc = dom.window.document;
  const text = doc.querySelector('p').firstChild;
  const other = doc.querySelectorAll('p')[1].firstChild;
  dom.window.Range.prototype.getClientRects = () => [{left: 0, right: 200, top: 0, bottom: 40, width: 200, height: 40}];
  doc.caretRangeFromPoint = (x, y) => {
    const r = doc.createRange();
    const node = y > 20 ? other : text;
    r.setStart(node, Math.min(node.length, Math.max(0, Math.floor(x / 10))));
    r.collapse(true); return r;
  };
  let saves = [], taps = 0, pageTurns = 0, errors = 0;
  const marker = installQuickMark(doc, {
    onCommit: async r => saves.push(r.toString()), onTap: () => taps++, onError: () => errors++,
  });
  doc.addEventListener('touchmove', () => pageTurns++);
  function touch(type, x, y = 10, count = 1) {
    const point = {identifier: 1, clientX: x, clientY: y};
    const e = new dom.window.Event(type, {bubbles: true, cancelable: true});
    Object.defineProperties(e, {
      touches: {value: type === 'touchend' || type === 'touchcancel' ? [] : Array(count).fill(point)},
      changedTouches: {value: [point]},
    });
    doc.querySelector('p').dispatchEvent(e);
    return e;
  }
  return {dom, doc, text, other, marker, touch, saves,
    get taps() { return taps; }, get pageTurns() { return pageTurns; }, get errors() { return errors; }};
}
const settle = () => new Promise(resolve => setImmediate(resolve));

test('disabled mode leaves scrolling alone and creates no note', async () => {
  const f = fixture();
  assert.equal(f.touch('touchstart', 0).defaultPrevented, false);
  f.touch('touchmove', 50); f.touch('touchend', 50);
  await settle();
  assert.equal(f.pageTurns, 1); assert.deepEqual(f.saves, []);
});
test('a single drag saves only on release and never opens native selection or turns pages', async () => {
  const f = fixture(); f.marker.setEnabled(true);
  assert.equal(f.touch('touchstart', 0).defaultPrevented, true);
  f.touch('touchmove', 50);
  assert.deepEqual(f.saves, []);
  assert.equal(f.doc.getSelection().rangeCount, 0);
  assert.ok(f.doc.querySelector('[data-modu-quick-mark="preview"]'));
  f.touch('touchend', 50); await settle();
  assert.deepEqual(f.saves, ['一二三四五']);
  assert.equal(f.pageTurns, 0);
  assert.equal(f.doc.querySelector('[data-modu-quick-mark="preview"]'), null);
});
test('reverse and cross-paragraph ranges preserve DOM order', () => {
  const f = fixture();
  assert.equal(rangeBetween(f.doc, {node:f.text,offset:5}, {node:f.text,offset:1}).toString(), '二三四五');
  assert.equal(rangeBetween(f.doc, {node:f.other,offset:2}, {node:f.text,offset:8}).toString(), '九十第二');
});
test('taps open controls without accidental highlights', async () => {
  const f = fixture(); f.marker.setEnabled(true);
  f.touch('touchstart', 10); f.touch('touchend', 10); await settle();
  assert.equal(f.taps, 1); assert.deepEqual(f.saves, []);
});
test('cancel, multitouch and turning the mode off discard unfinished strokes', async () => {
  for (const action of ['cancel', 'multi', 'off', 'navigation']) {
    const f = fixture(); f.marker.setEnabled(true);
    f.touch('touchstart', 0); f.touch('touchmove', 50);
    if (action === 'cancel') f.touch('touchcancel', 50);
    if (action === 'multi') f.touch('touchstart', 50, 10, 2);
    if (action === 'off') f.marker.setEnabled(false);
    if (action === 'navigation') f.marker.cancel();
    f.touch('touchend', 50); await settle();
    assert.deepEqual(f.saves, [], action);
    assert.equal(f.doc.querySelector('[data-modu-quick-mark="preview"]'), null);
  }
});
test('turning mode off restores normal scrolling and removes injected styles', () => {
  const f = fixture(); f.marker.setEnabled(true); f.marker.setEnabled(false);
  assert.equal(f.doc.documentElement.dataset.moduQuickMark, undefined);
  assert.equal(f.doc.querySelector('style'), null);
  f.touch('touchstart', 0); f.touch('touchmove', 50);
  assert.equal(f.pageTurns, 1);
});
test('a dynamic text replacement during a stroke cannot save a stale range', async () => {
  const f = fixture(); f.marker.setEnabled(true);
  f.touch('touchstart', 0); f.touch('touchmove', 30);
  f.doc.querySelector('p').textContent = '更新的正文';
  f.touch('touchmove', 50); f.touch('touchend', 50); await settle();
  assert.deepEqual(f.saves, []);
  assert.equal(f.doc.querySelector('[data-modu-quick-mark="preview"]'), null);
});
test('both caret APIs work; page margins and controls cannot start a mark', () => {
  const f = fixture();
  assert.equal(caretAt(f.doc, 300, 10, true), null);
  f.doc.caretPositionFromPoint = () => ({offsetNode: f.text, offset: 3});
  assert.equal(caretAt(f.doc, 20, 10).offset, 3);
  f.doc.querySelector('p').setAttribute('contenteditable', 'true');
  assert.equal(caretAt(f.doc, 20, 10), null);
});
