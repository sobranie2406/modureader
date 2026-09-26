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

test('presentation failure at a paragraph boundary must not stop or skip speech', async () => {
  const doc = documentFor('<p>第一段。</p><p>第二段。</p><p>第三段。</p>')
  const tts = new TTS(doc, null, range => {
    if (range.toString() === '第二段。') throw new Error('overlay unavailable')
  }, range => range.toString())
  const view = {tts, book: {sections: [{}]}, initTTS() {}}
  const nav = new TtsNavigator(() => view)
  assert.equal(await nav.start(), '第一段。')
  assert.equal(await nav.move(1), '第二段。')
  assert.deepEqual(tts.collectDetails(2, {includeCurrent: true}).map(x => x.text), ['第二段。', '第三段。'])
  assert.equal(await nav.move(1), '第三段。')
  assert.equal(await nav.move(-1), '第二段。')
})

test('optional CFI failure cannot discard readable text during prefetch or resume', () => {
  const doc = documentFor('<p>正文一。</p><p>正文二。</p>')
  const tts = new TTS(doc, null, () => { throw new Error('presentation failed') }, () => { throw new Error('location unavailable') })
  assert.equal(tts.start(), '正文一。')
  assert.deepEqual(tts.collectDetails(2, {includeCurrent:true}), [
    {text:'正文一。', cfi:null}, {text:'正文二。', cfi:null},
  ])
  assert.equal(tts.highlightCfi('stale-cfi'), null)
  assert.equal(tts.resume(), '正文一。')
  assert.equal(tts.next(true), '正文二。')
  assert.equal(tts.end(), '正文二。')
})

test('Previous and Next skip punctuation in both directions, preserving symbols and languages', () => {
  const tts = speech(documentFor('<p>第一句。</p><p>……</p><p>... —— ⋯⋯</p><p>第二句。</p><p>123 + مرحبا</p>'))
  assert.equal(tts.start(), '第一句。')
  assert.equal(tts.next(true), '第二句。')
  assert.equal(tts.prev(true), '第一句。')
  assert.equal(tts.prev(true), undefined)
  assert.equal(tts.next(true), '第二句。')
  assert.equal(tts.next(true), '123 + مرحبا')
})

test('read from here trims the first sentence for audio, peek and highlight, then continues', () => {
  const doc = documentFor('<p>不重读前半，从选中位置开始。下一句。</p>')
  const range = doc.createRange()
  range.setStart(doc.querySelector('p').firstChild, 6)
  range.setEnd(doc.querySelector('p').firstChild, 8)
  const tts = new TTS(doc, null, () => null, range => range.toString())
  assert.equal(tts.from(range, {exactStart:true}), '从选中位置开始。')
  assert.deepEqual(tts.collectDetails(2, {includeCurrent:true}).map(x => x.text), ['从选中位置开始。','下一句。'])
  assert.equal(tts.highlightCfi('从选中位置开始。').text, '从选中位置开始。')
  assert.equal(tts.resume(), '从选中位置开始。')
  assert.equal(tts.next(true), '下一句。')
  assert.equal(tts.prev(true), '不重读前半，从选中位置开始。')
})

test('selected start binds the selected continuous chapter, never the first visible iframe', async () => {
  const wrong = documentFor('<p>旧章节。</p>')
  const selected = documentFor('<p>前半，从此朗读。</p><p>后续正文。</p>')
  const view = {
    book: {sections:[{},{}]},
    renderer: {getContents:()=>[{index:0, doc:wrong},{index:1,doc:selected}]},
    initTTS(_stop, {content}) {this.tts = speech(content.doc); this.tts.sectionIndex = content.index},
    resolveNavigation: async () => ({index:1, anchor: doc => {
      const range = doc.createRange(); range.setStart(doc.querySelector('p').firstChild,3); range.collapse(true); return range
    }}),
  }
  const nav = new TtsNavigator(() => view)
  assert.equal(await nav.startFromCfi('selection'), '从此朗读。')
  assert.equal(view.tts.sectionIndex,1)
  assert.equal(await nav.move(1),'后续正文。')
  view.resolveNavigation = async () => null
  await assert.rejects(nav.startFromCfi('invalid'), /selected reading position/)
})

test('previous across separator-only chapters reaches real body text', async () => {
  const {nav} = reader(['<p>前章正文。</p>', '<p>……</p>', '<p>后章正文。</p>'])
  assert.equal(await nav.start(),'前章正文。')
  assert.equal(await nav.move(1),'后章正文。')
  assert.equal(await nav.move(-1),'前章正文。')
})

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
test('popup bodies, reference codes and endnotes are excluded without editing the document', () => {
  const doc = documentFor(`<h1>第一章</h1>
    <p>正文<a epub:type="noteref" href="#fn1"><sup>[1]</sup></a>继续。</p>
    <aside id="fn1" epub:type="footnote"><p>弹出注释一。</p><p>弹出注释二。</p></aside>
    <section role="doc-endnotes"><h2>章末注释</h2><ol><li role="doc-endnote">注释内容。</li></ol></section>
    <p>余下正文。</p>`)
  const before = doc.body.innerHTML
  assert.deepEqual(all(speech(doc)), ['第一章', '正文继续。', '余下正文。'])
  assert.equal(doc.body.innerHTML, before)
})
test('legacy numbered note links and their target paragraphs are skipped, ordinary numbers stay', () => {
  const doc = documentFor(`<p>正文<a href="#note_1">[1]</a>继续，2026年与x<sup>2</sup>。</p>
    <p><a id="note_1"></a>老式章末注释。</p><p>后续正文。</p>`)
  assert.deepEqual(all(speech(doc)), ['正文继续，2026年与x2。', '后续正文。'])
})
test('CSS-hidden spans inside a sentence are filtered using original ancestors', () => {
  const doc = documentFor(`<style>.popup { display:none }</style>
    <p>开始<span class="popup">隐藏注释。</span>结束。</p>
    <div style="display:none"><p>隐藏段落。</p></div>
    <p>最后一句。</p>`)
  assert.deepEqual(all(speech(doc)), ['开始结束。', '最后一句。'])
})
test('footnote backlinks never suppress the referenced body paragraph', () => {
  const doc = documentFor(`<p>保留正文<a id="ref1" href="#fn1" epub:type="noteref">1</a>结尾。</p>
    <aside id="fn1" epub:type="footnote"><p>注释<a epub:type="backlink" href="#ref1">返回</a></p></aside>
    <p>后续正文。</p>`)
  assert.deepEqual(all(speech(doc)), ['保留正文结尾。', '后续正文。'])
})
test('detached XML EPUB namespace and multi-token roles exclude chapter notes', () => {
  const base = documentFor('')
  const doc = new base.defaultView.DOMParser().parseFromString(`<html xmlns="http://www.w3.org/1999/xhtml" xmlns:e="http://www.idpf.org/2007/ops"><body>
    <p>正文<sup e:type="noteref">1</sup>结束。</p>
    <aside e:type="footnote"><p>隐藏注释。</p></aside>
    <section role="region doc-endnotes"><p>章后注释。</p></section>
    </body></html>`, 'application/xhtml+xml')
  assert.deepEqual(all(speech(doc)), ['正文结束。'])
})
test('a late asynchronous highlight cannot rewind the speech cursor', () => {
  const doc = documentFor('<p>第一句。</p><p>第二句。</p><p>第三句。</p>')
  const tts = new TTS(doc, null, () => null, range => range.toString())
  tts.start()
  tts.next()
  assert.equal(tts.highlightCfi('第一句。'), null)
  assert.equal(tts.currentDetail().text, '第二句。')
  assert.equal(tts.highlightCfi('第二句。').text, '第二句。')
  assert.equal(tts.next(), '第三句。')
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

// Use the real View speech methods without a real WebView renderer. Any
// attempted renderer load here remains pending, as it does on affected phones.
const viewSource = await readFile(new URL('../assets/foliate-js/src/view.js', import.meta.url), 'utf8')
const speechMethods = viewSource.slice(viewSource.indexOf('  oldValue = null'), viewSource.indexOf('  startMediaOverlay()'))
const SpeechView = vm.runInNewContext(`(class {
  #index = 0;
  #sectionProgress = { getProgress: (index, fraction) => ({fraction: (index + fraction) / 4}) };
  progressEvents = [];
  chapterEvents = [];
  getProgressOf(index) { return {tocItem: {label: 'Chapter ' + index}} }
  #emit(name, detail) {
    if (name === 'tts-progress') this.progressEvents.push(detail);
    if (name === 'tts-chapter') this.chapterEvents.push(detail);
  }
  overlays = [];
  #getOverlayer(index) { return this.overlays[index] }
  getCFI(index, range) { return index + ':' + range.toString() }
  resolveNavigation(cfi) {
    const index = Number(cfi.split(':')[0]);
    return {index, anchor: doc => { const r = doc.createRange(); r.selectNodeContents(doc.body); return r }}
  }
  ${speechMethods}
})`, { TTS, textWalker: null, Overlayer: {highlight() {}}, document: {hidden: false}, console })
function backgroundReader(chapters) {
  const docs = chapters.map(documentFor)
  const view = new SpeechView()
  let loads = 0
  view.book = {sections: docs.map(doc => ({createDocument: async () => doc}))}
  view.renderer = {
    getContents: () => [{index: 0, doc: docs[0]}],
    pinTtsSection() {},
    scrollToAnchor: async () => {},
    goTo: () => { loads++; return new Promise(() => {}) },
  }
  view.ttsBackground = true
  const nav = new TtsNavigator(() => view)
  return {view, nav, get loads() { return loads }}
}
test('locked-screen speech crosses empty and title-only chapters without loading any iframe', async () => {
  const fixture = backgroundReader(['<p>末句。</p>', '', '<h1>下一章</h1>', '<h1>第三章</h1><p>完。</p>'])
  const {view, nav} = fixture
  assert.equal(await nav.start(), '末句。')
  assert.equal(await nav.move(1), '下一章')
  // The producer calls initTTS during collection. It must retain the speech
  // document, not return to the stale chapter still visible on screen.
  view.initTTS()
  assert.equal(view.tts.currentDetail().text, '下一章')
  assert.equal(await nav.move(1), '第三章')
  assert.equal(await nav.move(1), '完。')
  assert.equal(await nav.move(1), '')
  assert.equal(fixture.loads, 0)
  assert.ok(view.progressEvents.some(event => event.cfi.startsWith('2:')))
  assert.ok(view.progressEvents.some(event => event.cfi.startsWith('3:')))
  assert.ok(view.progressEvents.every(event => Number.isFinite(event.fraction)))
  assert.ok(view.chapterEvents.some(event => event.chapterTitle === 'Chapter 2'))
  assert.ok(view.chapterEvents.some(event => event.chapterTitle === 'Chapter 3'))
})
test('background chapter navigation skips a notes-only chapter and continues body text', async () => {
  const {nav} = backgroundReader(['<p>第一章正文。</p>',
    '<section epub:type="endnotes"><h1>注释</h1><p>不朗读的内容。</p></section>',
    '<p>第二章正文。</p>'])
  assert.equal(await nav.start(), '第一章正文。')
  assert.equal(await nav.move(1), '第二章正文。')
  assert.equal(await nav.move(1), '')
})
test('foreground presentation blocked in goTo does not block speech or reset its cursor', async () => {
  const fixture = backgroundReader(['<p>末句。</p>', '<h1>下一章</h1><p>正文。</p>', '<h1>最后章</h1>'])
  const {view, nav} = fixture
  await nav.start()
  await nav.move(1)
  view.ttsBackground = false
  void view.syncTTSHighlight()
  assert.equal(fixture.loads, 1)
  assert.equal(await nav.move(1), '正文。')
  assert.equal(await nav.move(1), '最后章')
  assert.equal(await nav.move(1), '')
})
test('stop during offscreen chapter extraction rejects the late document', async () => {
  const {view, nav} = backgroundReader(['<p>末句。</p>', '<h1>下一章</h1>'])
  let complete
  view.book.sections[1].createDocument = () => new Promise(resolve => { complete = resolve })
  await nav.start()
  const moving = nav.move(1)
  await new Promise(resolve => setImmediate(resolve))
  nav.stop()
  view.initTTS(true)
  complete(documentFor('<h1>下一章</h1>'))
  assert.equal(await moving, '')
  assert.equal(view.tts, null)
})
test('failed offscreen extraction can retry the same chapter, never skipping it', async () => {
  const {view, nav} = backgroundReader(['<p>末句。</p>', '<h1>下一章</h1>'])
  const load = view.book.sections[1].createDocument
  view.book.sections[1].createDocument = async () => { throw new Error('read failed') }
  await nav.start()
  await assert.rejects(nav.move(1), /read failed/)
  view.book.sections[1].createDocument = load
  assert.equal(await nav.move(1), '下一章')
})

test('a stalled locked-screen chapter read retries the same heading and ignores its late result', async () => {
  const {view} = backgroundReader(['<p>末句。</p>', '<h1>下一章</h1><p>正文。</p>', '<p>最后章。</p>'])
  const nav = new TtsNavigator(() => view, {chapterTimeoutMs:5})
  const load = view.book.sections[1].createDocument
  let completeOldRead
  let reads = 0
  view.book.sections[1].createDocument = () => ++reads === 1
    ? new Promise(resolve => { completeOldRead = resolve }) : load()
  assert.equal(await nav.start(), '末句。')
  assert.equal(await nav.move(1), '下一章')
  assert.equal(reads, 2)
  assert.equal(await nav.move(1), '正文。')
  completeOldRead(documentFor('<h1>过期内容</h1>'))
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(view.tts.currentDetail().text, '正文。')
  assert.equal(await nav.move(1), '最后章。')
})

test('repeated chapter timeouts release the queue without reporting end-of-book or skipping text', async () => {
  const {view} = backgroundReader(['<p>末句。</p>', '<h1>不能跳过</h1>'])
  const nav = new TtsNavigator(() => view, {chapterTimeoutMs:5})
  const load = view.book.sections[1].createDocument
  let reads = 0
  view.book.sections[1].createDocument = () => { reads++; return new Promise(() => {}) }
  await nav.start()
  await assert.rejects(nav.move(1), /chapter text loading timed out/)
  assert.equal(reads, 2)
  assert.equal(view.tts.sectionIndex, 0)
  assert.equal(view.tts.currentDetail().text, '末句。')
  view.book.sections[1].createDocument = load
  assert.equal(await nav.move(1), '不能跳过')
})

test('stop immediately releases a stalled chapter and queued moves so a new session can start', {timeout:1000}, async () => {
  const {view} = backgroundReader(['<p>末句。</p>', '<h1>下一章</h1>'])
  // Much longer than the test deadline: only cancellation may unblock this.
  const nav = new TtsNavigator(() => view, {chapterTimeoutMs:10000})
  let completeOldRead
  view.book.sections[1].createDocument = () => new Promise(resolve => { completeOldRead = resolve })
  await nav.start()
  const moving = nav.move(1)
  const queued = nav.move(1)
  await new Promise(resolve => setImmediate(resolve))
  nav.stop()
  view.initTTS(true)
  assert.deepEqual(await Promise.all([moving, queued]), ['', ''])
  assert.equal(await nav.start(), '末句。')
  completeOldRead(documentFor('<h1>迟到章节</h1>'))
  await new Promise(resolve => setImmediate(resolve))
  assert.equal(view.tts.sectionIndex, 0)
  assert.equal(view.tts.currentDetail().text, '末句。')
})

// Exercise the actual private page-turn method with only its renderer IO stubbed.
const paginatorSource = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8')
const turnPage = paginatorSource.slice(paginatorSource.indexOf('  async #turnPage('), paginatorSource.indexOf('  prev(distance)'))
const PageTurn = vm.runInNewContext(`(class {
  #locked = false;
  #navigationWaiters = new Set();
  ${paginatorSource.slice(paginatorSource.indexOf('  #unlockNavigation()'), paginatorSource.indexOf('  retryNavigation()'))}
  #continuous; #container; #afterScroll() {}
  #view = null;
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
