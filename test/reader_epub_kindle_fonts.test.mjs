import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';

const source = await readFile(new URL('../assets/foliate-js/src/epub-kindle-fonts.js', import.meta.url), 'utf8');
const { createKindleFontResolver } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const fonts = Array.from({length:17}, (_,i) => ({
  href:`OEBPS/FONT${String(i).padStart(5,'0')}.ttf`, mediaType:'application/vnd.ms-opentype',
}));
const css = 'OEBPS/flow0001.css';

test('converted EPUB font references use one-based base32 resource IDs, not manifest order', () => {
  const resolve = createKindleFontResolver([...fonts].reverse());
  for (let i = 0; i < fonts.length; i++) {
    const id = (i+1).toString(32).toUpperCase().padStart(4,'0');
    assert.equal(resolve(`kindle:embed:${id}`, css), fonts[i]);
  }
  assert.equal(resolve('kindle:embed:000H?mime=application/x-font-ttf', css), fonts[16]);
});

test('ordinary/system fonts and non-font, malformed or missing Kindle URLs remain unchanged', () => {
  const resolve = createKindleFontResolver(fonts);
  for (const url of ['sans-serif','FONT00016.ttf','https://example.com/font.ttf',
    'kindle:flow:0001','kindle:embed:0000','kindle:embed:000I','kindle:embed:000Z',
    'kindle:embed:000H?mime=image/jpeg','kindle:embed:000H/trailing',
    'kindle:embed:VVVVVVVVVVVVVVVVVVVVVV']) assert.equal(resolve(url, css), null, url);
  assert.equal(resolve('kindle:embed:000H','Other/styles.css'),null);
});

test('ambiguous, gapped or non-font manifest resources are not guessed', () => {
  for (const manifest of [fonts.slice(1), [...fonts, fonts[0]],
    fonts.map(f=>({...f,mediaType:'image/png'})),
    fonts.map(f=>({...f,href:f.href.replace('FONT','Unknown')}))]) {
    assert.equal(createKindleFontResolver(manifest)('kindle:embed:000H',css),null);
  }
});

const epub = await readFile(new URL('../assets/foliate-js/src/epub.js', import.meta.url), 'utf8');
const replaceCSS = epub.slice(epub.indexOf('    async replaceCSS('),epub.indexOf('    // find & replace all possible relative paths'));
const replaceSeries = epub.slice(epub.indexOf('const replaceSeries ='),epub.indexOf('\nconst regexEscape'));
const CSSLoader = runInNewContext(`${replaceSeries}\nclass CSSLoader { ${replaceCSS} }; CSSLoader`, {window:{innerWidth:800,innerHeight:600}});

test('production CSS loader passes mapped fonts through normal asset loading with parent lifetime', async () => {
  const loader = new CSSLoader();
  loader.resolveKindleFont = createKindleFontResolver(fonts);
  const calls = [];
  loader.loadItem = async (font,parents) => {calls.push({font,parents:[...parents]}); return 'blob:original-font';};
  loader.loadHref = async url => url;
  const result = await loader.replaceCSS('@font-face{font-family:BookFont;src:url(kindle:embed:000H)} p{font-family:sans-serif}',css,['OEBPS/title.xhtml']);
  assert.match(result,/src:url\("blob:original-font"\)/);
  assert.match(result,/font-family:sans-serif/);
  assert.equal(calls[0].font, fonts[16]);
  assert.deepEqual(calls[0].parents,['OEBPS/title.xhtml',css]);
});

test('real asset errors still propagate; unresolved references are not silently dropped', async () => {
  const loader = new CSSLoader();
  loader.resolveKindleFont = createKindleFontResolver(fonts);
  loader.loadItem = async () => {throw Error('font unreadable');};
  loader.loadHref = async url => url;
  await assert.rejects(loader.replaceCSS('a{src:url(kindle:embed:000H)}',css),/font unreadable/);
  assert.match(await loader.replaceCSS('a{src:url(kindle:embed:000I)}',css),/kindle:embed:000I/);
  assert.match(await loader.replaceCSS('a{src:url(FONT00016.ttf)}',css),/FONT00016.ttf/);
});
