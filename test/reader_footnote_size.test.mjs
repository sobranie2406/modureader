import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
const source = await readFile(new URL('../assets/foliate-js/src/footnote-size.js', import.meta.url), 'utf8');
const { footnoteBoxSize, attachFootnoteSizing } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

test('short notes shrink; long notes grow beyond the former 400 x 200 limit', () => {
  const viewport = {width: 1400, height: 900};
  const short = footnoteBoxSize({...viewport, textLength: 8, contentHeight: 26});
  const long = footnoteBoxSize({...viewport, textLength: 900, contentHeight: 2400});
  assert.ok(short.width < long.width);
  assert.ok(short.height < long.height);
  assert.ok(long.width > 400 && long.height > 200);
});
test('outer box including padding and borders never exceeds 25 percent of viewport area', () => {
  for (const [width, height] of [[390,844], [844,390], [2810,950], [1366,768], [320,480], [80,120]]) {
    for (const desktop of [false, true]) for (const fontSize of [12,24,48]) for (const textLength of [0,10,200,50000]) {
      const box = footnoteBoxSize({width,height,fontSize,textLength,desktop,contentHeight:100000});
      assert.ok(box.width * box.height <= width * height * .25, JSON.stringify({width,height,box}));
      assert.ok(box.width <= width && box.height <= height);
      assert.ok(box.width > 0 && box.height > 0);
    }
  }
});
test('content height includes the border box and is capped only when needed', () => {
  const base = {width:1200,height:800,textLength:300,fontSize:20,chromeHeight:18};
  assert.equal(footnoteBoxSize({...base, contentHeight:80}).height, 98);
  const long = footnoteBoxSize({...base, contentHeight:2000});
  assert.equal(long.height, long.maxHeight);
});
test('desktop long notes show a taller reading area within the same area cap', () => {
  const base = {width:1400,height:900,textLength:2000,contentHeight:3000};
  const previous = footnoteBoxSize(base);
  const desktop = footnoteBoxSize({...base,desktop:true});
  assert.ok(desktop.height > previous.height * 1.25);
  assert.ok(desktop.width * desktop.height <= base.width * base.height / 4);
});
test('desktop medium notes expand but short notes still fit their content', () => {
  const base = {width:1400,height:900,fontSize:16,contentHeight:120};
  const medium = footnoteBoxSize({...base,textLength:120,desktop:true});
  assert.ok(medium.width >= 360 && medium.height >= 240);
  const short = { ...base,textLength:8,contentHeight:26 };
  const small = footnoteBoxSize({...short,desktop:true});
  assert.equal(small.width,footnoteBoxSize(short).width);
  assert.equal(small.height,footnoteBoxSize(short).height);
});
test('desktop chooses a fully fitting width instead of forcing a scrollable shape', () => {
  const box = footnoteBoxSize({width:1400,height:900,desktop:true,textLength:300,
    measureHeight: width => width < 700 ? 900 : 220});
  assert.ok(box.width >= 700);
  assert.equal(box.height, 240);
  assert.ok(box.width * box.height <= 1400 * 900 / 4);
});
test('very long measured notes stay within the cap instead of cropping the document', () => {
  const box = footnoteBoxSize({width:390,height:844,desktop:true,textLength:9000,
    measureHeight: () => 5000});
  assert.ok(box.width * box.height <= 390 * 844 / 4);
  assert.equal(box.height,box.maxHeight);
});
test('smaller resized viewport recomputes the cap instead of retaining previous dimensions', () => {
  const base = {textLength:5000,contentHeight:10000};
  const desktop = footnoteBoxSize({...base,width:1400,height:900});
  const phone = footnoteBoxSize({...base,width:390,height:844});
  assert.ok(phone.width < desktop.width);
  assert.ok(phone.width * phone.height <= 390 * 844 / 4);
});
test('sizer measures text rather than the previous oversized iframe body', () => {
  const { JSDOM } = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
  const dom = new JSDOM('<div id="note" style="box-sizing:border-box;padding:8px;border:1px solid"></div>');
  const content = new JSDOM('<body style="font-size:24px;margin:0"><p>短注释</p></body>');
  const win = dom.window;
  win.ResizeObserver = class {observe() {} disconnect() {}};
  win.requestAnimationFrame = () => 1;
  win.cancelAnimationFrame = () => {};
  content.window.document.createRange = () => ({selectNodeContents() {}, getBoundingClientRect: () => ({height:36})});
  Object.defineProperty(content.window.document.body, 'scrollHeight', {value:99999});
  const dialog = win.document.querySelector('#note');
  const sizing = attachFootnoteSizing(dialog, content.window.document);
  assert.equal(dialog.style.height, '54px');
  const width = dialog.style.width;
  sizing.destroy();
  win.dispatchEvent(new win.Event('resize'));
  assert.equal(dialog.style.width, width);
  win.close(); content.window.close();
});
test('HTML div popup no longer calls dialog-only APIs and reconnects sizing on each note', async () => {
  const book = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8');
  assert.ok(!book.includes('footnoteDialog.showModal()'));
  assert.ok(!book.includes('footnoteDialog.close()'));
  assert.match(book, /attachFootnoteSizing\(footnoteDialog, doc, \{\s*desktop: style.desktopPageInput === true/);
  assert.match(book, /footnoteSizing\?\.destroy\(\)/);
  assert.match(book, /renderer.setStyles\(css \+ footnoteLayoutCSS\)/);
  assert.match(source, /padding-block-end: 1em !important/);
  assert.match(source, /display: flow-root !important/);
  const html = await readFile(new URL('../assets/foliate-js/index.html', import.meta.url), 'utf8');
  assert.ok(!html.includes('max-height: 200px'));
  assert.match(html, /box-sizing: border-box/);
});

test('mobile sizing includes end padding in portrait and landscape without exceeding the area cap', () => {
  const { JSDOM } = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
  for (const [width,height] of [[390,844],[844,390]]) {
    for (const contentHeight of [36,4000]) {
      const dom = new JSDOM('<div id="note" style="box-sizing:border-box;padding:8px;border:1px solid"></div>');
      const content = new JSDOM('<body style="font-size:24px;margin:0;padding-bottom:24px"><p>移动端末行</p></body>');
      const win = dom.window;
      Object.defineProperty(win,'innerWidth',{value:width});
      Object.defineProperty(win,'innerHeight',{value:height});
      win.ResizeObserver = class {observe() {} disconnect() {}};
      win.requestAnimationFrame = () => 1;
      win.cancelAnimationFrame = () => {};
      content.window.document.createRange = () => ({selectNodeContents() {},
        getBoundingClientRect: () => ({height:contentHeight})});
      const dialog = win.document.querySelector('#note');
      const sizing = attachFootnoteSizing(dialog,content.window.document,{desktop:false});
      const boxWidth=parseFloat(dialog.style.width),boxHeight=parseFloat(dialog.style.height);
      assert.ok(boxWidth*boxHeight<=width*height*.25);
      if (contentHeight===36) assert.equal(boxHeight,36+24+18);
      sizing.destroy();win.close();content.window.close();
    }
  }
});
