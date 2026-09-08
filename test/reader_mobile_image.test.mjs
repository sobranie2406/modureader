import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
const { JSDOM } = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/mobile-image-fit.js', import.meta.url), 'utf8');
const { mobileImageBounds, fitMobileImages } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const layout = {mobileImageFit: true, width: 390, height: 760, columnWidth: 350, gap: 40, topMargin: 20, bottomMargin: 40};
function fixture() {
  const doc = new JSDOM('<div style="width:2000px;height:3000px;overflow:hidden"><img style="width:1200px;height:1800px;min-width:1200px;min-height:1800px"></div>').window.document;
  const img = doc.querySelector('img');
  Object.defineProperties(img, {naturalWidth: {value:1200}, naturalHeight: {value:1800}});
  return {doc, img};
}
test('mobile content bounds include both margins and scrolled viewport dimensions', () => {
  assert.deepEqual(mobileImageBounds(layout), {width:350, height:700});
  assert.deepEqual(mobileImageBounds({...layout, flow:'scrolled'}), {width:310, height:760});
  assert.deepEqual(mobileImageBounds(layout, true), {width:330, height:350});
});
test('oversized media and its fixed crop box fit proportionally', () => {
  const {doc, img} = fixture(); fitMobileImages(doc, layout);
  assert.equal(img.style.width, '350px'); assert.equal(img.style.height, '525px');
  assert.equal(img.style.minWidth, '0'); assert.equal(img.style.minHeight, '0');
  assert.equal(doc.querySelector('div').style.height, 'auto');
  assert.equal(doc.querySelector('div').style.overflow, 'visible');
  assert.equal(img.style.objectFit, 'contain');
});
test('landscape resize refits from original dimensions instead of retaining portrait shrink', () => {
  const {doc, img} = fixture(); fitMobileImages(doc, layout);
  fitMobileImages(doc, {...layout, width:760, height:390, columnWidth:720});
  assert.equal(parseFloat(img.style.height), 330);
  assert.equal(parseFloat(img.style.width), 220);
  fitMobileImages(doc, layout);
  assert.equal(img.style.width, '350px');
});
test('desktop mode does not mutate publisher styles', () => {
  const {doc} = fixture(); const before = doc.body.innerHTML;
  fitMobileImages(doc, {...layout, mobileImageFit:false});
  assert.equal(doc.body.innerHTML, before);
});
test('small inline icons do not inflate to their intrinsic dimensions', () => {
  const {doc, img} = fixture(); img.style.width = '16px'; img.style.height = '24px';
  img.style.minWidth = '0'; img.style.minHeight = '0';
  fitMobileImages(doc, layout);
  assert.equal(img.style.width, '16px'); assert.equal(img.style.height, '24px');
});
test('source wiring gates initial and updated layout by host platform, not window width', async () => {
  for (const name of ['../lib/utils/webView/webview_initial_variable.dart', '../lib/page/book_player/epub_player.dart']) {
    assert.match(await readFile(new URL(name, import.meta.url), 'utf8'), /mobileImageFit: \$\{AnxPlatform.isMobile\}/);
  }
  const paginator = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
  assert.match(paginator, /if \(this\.#layout\.mobileImageFit\) \{\s+fitMobileImages/);
  assert.match(paginator, /doc.addEventListener\('load', refit, true\)/);
});
