import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';

const {JSDOM} = createRequire(`${process.env.MODU_JSDOM_ROOT || '/private/tmp/modu-pdf-js-tests'}/package.json`)('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/reader-motion.js', import.meta.url), 'utf8');
const {applyReaderMotion, reducedReaderMotionCSS} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

test('E-Ink disables chapter transitions, animations and smooth scrolling without modifying publisher styles', () => {
  const dom = new JSDOM('<html><head><style id="publisher">p{transition:color 1s}</style></head><body><p>Reading</p></body></html>');
  try {
    const doc = dom.window.document;
    applyReaderMotion(doc, true);
    applyReaderMotion(doc, true);
    assert.equal(doc.querySelectorAll('#modu-reduced-motion').length, 1);
    assert.match(reducedReaderMotionCSS, /animation:\s*none\s*!important/);
    assert.match(reducedReaderMotionCSS, /transition:\s*none\s*!important/);
    assert.match(reducedReaderMotionCSS, /scroll-behavior:\s*auto\s*!important/);
    assert.equal(doc.getElementById('publisher').textContent, 'p{transition:color 1s}');
    applyReaderMotion(doc, false);
    assert.equal(doc.querySelector('#modu-reduced-motion'), null);
    assert.equal(doc.getElementById('publisher').textContent, 'p{transition:color 1s}');
  } finally { dom.window.close(); }
});

test('reader and footnote styles carry E-Ink state and disable renderer turn animation', async () => {
  const book = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8');
  assert.match(book, /applyReaderMotion\(document, style.eInkMode === true\)/);
  assert.match(book, /if \(style.eInkMode === true\) turn.animated = false/);
  assert.match(book, /eInkMode\s*:\s*style.eInkMode/);
});
