// Run with MODU_JSDOM_ROOT pointing to a directory containing node_modules/jsdom.
import test from 'node:test'
import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { readFile } from 'node:fs/promises'
import { runInNewContext } from 'node:vm'
const requireDOM = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)
const { JSDOM } = requireDOM('jsdom')
const loadSource = async name => import(`data:text/javascript;base64,${Buffer.from(await readFile(new URL(`../assets/foliate-js/src/${name}`, import.meta.url))).toString('base64')}`)
const { sanitizeBookDocument } = await loadSource('script_policy.js')
const { makePDF } = await loadSource('pdf.js')
const { getChapterLocation } = await loadSource('progress.js')

test('fixed-layout display pages are one-based without changing EPUB paginator pages', () => {
  assert.deepEqual(getChapterLocation({}, {current: 0, total: 3}), {current: 1, total: 3})
  assert.deepEqual(getChapterLocation({}, {current: 2, total: 3}), {current: 3, total: 3})
  assert.deepEqual(getChapterLocation({page: 1, pages: 12}, {current: 5, total: 20}), {current: 1, total: 10})
  assert.deepEqual(getChapterLocation({page: 10, pages: 12}, {current: 5, total: 20}), {current: 10, total: 10})
})

test('Reader.open navigates once and waits for initialization, for new and resumed books', async () => {
  // Execute the actual Reader.open method with an instrumented renderer. This
  // catches the extra renderer.next() even if it is fire-and-forget.
  const source = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8')
  const openMethod = source.slice(source.indexOf('  async open(file, cfi) {'), source.indexOf('\n  setView(view) {'))
  for (const cfi of [undefined, 'epubcfi(/6/4)']) {
    const events = []
    let releaseInit
    const ready = new Promise(resolve => { releaseInit = resolve })
    const view = {
      addEventListener: () => {},
      renderer: {next: () => { events.push('next') }},
      init: async args => { events.push(['init', args.lastLocation]); await ready; events.push('ready') },
    }
    const Reader = runInNewContext(`(class {
      #onLoad() {} #onRelocate() {} #onClickView() {}
      #onTouchStart() {} #onTouchMove() {} #onTouchEnd() {}
      setView() {}
      ${openMethod}
    })`, {getView: async () => view, importing: false, setStyle() {}, document: {documentElement: {style: {}}}})
    let completed = false
    const opened = new Reader().open('fixture', cfi).then(() => { completed = true })
    await new Promise(resolve => setImmediate(resolve))
    assert.deepEqual(events, [['init', cfi]])
    assert.equal(completed, false)
    releaseInit()
    await opened
    assert.deepEqual(events, [['init', cfi], 'ready'])
    assert.equal(completed, true)
  }
})

test('disabled EPUB scripts remove inline/external code, handlers and active URLs', () => {
  const doc = new JSDOM(`<html><head><script src="https://example.com/bad.js"></script><meta http-equiv="refresh" content="0;url=javascript:alert(1)"></head><body onload="alert(1)">
    <script>alert(1)</script><img src="cover.png" onerror="alert(1)"><img id="inline" src="data:image/png;base64,AAAA"><a href="java&#10;script:alert(1)">unsafe</a>
    <a id="safe" href="https://example.com/">safe</a><iframe srcdoc="<script>alert(1)</script>"></iframe>
    <svg><script>alert(1)</script><foreignObject><iframe></iframe></foreignObject></svg><p>Readable text</p></body></html>`).window.document
  sanitizeBookDocument(doc, false)
  assert.equal(doc.querySelectorAll('script,iframe,foreignObject,meta[http-equiv="refresh"]').length, 0)
  assert.equal(doc.querySelector('[onload], [onerror]'), null)
  assert.equal(doc.querySelector('a').getAttribute('href'), null)
  assert.equal(doc.querySelector('#safe').href, 'https://example.com/')
  assert.equal(doc.querySelector('img').getAttribute('src'), 'cover.png')
  assert.equal(doc.querySelector('#inline').getAttribute('src'), 'data:image/png;base64,AAAA')
  assert.match(doc.head.firstChild.getAttribute('content'), /script-src 'none'/)
  assert.match(doc.body.textContent, /Readable text/)
})

test('explicit script opt-in keeps the original content', () => {
  const doc = new JSDOM('<script>enabled()</script><p onclick="enabled()">text</p>').window.document
  sanitizeBookDocument(doc, true)
  assert.equal(doc.querySelectorAll('script').length, 1)
  assert.equal(doc.querySelector('p').getAttribute('onclick'), 'enabled()')
})

test('PDF extraction uses all pages even with a partial outline, without HTML execution', async () => {
  globalThis.document = new JSDOM('').window.document
  globalThis.pdfjsLib = { getDocument: () => ({ promise: Promise.resolve({
    numPages: 3, getMetadata: async () => ({info: {Title: 'Fixture'}}),
    getOutline: async () => [{ title: 'Partial outline', dest: [0], items: [] }],
    getPage: async number => ({getTextContent: async () => ({ items: [{str: `Page ${number} <script>not code</script>`, hasEOL: true}] })}),
  }) }) }
  const book = await makePDF(new Blob(['fixture']))
  assert.equal(book.toc.length, 1)
  assert.equal(book.indexToc.length, 3)
  for (let i = 0; i < 3; i++) {
    assert.deepEqual(await book.resolveHref(book.indexToc[i].href), {index: i})
    const doc = await book.sections[i].createDocument()
    assert.match(doc.body.textContent, new RegExp(`Page ${i+1}`))
    assert.equal(doc.querySelector('script'), null)
  }
  await assert.rejects(book.resolveHref('pdf-page:3'), /out of bounds/)
})

test('headless PDF cover rendering uses print intent and finite dimensions', async () => {
  const dom = new JSDOM('')
  globalThis.document = dom.window.document
  globalThis.innerWidth = 0
  globalThis.innerHeight = 0
  globalThis.devicePixelRatio = 2
  dom.window.HTMLCanvasElement.prototype.getContext = () => ({})
  dom.window.HTMLCanvasElement.prototype.toBlob = function(callback) {
    assert.equal(this.width, 600); assert.equal(this.height, 800)
    callback(new Blob(['cover']))
  }
  let rendered = false
  globalThis.pdfjsLib = { getDocument: () => ({promise: Promise.resolve({
    numPages: 1, getMetadata: async () => ({}), getOutline: async () => null,
    getPage: async () => ({
      getViewport: ({scale}) => ({width: 600 * scale, height: 800 * scale}),
      render: ({intent}) => { assert.equal(intent, 'print'); rendered = true; return {promise: Promise.resolve()} },
    }),
  })}) }
  const book = await makePDF(new Blob(['fixture']))
  assert.equal((await book.getCover()).size, 5)
  assert.equal(rendered, true)
  assert.equal(book.toc.length, 1)
})

test('actual PDF.js extracts the audited normal fixture and rejects encrypted/broken samples', async () => {
  const require = createRequire(import.meta.url)
  globalThis.pdfjsLib = require('../assets/foliate-js/src/vendor/pdfjs/pdf.js')
  globalThis.document = new JSDOM('').window.document
  const fixture = async name => new Blob([await readFile(new URL(`../docs/qa/2026-09-05/full-audit/fixtures/${name}`, import.meta.url))])
  const book = await makePDF(await fixture('MODU-QA-text-and-image.pdf'))
  assert.equal(book.sections.length, 3)
  assert.deepEqual(book.toc.map(item => item.startPage), [1, 2, 3])
  assert.deepEqual(book.toc.map(item => item.startPercentage), [0, 1 / 3, 2 / 3])
  assert.match((await book.sections[0].createDocument()).body.textContent, /MODU/)
  assert.equal((await book.sections[2].createDocument()).body.textContent.trim(), '')
  await assert.rejects(makePDF(await fixture('MODU-QA-password.pdf')), {name: 'PasswordException'})
  await assert.rejects(makePDF(await fixture('MODU-QA-broken.pdf')))
})

test('fixed-layout navigation reports the requested side, including within the same spread', async () => {
  const dom = new JSDOM('', {resources: 'usable'})
  for (const name of ['document', 'HTMLElement', 'customElements', 'CustomEvent']) {
    globalThis[name] = dom.window[name]
  }
  globalThis.ResizeObserver = class {observe() {} unobserve() {}}
  globalThis.CSSStyleSheet = class {replaceSync() {}}
  // JSDOM does not load iframe resources inside shadow roots. Mount only the
  // test root in light DOM; use the real renderer/frame/navigation logic.
  dom.window.HTMLElement.prototype.attachShadow = function () {
    return document.body.appendChild(document.createElement('div'))
  }
  const { FixedLayout } = await loadSource('fixed-layout.js')
  const layout = new FixedLayout()
  document.body.append(layout)
  layout.getBoundingClientRect = () => ({width: 1200, height: 800})
  const page = 'data:text/html,' + encodeURIComponent('<html><head><meta name="viewport" content="width=600,height=800"></head><body>fixture</body></html>')
  const book = {rendition: {layout: 'pre-paginated'}, sections: Array.from({length: 3}, (_, id) => ({id, load: async () => page}))}
  book.sections[0].pageSpread = 'right'
  layout.open(book)
  const locations = []
  layout.addEventListener('relocate', event => locations.push(event.detail.index))
  await layout.next()
  assert.equal(layout.index, 0)
  await layout.next()
  assert.equal(layout.index, 1)
  await layout.goTo({index: 2})
  assert.equal(layout.index, 2)
  await layout.goTo({index: 1})
  assert.equal(layout.index, 1)
  assert.deepEqual(locations, [0, 1, 2, 1])
  layout.destroy()
  dom.window.close()
})
