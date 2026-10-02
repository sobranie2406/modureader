import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import vm from 'node:vm';
const { JSDOM } = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/reader-font-weight.js', import.meta.url), 'utf8');
const { readerFontWeightCSS, prepareReaderFontWeight } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const book = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8');
const start = book.indexOf('const getCSS =');
const getCSS = vm.runInNewContext(book.slice(start, book.indexOf('const fixHeadingColor', start)) + '\ngetCSS', {
  readerFontWeightCSS, readerFontCSS: () => ({ faces: '', family: '' }),
  readerSelectionCSS: () => '', isPdf: false,
});

test('weight applies to nested text through inheritance and permits synthetic bold', () => {
  const css = readerFontWeightCSS({ fontWeight: 700 });
  assert.match(css, /body\s*\{\s*font-weight: 700 !important/);
  assert.match(css, /font-weight: inherit !important/);
  assert.match(css, /font-synthesis: weight style !important/);
  assert.match(css, /:not\(h1, h2, h3, h4, h5, h6, \[role="heading"\], b, strong/);
  assert.doesNotMatch(readerFontWeightCSS({ useBookStyles: true }), /font-weight/);
  assert.equal(readerFontWeightCSS({ pdf: true }), '');
  assert.match(readerFontWeightCSS({ fontWeight: NaN }), /font-weight: 400/);
  assert.match(readerFontWeightCSS({ fontWeight: 2000 }), /font-weight: 900/);
});

test('simulated bold uses a bounded text stroke instead of another weight face', () => {
  assert.doesNotMatch(readerFontWeightCSS({ fontWeight: 800 }), /text-stroke/);
  for (const weight of [200, 300, 400]) {
    const css = readerFontWeightCSS({ fontWeight: weight, simulateBold: true });
    assert.doesNotMatch(css, /text-stroke/);
    assert.match(css, /font-weight: 400 !important/);
  }
  for (let step = 1; step <= 10; step++) {
    const css = readerFontWeightCSS({ fontWeight: 400 + step * 40, simulateBold: true });
    const stroke = Number(css.match(/-webkit-text-stroke-width: ([\d.]+)em/)?.[1]);
    assert.ok(Math.abs(stroke - step * 0.0035) < 1e-8);
    assert.match(css, /font-weight: 400 !important/);
    assert.match(css, /-webkit-text-stroke-color: currentColor !important/);
    assert.match(css, /-webkit-text-stroke-width: inherit !important/);
    assert.match(css, /body :where\(h1, h2,[\s\S]*?-webkit-text-stroke-width: 0 !important/);
  }
  assert.match(readerFontWeightCSS({ fontWeight: 100000, simulateBold: true }), /0\.0350em/);
  assert.doesNotMatch(readerFontWeightCSS({ fontWeight: NaN, simulateBold: true }), /text-stroke/);
  assert.equal(readerFontWeightCSS({ fontWeight: 800, simulateBold: true, useBookStyles: true }), '');
  assert.equal(readerFontWeightCSS({ fontWeight: 800, simulateBold: true, pdf: true }), '');
});

test('simulation propagates into production CSS and remains reversible without replacing text', () => {
  const dom = new JSDOM('<body><p><span>字体粗细</span></p><h1>标题</h1></body>');
  const doc = dom.window.document, text = doc.querySelector('span').firstChild;
  const range = doc.createRange(); range.setStart(text, 0); range.setEnd(text, 2);
  doc.getSelection().addRange(range);
  const css = getCSS({ fontWeight: 800, simulateBold: true, customCSSEnabled: true,
    customCSS: 'p { -webkit-text-stroke-width: 0!important; }' });
  assert.match(css, /-webkit-text-stroke-width: 0\.0350em !important/);
  assert.ok(css.indexOf('0.0350em') < css.indexOf('p { -webkit-text-stroke-width: 0!important; }'));
  prepareReaderFontWeight(doc, css);
  prepareReaderFontWeight(doc, getCSS({ fontWeight: 800, simulateBold: false }));
  assert.equal(doc.querySelector('span').firstChild, text);
  assert.equal(doc.getSelection().toString(), '字体');
  assert.match(book, /simulateBold: style\.simulateBold/);
  dom.window.close();
});

test('inline-important paragraph/span weights no longer defeat the slider; restore book styles', () => {
  const dom = new JSDOM(`<body style="font-weight:300!important"><p style="font-weight:400!important;color:red">
    <span style="font-weight:400!important;font-size:20px">正文文字</span>
    <i style="font-weight:400;font-style:italic">斜体</i>
    <strong style="font-weight:800"><span style="font-weight:800">强调</span></strong></p>
    <h1 style="font-weight:500"><span style="font-weight:500">标题</span></h1>
    <svg><text style="font-weight:200">图</text></svg><math><mi style="font-weight:200">x</mi></math></body>`);
  const doc = dom.window.document;
  const nodes = [...doc.body.querySelectorAll('*')].filter(el => el.style);
  const weights = nodes.map(el => [el.style.fontWeight, el.style.getPropertyPriority('font-weight')]);
  const text = doc.querySelector('p > span').firstChild;
  const range = doc.createRange(); range.setStart(text, 0); range.setEnd(text, 2);
  doc.getSelection().addRange(range);
  prepareReaderFontWeight(doc, readerFontWeightCSS({ fontWeight: 700 }));
  for (const el of [doc.body, doc.querySelector('p'), doc.querySelector('p > span'), doc.querySelector('i')]) {
    assert.equal(el.style.fontWeight, '');
  }
  assert.equal(doc.querySelector('span').style.fontSize, '20px');
  assert.equal(doc.querySelector('i').style.fontStyle, 'italic');
  assert.equal(doc.querySelector('p').style.color, 'red');
  for (const selector of ['strong', 'strong span', 'h1', 'h1 span', 'svg text']) {
    assert.notEqual(doc.querySelector(selector).style.fontWeight, '');
  }
  assert.equal(doc.querySelector('math mi').getAttribute('style'), 'font-weight:200');
  prepareReaderFontWeight(doc, readerFontWeightCSS({ fontWeight: 900 }));
  assert.equal(doc.getSelection().toString(), '正文');
  assert.equal(doc.querySelector('p > span').firstChild, text, 'CFIs/text nodes unchanged');
  prepareReaderFontWeight(doc, 'p {color: blue}');
  assert.equal(doc.body.style.fontWeight, '300');
  assert.equal(doc.body.style.getPropertyPriority('font-weight'), 'important');
  assert.deepEqual(nodes.map(el => [el.style.fontWeight, el.style.getPropertyPriority('font-weight')]), weights);
  dom.window.close();
});

test('normalizing a font shorthand retains size, family and italics', () => {
  const dom = new JSDOM('<body><p style="font:italic 400 24px serif!important">文字</p></body>');
  const doc = dom.window.document, p = doc.querySelector('p');
  const original = ['font-size', 'font-family', 'font-style'].map(key => p.style.getPropertyValue(key));
  prepareReaderFontWeight(doc, readerFontWeightCSS({ fontWeight: 700 }));
  assert.equal(p.style.fontWeight, '');
  assert.deepEqual(['font-size', 'font-family', 'font-style'].map(key => p.style.getPropertyValue(key)), original);
  prepareReaderFontWeight(doc, '');
  assert.equal(p.style.fontWeight, '400');
  dom.window.close();
});

test('the production stylesheet keeps custom CSS last and removes the old block-only override', () => {
  for (const weight of [100, 400, 700, 900]) {
    const css = getCSS({ fontWeight: weight, customCSSEnabled: true, customCSS: 'p {font-weight:500!important}' });
    assert.match(css, new RegExp(`font-weight: ${weight} !important`));
    assert.ok(css.indexOf('modu-reader-font-weight') < css.indexOf('p {font-weight:500!important}'));
    assert.equal((css.match(new RegExp(`font-weight: ${weight} !important`, 'g')) ?? []).length, 1);
  }
  assert.doesNotMatch(getCSS({ useBookStyles: true, fontWeight: 900 }), /modu-reader-font-weight/);
});

test('ordinary, live, preloaded and footnote frames share the weight preparation', async () => {
  const paginator = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
  assert.match(paginator, /prepareReaderFontWeight\(doc, this\.#styles\)/);
  assert.match(paginator, /prepareReaderFontWeight\(this\.#view.document, styles\)/);
  assert.match(book, /renderer\.setStyles\(css \+ footnoteLayoutCSS\)/);
});
