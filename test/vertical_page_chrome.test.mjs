import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('../assets/foliate-js/src/vertical-page-chrome.js', import.meta.url), 'utf8');
const { applyVerticalPageChrome } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
function renderer() {
  const attrs = new Map();
  return { style: {}, writingMode: 'vertical-rl',
    getAttribute: key => attrs.get(key), setAttribute: (key, value) => attrs.set(key, value) };
}
test('vertical page reserves physical gutters in both scroll and paginated modes', () => {
  const r = renderer();
  for (const flow of ['scrolled','paginated']) {
    r.setAttribute('flow', flow);
    assert.equal(applyVerticalPageChrome(r, {writingMode:'vertical-rl',
      verticalPageInsets:{top:42, right:44, bottom:46, left:44}}), true);
    assert.equal(r.style.padding, '42px 44px 46px 44px');
    assert.equal(r.getAttribute('top-margin'), '0px');
    assert.equal(r.getAttribute('flow'), flow);
  }
});
test('horizontal mode restores original margins and never inherits vertical padding', () => {
  const r = renderer();
  applyVerticalPageChrome(r,{writingMode:'vertical-rl',verticalPageInsets:{left:44}});
  assert.equal(applyVerticalPageChrome(r, {writingMode:'horizontal-tb',topMargin:90,bottomMargin:50}),false);
  assert.equal(r.style.padding, '0px');
  assert.equal(r.getAttribute('top-margin'),'90px');
  assert.equal(r.getAttribute('bottom-margin'),'50px');
});
test('auto follows the loaded chapter; headless rendering has no chrome', () => {
  const r = renderer();
  assert.equal(applyVerticalPageChrome(r,{writingMode:'auto',verticalPageInsets:{}}),true);
  r.writingMode='horizontal-tb';
  assert.equal(applyVerticalPageChrome(r,{writingMode:'auto',verticalPageInsets:{}}),false);
  r.writingMode='vertical-rl';
  assert.equal(applyVerticalPageChrome(r,{writingMode:'vertical-rl'}),false);
});
test('column rules follow the red-frame switch and never appear in horizontal/headless mode', () => {
  const r = renderer();
  const style = {writingMode: 'vertical-rl', verticalPageInsets: {}, verticalRedFrame: true};
  applyVerticalPageChrome(r, style);
  assert.equal(r.getAttribute('vertical-column-rules'), 'true');
  for (const override of [{verticalRedFrame: false}, {writingMode: 'horizontal-tb'}, {verticalPageInsets: null}]) {
    applyVerticalPageChrome(r, {...style, ...override});
    assert.equal(r.getAttribute('vertical-column-rules'), 'false');
  }
});

const rulesCode = await readFile(new URL('../assets/foliate-js/src/vertical-column-rules.js', import.meta.url), 'utf8');
const { columnSeparators } = await import(`data:text/javascript;base64,${Buffer.from(rulesCode).toString('base64')}`);
test('column rules use actual glyph gaps, merging mixed inline fragments', () => {
  assert.deepEqual(columnSeparators([
    {left:80,right:105}, {left:10,right:30}, {left:50,right:68},
    {left:13,right:29}, {left:49,right:66},
  ], 120), [39.5, 74]);
});
test('offscreen text and touching glyphs do not create spurious lines', () => {
  assert.deepEqual(columnSeparators([
    {left:-30,right:-10}, {left:10,right:30}, {left:29,right:51},
    {left:150,right:180}, {left:NaN,right:40},
  ], 100), []);
  assert.deepEqual(columnSeparators([], 100), []);
});
test('larger fonts/uneven paragraph spacing are not forced onto a fixed grid', () => {
  assert.deepEqual(columnSeparators([
    {left:10,right:40}, {left:70,right:100}, {left:150,right:195},
  ], 240), [55, 125]);
});
test('background is painted once across the renderer, not only inside its padded content', async () => {
  const paginator = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
  assert.match(paginator, /<div id="background" part="filter"><\/div>\s*<div id="top">/);
  assert.match(paginator, /:host \{ background-color: var\(--_background-color\); \}/);
  const book = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8');
  assert.doesNotMatch(book, /documentElement\.style\.backgroundColor = 'grey'/);
});
