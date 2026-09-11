import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('../assets/foliate-js/src/desktop-page-input.js', import.meta.url), 'utf8');
const { desktopPageKey, desktopDragDirection, installDesktopPageInput } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const settle = () => new Promise(resolve => setImmediate(resolve));
function fixture() {
  const doc = new EventTarget();
  doc.defaultView = new EventTarget();
  let selection = '', enabled = true;
  doc.getSelection = () => selection;
  const turns = [];
  const controller = installDesktopPageInput(doc, { enabled: () => enabled,
    turnPage: async d => { turns.push(d); } });
  const send = (type, props = {}) => {
    const e = new Event(type, { cancelable: true });
    Object.assign(e, props);
    doc.dispatchEvent(e);
    return e;
  };
  const point = (type, x, y = 10, extra = {}) => send(type,
    { pointerType: 'mouse', pointerId: 1, button: 0, clientX: x, clientY: y, ...extra });
  return { doc, turns, send, point, controller,
    select(value) { selection = value; send('selectionchange'); },
    disable() { enabled = false; } };
}
test('all directions mean discrete previous/next, not native movement', () => {
  for (const key of ['ArrowRight', 'ArrowDown', 'PageDown', ' '])
    assert.equal(desktopPageKey({ key }), 1);
  for (const key of ['ArrowLeft', 'ArrowUp', 'PageUp'])
    assert.equal(desktopPageKey({ key }), -1);
  for (const flag of ['shiftKey', 'ctrlKey', 'metaKey', 'altKey', 'isComposing', 'defaultPrevented'])
    assert.equal(desktopPageKey({ key: 'ArrowRight', [flag]: true }), 0);
  assert.equal(desktopPageKey({ key: 'ArrowRight', composedPath: () => [{isContentEditable:true}] }), 0);
  assert.equal(desktopPageKey({ key: 'ArrowLeft', composedPath: () => [{matches:()=>true}] }), 0);
});
test('empty-space drag turns one page, jitter and ambiguous diagonals do not', () => {
  for (const [x,y,wanted] of [[-60,0,1],[60,0,-1],[0,-60,1],[0,60,-1],[20,0,0],[-60,60,0]])
    assert.equal(desktopDragDirection(x,y), wanted);
});
test('actual DOM handlers consume arrow keys including repeat while navigating', async () => {
  const f = fixture();
  assert.equal(f.send('keydown', {key:'ArrowRight'}).defaultPrevented, true);
  assert.equal(f.send('keydown', {key:'ArrowRight', repeat:true}).defaultPrevented, true);
  await settle();
  assert.deepEqual(f.turns,[1]);
  f.send('keydown', {key:'ArrowUp'}); await settle();
  assert.deepEqual(f.turns,[1,-1]);
  f.disable();
  assert.equal(f.send('keydown',{key:'ArrowDown'}).defaultPrevented,false);
});
test('drag consumes synthetic click, but never disables native text selection', async () => {
  const f = fixture();
  assert.equal(f.point('pointerdown',200).defaultPrevented,false);
  assert.equal(f.point('pointermove',70).defaultPrevented,false);
  assert.equal(f.point('pointerup',70).defaultPrevented,true);
  assert.equal(f.send('click').defaultPrevented,true);
  await settle(); assert.deepEqual(f.turns,[1]);
});
test('existing/new selection, touch, right click, blur and cancellation never page', async () => {
  for (const mode of ['existing','new','touch','right','blur','cancel','leave']) {
    const f = fixture();
    if (mode === 'existing') f.select('already selected');
    f.point('pointerdown',200,10,mode==='touch'?{pointerType:'touch'}:mode==='right'?{button:2}:{});
    if (mode === 'new') { f.select('new selected text'); f.select(''); }
    if (mode === 'blur') f.doc.defaultView.dispatchEvent(new Event('blur'));
    if (mode === 'cancel') f.send('pointercancel');
    if (mode === 'leave') f.send('mouseleave');
    f.point('pointerup',70); await settle();
    assert.deepEqual(f.turns,[],mode);
  }
});
test('destroy detaches handlers and releases pending gesture', async () => {
  const f = fixture(); f.point('pointerdown',200); f.controller.destroy();
  assert.equal(f.send('keydown',{key:'ArrowDown'}).defaultPrevented,false);
  f.point('pointerup',70); await settle(); assert.deepEqual(f.turns,[]);
});
test('runtime wires desktop-only input for outer document and every loaded chapter', async () => {
  const book=await readFile(new URL('../assets/foliate-js/src/book.js',import.meta.url),'utf8');
  const dart=await readFile(new URL('../lib/page/book_player/epub_player.dart',import.meta.url),'utf8');
  assert.match(book,/this\.installDesktopInput\(document\)/);
  assert.match(book,/this\.installDesktopInput\(doc\)/);
  assert.match(book,/style\.desktopPageInput === true && !window\.isFootNoteOpen\(\)/);
  assert.match(dart,/desktopPageInput: \$\{AnxPlatform\.isDesktop\}/);
  const initial=await readFile(new URL('../lib/utils/webView/gererate_url.dart',import.meta.url),'utf8');
  assert.match(initial,/'desktopPageInput': AnxPlatform\.isDesktop/);
  const legacy=await readFile(new URL('../lib/utils/webView/webview_initial_variable.dart',import.meta.url),'utf8');
  assert.match(legacy,/desktopPageInput: \$\{AnxPlatform\.isDesktop\}/);
});

test('completed reader taps return Flutter and native focus even with AI open', async () => {
  const dart=await readFile(new URL('../lib/page/book_player/epub_player.dart',import.meta.url),'utf8');
  const page=await readFile(new URL('../lib/page/reading_page.dart',import.meta.url),'utf8');
  const click=dart.slice(dart.indexOf('  void onClick('), dart.indexOf('  void onClick(')+2200);
  assert.match(click,/readingPageKey\.currentState\?\.focusReaderFromTap\(\)/);
  const start=page.indexOf('  void focusReaderFromTap()');
  const method=page.slice(start,page.indexOf('\n  }',start));
  assert.match(method,/!AnxPlatform\.isDesktop/);
  assert.match(method,/_readerFocusNode\.requestFocus\(\)/);
  assert.match(method,/restoreNativeReaderFocus\(\)/);
  assert.doesNotMatch(method,/_aiChat/);
});
