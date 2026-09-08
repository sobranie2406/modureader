import test from 'node:test'
import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { readFile } from 'node:fs/promises'
import vm from 'node:vm'
const requireDOM = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)
const { JSDOM } = requireDOM('jsdom')
const load = async name => import(`data:text/javascript;base64,${Buffer.from(await readFile(new URL(`../assets/foliate-js/src/${name}`, import.meta.url))).toString('base64')}`)
const { TTS } = await load('tts.js')
const { TtsNavigator } = await load('tts-navigation.js')
function documentFor(html) {
  const dom = new JSDOM(`<body>${html}</body>`)
  globalThis.document = dom.window.document
  globalThis.NodeFilter = dom.window.NodeFilter
  globalThis.Range = dom.window.Range
  return dom.window.document
}
function speech(doc) { return new TTS(doc, null, () => null) }
function all(tts) {
  const values = []
  for (let text = tts.start(); text != null; text = tts.next()) values.push(text.trim())
  return values
}

test('all heading levels, TOC backlink headings, and inline local links are read', () => {
  const doc = documentFor(Array.from({length: 6}, (_, i) => `<h${i+1}><a href="toc.xhtml#ch${i}">标题${i+1}</a></h${i+1}>`).join('') + '<p>正文<a href="#other">有效文字</a>结束。</p>')
  assert.deepEqual(all(speech(doc)), ['标题1', '标题2', '标题3', '标题4', '标题5', '标题6', '正文有效文字结束。'])
})
test('only explicit note markers, hidden content and ruby annotations are excluded', () => {
  const doc = documentFor('<h1><a href="#toc">标题</a></h1><p>你好<a epub:type="noteref" href="#n1">[1]</a>世界。</p><p><ruby>默读<rt>mo du</rt></ruby>继续。</p><p hidden>隐藏</p><script>bad()</script>')
  assert.deepEqual(all(speech(doc)), ['标题', '你好世界。', '默读继续。'])
})
test('starting from a visible range preserves the first heading and does not consume peek', () => {
  const doc = documentFor('<h1>第一章</h1><p>正文一句。</p><p>正文二句。</p>')
  const tts = speech(doc)
  const range = doc.createRange()
  range.selectNodeContents(doc.body)
  assert.equal(tts.from(range), '第一章')
  assert.equal(tts.currentDetail().text, '第一章')
  assert.deepEqual(tts.collectDetails(3, {includeCurrent: true}).map(x => x.text), ['第一章','正文一句。','正文二句。'])
  assert.equal(tts.currentDetail().text, '第一章')
  assert.equal(tts.next(), '正文一句。')
})
function reader(chapters) {
  const docs = chapters.map(documentFor)
  let index = 0
  const visited = []
  const view = {
    book: {sections: docs.map(() => ({}))},
    renderer: {
      getContents: () => [{index, doc: docs[index]}],
      goTo: async ({index: target}) => { await new Promise(r => setTimeout(r, 2)); index = target; visited.push(index) },
    },
    initTTS() { if (this.tts?.doc !== docs[index]) this.tts = speech(docs[index]) },
  }
  view.initTTS()
  return {view, nav: new TtsNavigator(() => view), visited}
}
test('starting at an empty chapter continues through following chapters', async () => {
  const {view, nav, visited} = reader(['', '<h1>下一章</h1><p>正文。</p>', '<h1>末章</h1>'])
  assert.equal(await nav.start(), '下一章')
  assert.equal(await nav.move(1), '正文。')
  assert.equal(await nav.move(1), '末章')
  assert.equal(await nav.move(1), '')
  assert.deepEqual(visited, [1,2])
})
test('starting after the last spoken paragraph continues at the next heading', async () => {
  const {view, nav} = reader(['<p>上一章末句。</p><div id="end"></div>', '<h1>下一章</h1>'])
  const doc = view.renderer.getContents()[0].doc
  const range = doc.createRange(); range.selectNode(doc.querySelector('#end'))
  assert.equal(await nav.start(range), '下一章')
})
test('a temporarily locked page turn retries the same chapter without losing its title', async () => {
  const {view, visited} = reader(['<p>末句。</p>', '<h1>下一章</h1><p>正文。</p>'])
  const goTo = view.renderer.goTo
  let attempts = 0
  view.renderer.goTo = async target => { if (++attempts > 2) await goTo(target) }
  const nav = new TtsNavigator(() => view, {retryDelayMs:1})
  view.tts.start()
  assert.equal(await nav.move(1), '下一章')
  assert.equal(await nav.move(1), '正文。')
  assert.deepEqual(visited, [1])
  assert.equal(attempts, 3)
})
test('a permanently unavailable chapter raises an error, never a false end-of-book', async () => {
  const {view, visited} = reader(['<p>末句。</p>', '<h1>不能跳过</h1>', '<h1>后章</h1>'])
  view.renderer.goTo = async () => {}
  const nav = new TtsNavigator(() => view, {navigationTimeoutMs:5,retryDelayMs:1})
  view.tts.start()
  await assert.rejects(nav.move(1), /navigation did not finish/)
  assert.deepEqual(visited, [])
})
test('manual stop while waiting for a page lock prevents late automatic continuation', async () => {
  const {view, visited} = reader(['<p>末句。</p>', '<h1>下一章</h1>'])
  const nav = new TtsNavigator(() => view, {retryDelayMs:1})
  view.renderer.goTo = async () => { nav.stop() }
  view.tts.start()
  assert.equal(await nav.move(1), '')
  assert.deepEqual(visited, [])
})
test('automatic transitions read each chapter heading exactly once, including title-only chapters', async () => {
  const {view, nav, visited} = reader(['<h1>一</h1><p>正文。</p>', '<h1>二</h1>', '<h1>三</h1><p>完。</p>'])
  const text = [view.tts.start()]
  for (let i=0;i<8;i++) { const next = await nav.move(1); if (!next) break; text.push(next) }
  assert.deepEqual(text, ['一','正文。','二','三','完。'])
  assert.deepEqual(visited, [1,2])
  assert.equal(await nav.move(1), '')
})
test('empty chapters are bounded and the last chapter does not recurse forever', async () => {
  const {view, nav, visited} = reader(['<p>开始。</p>', '', '<p>结束。</p>', ''])
  view.tts.start()
  assert.equal(await nav.move(1), '结束。')
  assert.equal(await nav.move(1), '')
  assert.equal(await nav.move(1), '')
  assert.deepEqual(visited, [1,2,3])
})
test('manual next chapter starts at its title, previous chapter can start at title or last sentence', async () => {
  const {view, nav} = reader(['<h1>一</h1><p>末句。</p>', '<h1>二</h1><p>正文。</p>'])
  view.tts.start()
  assert.equal(await nav.move(1, {section: true, last: false}), '二')
  assert.equal(await nav.move(-1, {section: true, last: false}), '一')
  await nav.move(1, {section: true, last: false})
  assert.equal(await nav.move(-1), '末句。')
})
test('concurrent next requests serialize chapter loads instead of skipping a chapter', async () => {
  const {view, nav, visited} = reader(['<h1>一</h1>', '<h1>二</h1><p>正文。</p>', '<h1>三</h1>'])
  view.tts.start()
  assert.deepEqual(await Promise.all([nav.move(1), nav.move(1)]), ['二','正文。'])
  assert.deepEqual(visited, [1])
})
test('failed chapter load reports an error without advancing further', async () => {
  const {view} = reader(['<h1>一</h1>', '<h1>二</h1>'])
  const nav = new TtsNavigator(() => view, {navigationTimeoutMs:5,retryDelayMs:1})
  view.tts.start()
  view.renderer.goTo = async () => {}
  await assert.rejects(nav.move(1), /did not finish/)
  assert.equal(view.renderer.getContents()[0].index, 0)
})
test('stop invalidates pending chapter movement and queued requests', async () => {
  const {view, nav, visited} = reader(['<h1>一</h1>', '', '<h1>三</h1>'])
  view.tts.start()
  const moving = nav.move(1)
  const queued = nav.move(1)
  await new Promise(r => setImmediate(r))
  nav.stop()
  assert.deepEqual(await Promise.all([moving, queued]), ['', ''])
  assert.deepEqual(visited, [1])
})

// Exercise the actual private page-turn method with only its renderer IO stubbed.
const paginatorSource = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8')
const turnPage = paginatorSource.slice(paginatorSource.indexOf('  async #turnPage('), paginatorSource.indexOf('  prev(distance)'))
const PageTurn = vm.runInNewContext(`(class {
  #locked = false;
  adjacent = 1;
  failure = false;
  visits = [];
  get locked() { return this.#locked }
  async #scrollPrev() { return true }
  async #scrollNext() { return true }
  #adjacentIndex() { return this.adjacent }
  async #goTo({index}) {
    if (this.failure) throw new Error('load failed')
    this.visits.push(index)
  }
  hasAttribute() { return false }
  turn(dir) { return this.#turnPage(dir) }
  ${turnPage}
})`, {wait: async () => {}})
test('page-turn load failure releases the lock for later TTS navigation', async () => {
  const page = new PageTurn()
  page.failure = true
  await assert.rejects(page.turn(1), /load failed/)
  assert.equal(page.locked, false)
  page.failure = false
  await page.turn(1)
  assert.equal(page.visits[0], 1)
})
test('turning beyond the last chapter never loads an undefined section or leaves a lock', async () => {
  const page = new PageTurn()
  page.adjacent = undefined
  await page.turn(1)
  assert.equal(page.visits.length, 0)
  assert.equal(page.locked, false)
})
