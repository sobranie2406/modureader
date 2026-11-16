import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {runInNewContext} from 'node:vm';

const {JSDOM} = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const read = name => readFile(new URL(`../assets/foliate-js/src/${name}.js`, import.meta.url), 'utf8');
const weights = await read('reader-font-weight');
const book = await read('book');
const cfiSource = await read('epubcfi');
const CFI = await import(`data:text/javascript;base64,${Buffer.from(cfiSource).toString('base64')}`);

function reader(modern, html) {
  const CSS = {supports: () => modern};
  const {readerFontWeightCSS, prepareReaderFontWeight} = runInNewContext(
    weights.replaceAll('export ', '') + '\n({readerFontWeightCSS,prepareReaderFontWeight})', {CSS});
  const start = book.indexOf('const getCSS =');
  const getCSS = runInNewContext(
    book.slice(start, book.indexOf('const fixHeadingColor', start)) + '\ngetCSS', {
      CSS, readerFontWeightCSS, readerFontCSS: () => ({faces: '', family: ''}),
      readerSelectionCSS: () => '', isPdf: false,
    });
  const dom = new JSDOM(html);
  dom.window.CSS = CSS;
  const doc = dom.window.document;
  const css = getCSS({fontSize: 2, fontWeight: 700, spacing: 1.8});
  return {dom, doc, css, prepare: (styles = css) => prepareReaderFontWeight(doc, styles)};
}

function imageRules(css) {
  const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)];
  const pure = rules.find(([, , body]) =>
    /text-indent:\s*initial\s*!important/.test(body) && /font-size:\s*initial\s*!important/.test(body));
  const inline = rules.find(([, selector, body]) =>
    selector.includes('[data-modu-inline-image]') && /font-size:\s*inherit\s*!important/.test(body));
  assert.ok(pure, 'pure-image paragraphs retain their own reset rule');
  assert.ok(inline, 'inline glyph images inherit the surrounding text size');
  assert.match(pure[1], /\[data-modu-image-paragraph\]/);
  assert.doesNotMatch(pure[1], /:has\(/);
  assert.equal(rules.some(([, selector, body]) => /a\s*>\s*img/.test(selector)
    && /font-size:/.test(body) && !/font-size:\s*inherit\s*!important/.test(body)), false,
  'linked glyphs must not multiply the reader font size a second time');
  const selector = value => value.replace(/\/\*[\s\S]*?\*\//g, '').trim();
  return {pure: selector(pure[1]), inline: selector(inline[1])};
}

for (const modern of [false, true]) {
  const mode = modern ? 'modern' : 'legacy';

  test(`embedded glyphs never reset the whole prose paragraph (${mode})`, () => {
    const {dom, doc, css, prepare} = reader(modern, `
      <p id="sanguo">那人不甚好读书；性宽和，寡言语，喜怒不形于<img src="gaiji.png" alt="色">。</p>
      <p id="direct">前文<img src="one.png">后文</p>
      <p id="first"><img src="two.png">后文</p>
      <p id="last">前文<img src="three.png"></p>
      <p id="span">前文<span><img src="four.png"></span>后文</p>
      <p id="linked">前文<a href="#note"><span><img src="five.png"></span></a>后文</p>
      <p id="direct-link">前文<a href="#note"><img src="direct-link.png"></a>后文</p>
      <div id="nested"><span>前文<a href="#note"><img src="six.png"></a>后文</span></div>
      <p id="page-run"><modu-page-run>前文<span><img src="run.png"></span>后文</modu-page-run></p>
      <p id="anchor"><a href="#note">脚注</a><img src="seven.png"></p>
      <p id="plain">没有图片的正文</p>`);
    try {
      prepare();
      for (const p of doc.body.children) {
        assert.equal(p.hasAttribute('data-modu-image-paragraph'), false, p.id);
      }
      for (const img of doc.querySelectorAll('img')) {
        assert.ok(img.hasAttribute('data-modu-inline-image'), img.outerHTML);
      }
      const rules = imageRules(css);
      for (const p of doc.body.children) assert.equal(p.matches(rules.pure), false, `${p.id} must keep the reader's text size`);
      for (const img of doc.querySelectorAll('img')) assert.ok(img.matches(rules.inline));
    } finally { dom.window.close(); }
  });

  test(`pure illustrations include whitespace, empty anchors and wrapped image groups (${mode})`, () => {
    const {dom, doc, css, prepare} = reader(modern, `
      <p id="only"><img src="cover.png" alt="封面说明"></p>
      <p id="space"> \n<a id="bookmark"></a> \t<img src="plate.png"> \n</p>
      <p id="wrapped"><span><a href="plate.png"><span><img src="plate.png"></span></a></span></p>
      <div id="gallery"><div id="frame"><span><img src="left.png"></span></div><div id="right-frame"><a><img src="right.png"></a></div></div>
      <p id="multiple"><img src="a.png"><span><img src="b.png"></span></p>
      <p id="old-class"><img class="has-text-siblings" src="c.png"></p>
      <p id="hidden"><span hidden>不可见的图注</span><img src="hidden.png"></p>
      <p id="display-none"><span style="display:none">隐藏的图注</span><img src="hidden-inline.png"></p>
      <p id="metadata"><script>window.caption = 'not prose';</script><style>.caption { color: red }</style><img src="metadata.png"></p>
      <p id="pure-run"><modu-page-run><span><img src="pure-run.png"></span></modu-page-run></p>
      <div id="mixed"><p id="child-image"><img src="d.png"></p><p id="caption">插图下的正文</p></div>`);
    try {
      prepare();
      const rules = imageRules(css);
      for (const id of ['only', 'space', 'wrapped', 'frame', 'right-frame', 'multiple', 'old-class', 'hidden', 'display-none', 'metadata', 'pure-run', 'child-image']) {
        const p = doc.getElementById(id);
        assert.ok(p.hasAttribute('data-modu-image-paragraph'), id);
        assert.ok(p.matches(rules.pure), id);
        for (const img of p.querySelectorAll('img')) assert.equal(img.hasAttribute('data-modu-inline-image'), false, id);
      }
      assert.equal(doc.querySelector('#gallery').matches(rules.pure), false);
      assert.equal(doc.querySelector('#mixed').matches(rules.pure), false);
      assert.equal(doc.querySelector('#caption').matches(rules.pure), false);
    } finally { dom.window.close(); }
  });

  test(`preparation preserves original text nodes, selection and EPUB CFI anchors (${mode})`, () => {
    const {dom, doc, prepare} = reader(modern,
      '<p id="prose">玄德看毕<span>，叹息<img src="gaiji.png" alt="曰">：</span><a href="#note">大丈夫</a>不与国家出力，何故长叹？</p>');
    try {
      const p = doc.querySelector('p');
      const before = p.textContent;
      const elements = [...p.querySelectorAll('*')];
      const walker = doc.createTreeWalker(p, 4);
      const nodes = [];
      for (let node = walker.nextNode(); node; node = walker.nextNode()) nodes.push(node);
      const checks = nodes.map(node => {
        const range = doc.createRange();
        range.selectNodeContents(node);
        return {node, text: node.data, cfi: CFI.fromRange(range)};
      });
      const range = doc.createRange();
      range.setStart(nodes[0], 1);
      range.setEnd(nodes.at(-1), 4);
      doc.getSelection().addRange(range);
      const selected = range.toString(), crossCFI = CFI.fromRange(range);
      prepare();
      prepare('');
      prepare();
      assert.equal(p.textContent, before);
      assert.deepEqual([...p.querySelectorAll('*')], elements);
      assert.equal(doc.getSelection().toString(), selected);
      assert.equal(CFI.toRange(doc, CFI.parse(crossCFI)).toString(), selected);
      for (const {node, text, cfi} of checks) {
        assert.equal(node.data, text);
        assert.ok(p.contains(node));
        const restored = CFI.toRange(doc, CFI.parse(cfi));
        assert.equal(restored.startContainer, node);
        assert.equal(restored.toString(), text);
      }
    } finally { dom.window.close(); }
  });

  test(`repeated preparation removes stale pure-image and inline-image markers (${mode})`, () => {
    const {dom, doc, prepare} = reader(modern, '<p id="changing"><img src="glyph.png"></p><p id="destination"></p>');
    try {
      const p = doc.querySelector('#changing'), img = p.querySelector('img');
      prepare();
      assert.ok(p.hasAttribute('data-modu-image-paragraph'));
      assert.equal(img.hasAttribute('data-modu-inline-image'), false);
      const text = doc.createTextNode('新增的正文');
      p.insertBefore(text, img);
      prepare();
      assert.equal(p.hasAttribute('data-modu-image-paragraph'), false);
      assert.ok(img.hasAttribute('data-modu-inline-image'));
      text.remove();
      prepare();
      assert.ok(p.hasAttribute('data-modu-image-paragraph'));
      assert.equal(img.hasAttribute('data-modu-inline-image'), false);
      doc.querySelector('#destination').append(img);
      prepare('');
      assert.equal(p.hasAttribute('data-modu-image-paragraph'), false);
      assert.ok(doc.querySelector('#destination').hasAttribute('data-modu-image-paragraph'));
      assert.equal(img.hasAttribute('data-modu-inline-image'), false);
    } finally { dom.window.close(); }
  });

  test(`SVG content retains its own nodes and sizing without shrinking adjacent prose (${mode})`, () => {
    const {dom, doc, css, prepare} = reader(modern, `
      <p id="vector">前文<svg width="24" height="24" viewBox="0 0 24 24"><text x="1" y="20">字</text></svg>后文</p>
      <div id="drawing"><svg width="600" height="800" viewBox="0 0 600 800"><image href="plate.png" width="600" height="800"/></svg></div>`);
    try {
      const svg = doc.querySelector('svg'), drawing = doc.querySelector('#drawing svg');
      const before = [svg.outerHTML, drawing.outerHTML, doc.body.textContent];
      prepare();
      assert.equal(doc.querySelector('#vector').matches(imageRules(css).pure), false);
      assert.equal(doc.querySelector('svg'), svg);
      assert.equal(doc.querySelector('#drawing svg'), drawing);
      assert.equal(svg.getAttribute('width'), '24');
      assert.equal(drawing.getAttribute('viewBox'), '0 0 600 800');
      assert.equal(doc.body.textContent, before[2]);
      assert.equal(svg.querySelector('text').textContent, '字');
      assert.equal(doc.querySelector('svg[data-modu-inline-image]'), null);
    } finally { dom.window.close(); }
  });

  test(`unlaid-out frames need no geometry and preserve publisher image dimensions (${mode})`, () => {
    const {dom, doc, prepare} = reader(modern, `
      <p id="prose">前文<span><img id="glyph" src="glyph.png" width="16" height="18" align="baseline"
        style="width:0.8em;height:1em;vertical-align:-0.1em"></span>后文</p>
      <p id="plate"><img id="illustration" src="plate.png" width="600" height="800" style="width:100%;height:auto;vertical-align:middle"></p>`);
    try {
      const images = [...doc.querySelectorAll('img')];
      const before = images.map(img => ['width', 'height', 'align', 'style'].map(name => img.getAttribute(name)));
      const unavailable = () => { throw new Error('image classification must not depend on iframe layout'); };
      dom.window.Element.prototype.getBoundingClientRect = unavailable;
      dom.window.Element.prototype.getClientRects = unavailable;
      dom.window.getComputedStyle = unavailable;
      for (const name of ['clientWidth', 'clientHeight', 'scrollWidth', 'scrollHeight']) {
        Object.defineProperty(dom.window.Element.prototype, name, {get: unavailable});
      }
      for (const name of ['offsetWidth', 'offsetHeight']) {
        Object.defineProperty(dom.window.HTMLElement.prototype, name, {get: unavailable});
      }
      prepare();
      prepare();
      assert.ok(doc.querySelector('#glyph').hasAttribute('data-modu-inline-image'));
      assert.equal(doc.querySelector('#prose').hasAttribute('data-modu-image-paragraph'), false);
      assert.ok(doc.querySelector('#plate').hasAttribute('data-modu-image-paragraph'));
      assert.deepEqual(images.map(img => ['width', 'height', 'align', 'style'].map(name => img.getAttribute(name))), before);
    } finally { dom.window.close(); }
  });
}
