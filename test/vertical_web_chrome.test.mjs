import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const {JSDOM} = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/vertical-page-chrome.js', import.meta.url), 'utf8');
const {applyVerticalPageChrome} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
test('web chrome cannot intercept input, does not alter chapter DOM, and is removed in horizontal mode', () => {
  const dom = new JSDOM('<div id="renderer"></div>');
  const renderer = dom.window.document.querySelector('#renderer');
  renderer.attachShadow({mode: 'open'});
  const chapter = dom.window.document.createElement('iframe');
  renderer.shadowRoot.append(chapter);
  const style = {writingMode: 'vertical-rl', verticalRedFrame: true,
    verticalPageInsets: {left: 44, right: 44, top: 42, bottom: 46},
    verticalPageChrome: {title:'章 <script>no()</script>',remaining:'本章剩余四十页',progress:'一·一百',
      chinese:true,headerFontSize:12,footerFontSize:12,color:'#333333',opacity:.7,safe:{top:24,bottom:28}}};
  applyVerticalPageChrome(renderer, style);
  const root = renderer.shadowRoot.querySelector('#vertical-page-chrome');
  assert.ok(root);
  for (const node of [root, ...root.querySelectorAll('*')])
    assert.equal(node.style.pointerEvents, 'none');
  assert.equal(root.querySelector('script'), null, 'title is text, never markup');
  assert.match(root.textContent, /章 <script>no\(\)<\/script>/);
  assert.equal(chapter.parentNode, renderer.shadowRoot);
  style.verticalPageChrome.progress = '二·一百';
  applyVerticalPageChrome(renderer, style);
  assert.equal(renderer.shadowRoot.querySelector('#vertical-page-chrome'), root, 'updates reuse chrome');
  assert.match(root.textContent, /二·一百/);
  style.verticalRedFrame = false;
  applyVerticalPageChrome(renderer, style);
  assert.equal(root.firstElementChild.style.display, 'none');
  assert.match(root.textContent, /本章剩余四十页/, 'labels remain when frame disabled');
  style.writingMode = 'horizontal-tb';
  applyVerticalPageChrome(renderer, style);
  assert.equal(renderer.shadowRoot.querySelector('#vertical-page-chrome'), null);
  assert.equal(chapter.parentNode, renderer.shadowRoot);
  style.writingMode = 'vertical-rl';
  applyVerticalPageChrome(renderer, style);
  assert.ok(renderer.shadowRoot.querySelector('#vertical-page-chrome'));
  delete style.verticalPageChrome;
  applyVerticalPageChrome(renderer, style);
  assert.equal(renderer.shadowRoot.querySelector('#vertical-page-chrome'), null, 'mobile/headless have no extra chrome');
});
