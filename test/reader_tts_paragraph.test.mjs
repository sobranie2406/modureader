import test from 'node:test'
import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { readFile } from 'node:fs/promises'
import vm from 'node:vm'
const { JSDOM } = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom')
const load = async name => import(`data:text/javascript;base64,${Buffer.from(await readFile(new URL(`../assets/foliate-js/src/${name}`, import.meta.url))).toString('base64')}`)
const { TTS } = await load('tts.js')
const { TtsNavigator } = await load('tts-navigation.js')
function docFor(html) {
    const dom = new JSDOM(`<body>${html}</body>`)
    globalThis.NodeFilter = dom.window.NodeFilter
    globalThis.Range = dom.window.Range
    return dom.window.document
}
const speech = (doc, highlight = () => null) => new TTS(doc, null, highlight,
    range => range.toString(), { paragraphMode: true })
function all(tts) {
    const out = []
    for (let text = tts.start(); text != null; text = tts.next()) out.push(text)
    return out
}

test('groups only adjacent sentences in one paragraph, never headings/list entries', () => {
    const doc = docFor('<h1>标题。</h1><p>第一句。<em>第二句！</em>“第三句？”</p><p>另一段。</p><ul><li>项目一。</li><li>项目二。</li></ul>')
    assert.deepEqual(all(speech(doc)), ['标题。', '第一句。第二句！“第三句？”', '另一段。', '项目一。', '项目二。'])
    assert.deepEqual(all(new TTS(doc, null, () => null)), ['标题。', '第一句。', '第二句！', '“第三句？”', '另一段。', '项目一。', '项目二。'])
})

test('groups at most four sentences and peek/previous use the same boundaries', () => {
    const tts = speech(docFor('<p>一。二。三。四。五。六。</p><p>下段。</p>'))
    assert.equal(tts.start(), '一。二。三。四。')
    assert.deepEqual(tts.collectDetails(3, {includeCurrent: true}).map(x => x.text),
        ['一。二。三。四。', '五。六。', '下段。'])
    assert.equal(tts.resume(), '一。二。三。四。')
    assert.equal(tts.next(true), '五。六。')
    assert.equal(tts.prev(true), '一。二。三。四。')
    assert.equal(tts.end(), '下段。')
})

test('long sentences spanning inline elements split into bounded ranges without losing text', () => {
    const doc = docFor(`<p>${'甲'.repeat(151)}，<b>${'乙'.repeat(330)}</b>${'丙'.repeat(100)}。</p>`)
    const expected = doc.querySelector('p').textContent
    const parts = all(speech(doc))
    assert.ok(parts.length >= 3)
    assert.ok(parts.every(x => x.length <= 240))
    assert.equal(parts.join(''), expected)
    assert.ok(parts[0].endsWith('，'))
})

test('long unpunctuated text never splits surrogate pairs', () => {
    const expected = '甲'.repeat(239) + '😀'.repeat(250) + '乙'
    const parts = all(speech(docFor(`<p>${expected}</p>`)))
    assert.equal(parts.join(''), expected)
    assert.ok(parts.every(x => x.length <= 240 && !/^[\uDC00-\uDFFF]|[\uD800-\uDBFF]$/.test(x)))
})

test('hidden annotations are excluded before grouping/length checks, DOM unchanged', () => {
    const doc = docFor(`<p>首句。<span hidden>${'注释'.repeat(400)}</span>第二句<a epub:type="noteref" href="#n">[1]</a>。</p><aside epub:type="footnote" id="n">隐藏注释。</aside><p>第三句。</p>`)
    const before = doc.body.innerHTML
    assert.deepEqual(all(speech(doc)), ['首句。第二句。', '第三句。'])
    assert.equal(doc.body.innerHTML, before)
})

test('selected-text start trims only the first group and highlight matches the spoken remainder', () => {
    const doc = docFor('<p>跳过。<b>从这里。再一句。</b>最后一句。</p><p>下一段。</p>')
    const selected = doc.createRange()
    selected.setStart(doc.querySelector('b').firstChild, 0)
    selected.collapse(true)
    const highlights = []
    const tts = speech(doc, range => { highlights.push(range.toString()); return range.toString() })
    assert.equal(tts.from(selected, {exactStart: true}), '从这里。再一句。最后一句。')
    assert.equal(tts.currentDetail().text, highlights.at(-1))
    assert.equal(tts.collectDetails(2, {includeCurrent: true})[0].text, highlights.at(-1))
    assert.equal(tts.highlightCfi(highlights.at(-1)).text, '从这里。再一句。最后一句。')
    assert.equal(tts.next(true), '下一段。')
    assert.equal(tts.highlightCfi('跳过。从这里。再一句。最后一句。'), null)
    assert.equal(tts.prev(true), '跳过。从这里。再一句。最后一句。')
})

test('each paragraph range is the highlighted range, not an estimated sentence', () => {
    const marked = []
    const tts = speech(docFor('<p>一。二。</p><p>三。四。</p>'), r => marked.push(r.toString()))
    assert.equal(tts.start(), '一。二。')
    assert.equal(tts.next(true), '三。四。')
    assert.deepEqual(marked, ['一。二。', '三。四。'])
    assert.equal(tts.highlightCfi('一。二。'), null)
})

test('paragraph mode crosses detached chapters without skipping titles or empty chapters', async () => {
    const docs = [docFor('<p>一。二。</p>'), docFor('<p>……</p>'), docFor('<h1>新章</h1><p>三。四。</p>')]
    const view = {
        book: {sections: docs.map(() => ({ createDocument() {} }))},
        tts: speech(docs[0]),
        async loadTTSSection(index, isCurrent) {
            if (!isCurrent()) return false
            this.tts = speech(docs[index]); this.tts.sectionIndex = index
            return true
        },
        initTTS() {}, renderer: {pinTtsSection() {}},
    }
    view.tts.sectionIndex = 0
    const nav = new TtsNavigator(() => view)
    assert.equal(await nav.start(), '一。二。')
    assert.equal(await nav.move(1), '新章')
    assert.equal(await nav.move(1), '三。四。')
    assert.equal(await nav.move(-1), '新章')
    assert.equal(await nav.move(-1), '一。二。')
})

test('service mode switch invalidates old cursor once and persists across chapters', async () => {
    const source = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8')
    const script = source.slice(source.indexOf('window.ttsSetParagraphMode ='), source.indexOf('window.ttsSetBackground ='))
    let stopped = 0, resets = 0
    const view = {initTTS(stop) { assert.equal(stop, true); resets++ }}
    const context = {window: {}, reader: {view}, ttsNavigator: {stop() {stopped++}}}
    vm.runInNewContext(script, context)
    context.window.ttsSetParagraphMode(true)
    context.window.ttsSetParagraphMode(true)
    assert.equal(view.ttsParagraphMode, true)
    assert.equal(stopped, 1)
    assert.equal(resets, 1)
    context.window.ttsSetParagraphMode(false)
    assert.equal(view.ttsParagraphMode, false)
    assert.equal(stopped, 2)
    const dart = await readFile(new URL('../lib/page/book_player/epub_player.dart', import.meta.url), 'utf8')
    assert.match(dart, /getTtsService\(Prefs\(\).ttsService\).isOnline/)
    const viewSource = await readFile(new URL('../assets/foliate-js/src/view.js', import.meta.url), 'utf8')
    assert.match(viewSource, /paragraphMode: this.ttsParagraphMode === true/)
})
