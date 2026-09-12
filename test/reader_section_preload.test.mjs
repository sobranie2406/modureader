import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { runInNewContext } from 'node:vm';

const source = await readFile(new URL('../assets/foliate-js/src/section-window-cache.js', import.meta.url), 'utf8');
const { SectionWindowCache } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const tick = () => new Promise(resolve => setImmediate(resolve));
const deferred = () => { let resolve; const promise = new Promise(r => resolve = r); return { promise, resolve }; };

function fixture(count = 8) {
  const loads = [], unloads = [], timers = new Map();
  let timer = 0, active = 0, peak = 0;
  const sections = Array.from({ length: count }, (_, index) => ({
    size: 100,
    async load() {
      active++; peak = Math.max(peak, active); loads.push(index);
      await Promise.resolve(); active--;
      return `blob:chapter-${index}`;
    },
    unload() { unloads.push(index); },
  }));
  const cache = new SectionWindowCache(sections, {
    schedule(callback) { timers.set(++timer, callback); return timer; },
    cancel(id) { timers.delete(id); },
  });
  async function idle() {
    for (const [id, callback] of [...timers]) { timers.delete(id); callback(); }
    await tick();
  }
  return { cache, sections, loads, unloads, timers, idle, peak: () => peak };
}

test('only loads the visible chapter initially, then warms next and previous', async () => {
  const f = fixture();
  await f.cache.load(3); f.cache.setCurrent(3);
  assert.deepEqual(f.loads, [3]);
  await f.idle();
  assert.deepEqual(f.loads, [3, 4, 2]);
  assert.equal(f.peak(), 1, 'shared EPUB resources load serially');
  assert.deepEqual(f.cache.indices.sort(), [2, 3, 4]);
  f.cache.destroy();
});

test('back and forth across a chapter boundary reuse the original URLs', async () => {
  const f = fixture();
  await f.cache.load(3); f.cache.setCurrent(3); await f.idle();
  await f.cache.load(4); f.cache.setCurrent(4); await f.idle();
  await f.cache.load(3); f.cache.setCurrent(3); await f.idle();
  assert.equal(f.loads.filter(i => i === 3).length, 1);
  assert.equal(f.loads.filter(i => i === 4).length, 1);
  assert.ok(!f.unloads.includes(3) && !f.unloads.includes(4));
  assert.deepEqual(f.cache.indices.sort(), [2, 3, 4]);
  f.cache.destroy();
});

test('window stays bounded and releases old resources after long jumps', async () => {
  const f = fixture(60);
  for (const index of [1, 30, 50, 2, 48]) {
    await f.cache.load(index); f.cache.setCurrent(index); await f.idle();
    assert.deepEqual(f.cache.indices.sort((a, b) => a - b), [index - 1, index, index + 1]);
  }
  f.cache.destroy();
  assert.equal(f.cache.indices.length, 0);
  assert.equal(f.loads.length, f.unloads.length);
});

test('first/last chapter, nonlinear inserts, absent sections and large chapters', async () => {
  const f = fixture(6);
  f.sections[1].linear = 'no';
  f.sections[3] = null;
  f.sections[4].size = 4 * 1024 * 1024;
  await f.cache.load(0); f.cache.setCurrent(0); await f.idle();
  assert.deepEqual(f.loads, [0, 2]);
  await f.cache.load(2); f.cache.setCurrent(2); await f.idle();
  assert.deepEqual(f.loads, [0, 2], 'large adjacent text is not prefetched');
  await f.cache.load(4); f.cache.setCurrent(4); await f.idle();
  assert.ok(f.loads.includes(4), 'foreground loading remains available');
  await f.cache.load(5); f.cache.setCurrent(5); await f.idle();
  assert.deepEqual(f.cache.indices, [5]);
  f.cache.destroy();
});

test('foreground navigation joins an in-flight prefetch without duplicate loads', async () => {
  const f = fixture(); const gate = deferred();
  f.sections[2].load = async () => { f.loads.push(2); await gate.promise; return 'blob:two'; };
  await f.cache.load(1); f.cache.setCurrent(1); await f.idle();
  const first = f.cache.load(2), second = f.cache.load(2);
  assert.equal(first, second);
  gate.resolve();
  assert.equal(await first, 'blob:two');
  f.cache.setCurrent(2); await f.idle();
  assert.equal(f.loads.filter(i => i === 2).length, 1);
  f.cache.destroy();
});

test('a failed background chapter does not poison the foreground retry', async () => {
  const f = fixture(); let attempts = 0;
  f.sections[2].load = async () => { if (++attempts === 1) throw Error('temporary'); return 'blob:retry'; };
  await f.cache.load(1); f.cache.setCurrent(1); await f.idle();
  assert.ok(!f.cache.indices.includes(2));
  assert.equal(await f.cache.load(2), 'blob:retry');
  assert.equal(attempts, 2);
  f.cache.destroy();
});

test('closing cancels scheduled work and releases late-running loads exactly once', async () => {
  const f = fixture(); const gate = deferred();
  f.sections[2].load = async () => { f.loads.push(2); await gate.promise; return 'blob:late'; };
  await f.cache.load(1); f.cache.setCurrent(1); await f.idle();
  f.cache.destroy(); gate.resolve(); await tick();
  assert.deepEqual(f.loads, [1, 2]);
  assert.deepEqual(f.unloads.sort(), [1, 2]);
  assert.equal(f.timers.size, 0);
  await assert.rejects(f.cache.load(0), /closed/);
  const other = fixture();
  await other.cache.load(1); other.cache.setCurrent(1); other.cache.destroy(); await other.idle();
  assert.deepEqual(other.loads, [1]);
});

test('paginator uses the cache, schedules after display and disposes it', async () => {
  const paginator = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
  assert.match(paginator, /new SectionWindowCache\(this.sections\)/);
  assert.match(paginator, /#display\(this.#sectionCache.load\(index\)/);
  assert.match(paginator, /this.#sectionCache.setCurrent\(index\)/);
  assert.doesNotMatch(paginator, /sections\[oldIndex\].*unload/);
  assert.match(paginator, /this.#sectionCache\?\.destroy\(\)/);
});

test('real EPUB loader keeps shared CSS, images and fonts alive, then revokes them', async () => {
  const { JSDOM } = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
  const dom = new JSDOM('', { url: 'https://reader.invalid/' });
  const policySource = await readFile(new URL('../assets/foliate-js/src/script_policy.js', import.meta.url), 'utf8');
  const { sanitizeBookDocument } = await import(`data:text/javascript;base64,${Buffer.from(policySource).toString('base64')}`);
  const urls = new Map(), revoked = [], reads = [];
  let urlId = 0;
  class BlobURL extends URL {
    static createObjectURL(blob) { const url = `blob:fixture-${++urlId}`; urls.set(url, blob); return url; }
    static revokeObjectURL(url) { revoked.push(url); urls.delete(url); }
  }
  const epubSource = await readFile(new URL('../assets/foliate-js/src/epub.js', import.meta.url), 'utf8');
  const Loader = runInNewContext(epubSource.replace(/^import .*$/gm, '').replace(/^export /gm, '') + '\nLoader', {
    URL: BlobURL, URLSearchParams, Blob, EventTarget, CustomEvent, console,
    window: dom.window, document: dom.window.document,
    DOMParser: dom.window.DOMParser, XMLSerializer: dom.window.XMLSerializer,
    ProcessingInstruction: dom.window.ProcessingInstruction, sanitizeBookDocument,
  });
  const manifest = [
    ...Array.from({length: 5}, (_, i) => ({href: `${i}.xhtml`, mediaType: 'application/xhtml+xml'})),
    {href: 'shared.css', mediaType: 'text/css'},
    {href: 'font.woff', mediaType: 'font/woff'},
    {href: 'image.png', mediaType: 'image/png'},
  ];
  const loader = new Loader({ resources: {manifest},
    async loadText(href) {
      reads.push(href);
      if (href.endsWith('.css')) return '@font-face { font-family: Reader; src: url("font.woff"); }';
      return `<html xmlns="http://www.w3.org/1999/xhtml"><head><link rel="stylesheet" href="shared.css"/></head><body><p>${href}</p><img src="image.png"/></body></html>`;
    },
    async loadBlob(href) { reads.push(href); return new Blob(['synthetic binary']); },
  });
  const sections = manifest.slice(0, 5).map(item => ({load: () => loader.loadItem(item), unload: () => loader.unloadItem(item)}));
  const scheduled = new Map(); let id = 0;
  const cache = new SectionWindowCache(sections, {
    schedule(fn) { scheduled.set(++id, fn); return id; }, cancel(id) { scheduled.delete(id); },
  });
  async function display(index) {
    const url = await cache.load(index);
    assert.ok(urls.has(url), 'visible chapter URL must not have been revoked');
    cache.setCurrent(index);
    for (const [id, fn] of [...scheduled]) { scheduled.delete(id); fn(); }
    await tick();
    return url;
  }
  try {
    const original = await display(1);
    await display(2);
    assert.equal(await display(1), original);
    assert.equal(reads.filter(href => href === '1.xhtml').length, 1);
    for (const href of ['shared.css', 'font.woff', 'image.png'])
      assert.equal(reads.filter(value => value === href).length, 1, href);
    assert.equal(urls.size, 6, 'three chapters plus three shared assets');
  } finally {
    cache.destroy();
    assert.equal(urls.size, 0, 'all cache-owned object URLs released');
    assert.equal(new Set(revoked).size, revoked.length, 'no double release');
    dom.window.close();
  }
});
