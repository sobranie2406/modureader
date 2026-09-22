import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const {JSDOM} = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/reader-fonts.js', import.meta.url), 'utf8');
const {readerFontCSS, englishUnicodeRange, captureBookFontFamilies} =
  await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

test('default preserves book/system/custom single-font behavior without English requests', () => {
  assert.deepEqual(readerFontCSS(), {faces:'', family:''});
  assert.deepEqual(readerFontCSS({fontName:'system'}), {faces:'', family:'font-family: system-ui !important;'});
  const css = readerFontCSS({fontName:'customFont',fontPath:'/中文.otf'});
  assert.match(css.faces, /font-display: block/);
  assert.doesNotMatch(css.faces, /unicode-range|ModuEnglish/);
  assert.equal(css.family, 'font-family: "customFont" !important;');
});

test('English face is restricted to Latin, digits and western punctuation, never Han or CJK punctuation', () => {
  const contains = char => englishUnicodeRange.split(',').some(part => {
    const [low,high] = part.trim().replace('U+','').split('-').map(x => parseInt(x,16));
    return char.codePointAt(0) >= low && char.codePointAt(0) <= (high ?? low);
  });
  for (const c of 'Az019éüœ!?,.$') assert.equal(contains(c),true,c);
  for (const c of '中文。，《》“”‘’—𠀀Ａ１') assert.equal(contains(c),false,c);
  const css = readerFontCSS({fontName:'body',fontPath:'/body.ttf',englishFontName:'latin',englishFontPath:'/latin.ttf'});
  assert.match(css.family, /"ModuEnglish_latin", "body"/);
  assert.equal((css.faces.match(/@font-face/g)||[]).length,2);
  assert.equal((css.faces.match(/unicode-range/g)||[]).length,1);
});

test('system English has no fake URL; malformed paths cannot inject CSS', () => {
  const css = readerFontCSS({fontName:'system',englishFontName:'system'});
  assert.match(css.faces,/local\("Roboto"\)/);
  assert.doesNotMatch(css.faces,/url\(/);
  const odd = readerFontCSS({fontName:'body',fontPath:'a"\\\n.ttf',englishFontName:'latin',englishFontPath:'b".otf'});
  assert.match(odd.faces,/url\("b\\22 \.otf"\)/);
  assert.doesNotMatch(odd.faces, /a"\\\n/);
});

test('publisher faces survive English-only override without changing text nodes/CFI or author styles', () => {
  const dom = new JSDOM('<html><head><style>p{font-family:PublisherSerif}em{font-family:PublisherItalic}</style></head><body><p>中文 English <em>Italic 英文</em></p></body></html>');
  const doc = dom.window.document;
  const own = doc.createElement('style'); doc.head.append(own);
  own.textContent = '* {font-family:PreviousUserFont!important}';
  const css = readerFontCSS({englishFontName:'latin',englishFontPath:'/latin.ttf'});
  const text = doc.querySelector('p').firstChild;
  const range = doc.createRange(); range.setStart(text,3); range.setEnd(text,10);
  const before = range.toString();
  captureBookFontFamilies(doc, css.faces + css.family, [own]);
  assert.equal(doc.querySelector('p').style.getPropertyValue('--modu-book-font-family'),'PublisherSerif');
  assert.equal(doc.querySelector('em').style.getPropertyValue('--modu-book-font-family'),'PublisherItalic');
  assert.equal(doc.querySelector('p').firstChild,text);
  assert.equal(range.toString(),before);
  assert.match(own.textContent,/PreviousUserFont/);
  captureBookFontFamilies(doc, css.family, [own]);
  assert.equal(doc.querySelector('p').style.getPropertyValue('--modu-book-font-family'),'PublisherSerif');
  dom.window.close();
});

test('no publisher scan while English follows body; ordinary, cached and footnote styles are wired', async () => {
  const doc = {body:{querySelectorAll(){throw Error('unnecessary scan');}}};
  captureBookFontFamilies(doc, readerFontCSS().family);
  const book = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url),'utf8');
  assert.equal((book.match(/englishFontName: style.englishFontName/g)||[]).length,2);
  const paginator = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url),'utf8');
  assert.match(paginator,/captureBookFontFamilies\(doc, this.#styles, pair\)/);
  assert.match(paginator,/captureBookFontFamilies\(this.#view.document, styles, \$\$styles\)/);
});
