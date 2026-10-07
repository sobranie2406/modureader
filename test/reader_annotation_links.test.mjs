import test from 'node:test'
import assert from 'node:assert/strict'
import { createRequire } from 'node:module'
import { readFile } from 'node:fs/promises'
import { runInNewContext } from 'node:vm'

const { JSDOM } = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom')
const source = await readFile(new URL('../assets/foliate-js/src/view.js', import.meta.url), 'utf8')
const imageSource = await readFile(new URL('../assets/foliate-js/src/image-footnotes.js', import.meta.url), 'utf8')
const { imageFootnoteText } = await import(`data:text/javascript;base64,${Buffer.from(imageSource).toString('base64')}`)
const method = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)))

function fixture(touch, mark) {
  const dom = new JSDOM(`<p><span id="text">已标注正文</span>
    <a href="#note" role="doc-noteref"><sup id="ref">③</sup></a>
    <a href="#note"><img id="icon" alt="注" /></a>
    <img id="image-note" class="qqreader-footnote" alt="图片注释" />
    <a href="#other"><span id="internal">章节链接</span></a>
    <a href="https://example.org/"><span id="external">外部链接</span></a>
    <a id="anchor">仅书签锚点</a>
    <span id="tail">未标注正文</span></p><aside id="note">注释内容</aside>`)
  const { document: doc } = dom.window
  const actions = []
  const range = { mark }
  const View = runInNewContext(`(class {
    #searchResults = new Map();
    book = { sections: [{}], isExternal: href => href.startsWith('https:') };
    #emit(name, detail) { actions.push({name, detail}); return false }
    install(doc) { this.#createOverlayer({doc, index: 0}); this.#handleLinks(doc, 0); this.#handleImage(doc) }
    ${method('  #createOverlayer(', '\n  async showAnnotation(')}
    ${method('  #handleLinks(', '\n  #handleImage(')}
    ${method('  #handleImage(', '\n  #handleClick(')}
  })`, {
    actions, imageFootnoteText, SEARCH_PREFIX: 'search:', console,
    window: touch ? { ontouchstart: null } : {},
    Overlayer: class {
      hitTest(event) { return event.clientX < 100 ? [mark, range] : [] }
    },
  })
  const view = new View()
  view.install(doc)
  actions.length = 0
  doc.addEventListener('click', () => actions.push({ name: 'page-click' }))
  const click = (id, x = 10, textNode = false) => {
    const el = doc.getElementById(id)
    const event = new dom.window.MouseEvent('click', { bubbles: true, cancelable: true, clientX: x })
    ;(textNode ? el.firstChild : el).dispatchEvent(event)
    return event
  }
  return { dom, doc, click, actions, range }
}

for (const touch of [false, true]) for (const mark of ['underline', 'highlight']) {
  test(`${touch ? 'touch' : 'mouse'} ${mark}: footnotes and links win over annotation capture`, () => {
    const f = fixture(touch, mark)
    try {
      const before = f.doc.body.innerHTML
      for (const [id, expected, href] of [
        ['ref', 'link', '#note'], ['icon', 'link', '#note'],
        ['image-note', 'image-footnote', null], ['internal', 'link', '#other'],
        ['external', 'external-link', 'https://example.org/'],
      ]) {
        f.actions.length = 0
        assert.equal(f.click(id).defaultPrevented, true)
        assert.deepEqual(f.actions.map(x => x.name), [expected], id)
        if (href) assert.equal(f.actions[0].detail.href, href)
      }
      f.actions.length = 0
      f.click('ref', 10, true)
      assert.deepEqual(f.actions.map(x => x.name), ['link'], 'text-node event target')
      assert.equal(f.doc.body.innerHTML, before, 'do not split marks or rewrite CFI/footnote DOM')
    } finally { f.dom.window.close() }
  })

  test(`${touch ? 'touch' : 'mouse'} ${mark}: neighboring text still opens annotation and unmarked text bubbles`, () => {
    const f = fixture(touch, mark)
    try {
      for (const id of ['text', 'anchor']) {
        f.actions.length = 0
        assert.equal(f.click(id).defaultPrevented, true)
        assert.deepEqual(f.actions.map(x => x.name), ['show-annotation'])
        assert.equal(f.actions[0].detail.value, mark)
        assert.equal(f.actions[0].detail.range, f.range)
      }
      f.actions.length = 0
      assert.equal(f.click('tail', 120).defaultPrevented, false)
      assert.deepEqual(f.actions.map(x => x.name), ['page-click'])
    } finally { f.dom.window.close() }
  })
}
