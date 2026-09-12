import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const source = await readFile(new URL('../assets/foliate-js/src/selection-style.js', import.meta.url), 'utf8');
const { readerSelectionCSS } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

test('active and inactive book selections retain the same blue background on all platforms', () => {
  const css = readerSelectionCSS();
  const active = css.match(/::selection\s*\{([^}]+)\}/)[1];
  const inactive = css.match(/::selection:window-inactive\s*\{([^}]+)\}/)[1];
  assert.equal(active, inactive);
  assert.match(active, /background-color: rgba\(64, 156, 255, 0.35\) !important/);
  assert.match(active, /color: inherit !important/);
});

test('mobile and desktop receive selection CSS; PDF retains its text layer styling', () => {
  for (const args of [
    { desktop: false, platform: 'MacIntel' }, // iPad desktop user agent
    { desktop: true, platform: 'Win32' },
    { desktop: true, platform: 'Linux x86_64' },
    { desktop: false, platform: 'iPhone' },
    { desktop: true },
  ]) {
    assert.match(readerSelectionCSS(args), /::selection\s*\{/);
    assert.equal(readerSelectionCSS({ ...args, pdf: true }), '');
  }
  assert.doesNotMatch(source, /removeAllRanges|addRange|\.focus\(|preventDefault|user-select|touch-action/);
});

test('selection styles are generated with chapter CSS rather than only the outer page', async () => {
  const book = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8');
  const cssStart = book.indexOf('const getCSS =');
  const call = book.indexOf('${readerSelectionCSS(', cssStart);
  assert.ok(call > cssStart);
  assert.match(book.slice(call, call + 180), /pdf: isPdf/);
});

test('menu dismissal restores book focus on every platform without focusing the outer key handler', async () => {
  const page = await readFile(new URL('../lib/page/reading_page.dart', import.meta.url), 'utf8');
  const start = page.indexOf('  void _requestReaderFocus()');
  const method = page.slice(start, page.indexOf('\n  }', start));
  assert.match(method, /_restoreReaderFocusAfterPanel\(\);/);
  assert.doesNotMatch(method, /AnxPlatform|_readerFocusNode.requestFocus/);
  const restore = page.slice(page.indexOf('  void _restoreReaderFocusAfterPanel()'), page.indexOf('  void _closeAiChat()'));
  assert.match(restore, /addPostFrameCallback/);
  assert.match(restore, /_aiChat != null/);
  assert.match(restore, /ModalRoute.of\(context\)\?\.isCurrent != true/);
  assert.match(page, /FocusScope\(\s*node: _readerWebViewFocusScope,\s*child: EpubPlayer\(/);
  assert.match(page, /_readerWebViewFocusScope.dispose\(\)/);
});
