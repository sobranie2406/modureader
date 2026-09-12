import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
const book = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8');
const chunk = (a,b) => book.slice(book.indexOf(a), book.indexOf(b));
const gateSource = await readFile(new URL('../assets/foliate-js/src/reading-action-gate.js', import.meta.url), 'utf8');
const {ReadingActionGate} = await import(`data:text/javascript;base64,${Buffer.from(gateSource).toString('base64')}`);

test('wake/resize scroll is passive, real scroll and explicit backward navigation count', () => {
  let now = 0; const gate = new ReadingActionGate(() => now);
  assert.equal(gate.isAction('scroll'), false);
  assert.equal(gate.isAction('anchor'), false);
  assert.equal(gate.isAction('page'), true);
  assert.equal(gate.isAction('navigation'), true);
  gate.input({isTrusted:false});
  assert.equal(gate.isAction('scroll'), false);
  gate.input({isTrusted:true});
  assert.equal(gate.isAction('scroll'), true);
  now = 2000; assert.equal(gate.isAction('snap'), true);
  now = 60000; assert.equal(gate.isAction('scroll'), false);
});

test('sync restore labels navigation callbacks as passive and releases suppression on failure', async () => {
  const win = {}, seen = [];
  const renderer = {isNavigating: false};
  const view = {renderer, async goTo() {seen.push(win.readerApplyingSync); return {index:1};}};
  runInNewContext(chunk('window.restoreSyncedReadingPosition =', '\nwindow.goToPercent'), {window:win, reader:{view}});
  assert.equal(await win.restoreSyncedReadingPosition('synthetic-cfi'), true);
  assert.deepEqual(seen, [true]); assert.equal(win.readerApplyingSync, false);
  renderer.isNavigating = true;
  assert.equal(await win.restoreSyncedReadingPosition('synthetic-cfi'), false);
  assert.equal(seen.length, 1);
  renderer.isNavigating = false;
  view.goTo = async () => {throw Error('failed');};
  await assert.rejects(win.restoreSyncedReadingPosition('synthetic-cfi'), /failed/);
  assert.equal(win.readerApplyingSync, false);
});

test('Flutter bridge cannot mistake a sync restore or passive layout for a reading action', () => {
  const messages = [], window = {readerApplyingSync:false};
  const notify = runInNewContext(`${chunk('const onRelocated =', '\nconst onAnnotationClick')}; onRelocated`, {
    window, reader:{view:{renderer:{writingMode:'horizontal-tb'}}},
    callFlutter: (_, data) => messages.push(data),
  });
  const location = {chapterLocation:{},location:{},readingAction:true};
  notify(location); assert.equal(messages.at(-1).readingAction, true);
  window.readerApplyingSync = true;
  notify(location); assert.equal(messages.at(-1).readingAction, false);
  window.readerApplyingSync = false;
  notify({...location,readingAction:false});
  assert.equal(messages.at(-1).readingAction, false);
});

test('remote annotation refresh replaces overlays without issuing bookmark deletion actions', async () => {
  const Harness = runInNewContext(`class Harness {
    annotations = new Map(); annotationsByValue = new Map(); removed = [];
    view = {addAnnotation: async (a, remove) => this.removed.push([a.value,remove])};
    checked = 0;
    #checkCurrentPageBookmark() {this.checked++}
    renderAnnotation(annos) {for (const a of annos) this.annotationsByValue.set(a.value,a)}
    ${chunk('  async replaceReadingAnnotations(', '\n  showContextMenu()')}
  }; Harness`);
  const reader = new Harness();
  reader.annotationsByValue.set('old',{value:'old',type:'highlight'});
  reader.annotationsByValue.set('bookmark',{value:'bookmark',type:'bookmark'});
  await reader.replaceReadingAnnotations([{value:'new',type:'highlight'}]);
  assert.equal(reader.removed.length, 1);
  assert.equal(reader.removed[0][0], 'old');
  assert.equal(reader.removed[0][1], true);
  assert.deepEqual([...reader.annotationsByValue.keys()], ['new']);
  assert.equal(reader.checked, 1);
});
