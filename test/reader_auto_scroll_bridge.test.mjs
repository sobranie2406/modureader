import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';

const book = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8');

test('auto scroll uses the reader e-ink mode while preserving speed and session', () => {
  const source = book.slice(book.indexOf('window.setReaderAutoScroll ='),
    book.indexOf('\nwindow.stopReaderAutoScroll'));
  const seen = [];
  const context = { window: {}, style: { eInkMode: true },
    autoScroll: { set: options => { seen.push(options); return true; } } };
  runInNewContext(source, context);
  assert.equal(context.window.setReaderAutoScroll({ enabled: true, speed: .1, session: 7, eInkMode: false }), true);
  assert.deepEqual(JSON.parse(JSON.stringify(seen[0])), { enabled: true, speed: .1, session: 7, eInkMode: true });
  context.style = { eInkMode: false };
  context.window.setReaderAutoScroll({ enabled: true, speed: 4, session: 8, eInkMode: true });
  assert.deepEqual(JSON.parse(JSON.stringify(seen[1])), { enabled: true, speed: 4, session: 8, eInkMode: false });
});

test('switching e-ink mode stops the old driver before layout changes', () => {
  const source = book.slice(book.indexOf('window.changeStyle ='), book.indexOf('\nwindow.goToHref'));
  const events = [];
  const context = { window: {}, style: { eInkMode: false, fontSize: 20 },
    console: { log() {} },
    autoScroll: { stop: reason => events.push(`stop:${reason}`), refresh: () => events.push('refresh') },
    setStyle: () => events.push('layout'), changeCodeHighlightTheme() {} };
  runInNewContext(source, context);
  context.window.changeStyle({ eInkMode: true });
  assert.deepEqual(events, ['stop:mode', 'layout', 'refresh']);
  events.length = 0;
  context.window.changeStyle({ fontSize: 24 });
  assert.deepEqual(events, ['layout', 'refresh']);
  events.length = 0;
  context.window.changeStyle({ eInkMode: false });
  assert.deepEqual(events, ['stop:mode', 'layout', 'refresh']);
});
