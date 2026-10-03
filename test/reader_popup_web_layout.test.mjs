import test from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import {createRequire} from 'node:module'

const {JSDOM} = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom')
const dart = await readFile(new URL('../lib/widgets/webview/popup_page_layout.dart', import.meta.url), 'utf8')
const template = dart.split("return '''")[1].split("''';")[0]
const script = percent => {
  const scale = Math.min(200, Math.max(50, percent)) / 100
  return template.replaceAll('$scale', String(scale)).replaceAll('${100 / scale}', String(100 / scale))
}
function page(html = '<p>正文</p>') {
  const dom = new JSDOM(html, {runScripts:'outside-only', pretendToBeVisual:true})
  let pending = []
  dom.window.requestAnimationFrame = f => pending.push(f)
  return {dom, doc:dom.window.document, run:percent=>dom.window.eval(script(percent)),
    frame() {const callbacks = pending; pending = []; callbacks.forEach(f=>f())}}
}

test('zoom reflows width, adds a device viewport and leaves input values intact', () => {
  const p = page('<meta name="viewport" content="width=1280"><textarea>未发送的草稿</textarea>')
  for (const percent of [50, 100, 200, 80]) {
    p.run(percent)
    assert.equal(p.doc.documentElement.style.width, `${100/(percent/100)}vw`)
    assert.equal(p.doc.querySelector('meta[name=viewport]').content, 'width=device-width, initial-scale=1')
    assert.equal(p.doc.querySelector('textarea').value, '未发送的草稿')
  }
  assert.equal(p.doc.querySelectorAll('#modu-popup-page-layout').length, 1)
  const css = p.doc.querySelector('style').textContent
  assert.match(css, /overflow-y: auto/)
  assert.match(css, /white-space: pre-wrap/)
  assert.match(css, /flex-wrap: wrap/)
  assert.doesNotMatch(script(100), /flutter_inappwebview|fetch\(|XMLHttpRequest/)
  p.dom.window.close()
})

test('overflowing grids stack, then restore original columns when space returns', () => {
  const p = page('<div id="grid" style="display:grid;grid-template-columns:500px 500px"><p>一</p><p>二</p></div>')
  const grid = p.doc.querySelector('#grid')
  let width = 320
  Object.defineProperty(grid, 'clientWidth', {get:()=>width})
  Object.defineProperty(grid, 'scrollWidth', {get:()=>1000})
  p.run(100); p.frame()
  assert.ok(grid.hasAttribute('data-modu-popup-grid'))
  width = 1200
  p.dom.window.dispatchEvent(new p.dom.window.Event('resize')); p.frame()
  assert.equal(grid.hasAttribute('data-modu-popup-grid'), false)
  assert.equal(grid.style.gridTemplateColumns, '500px 500px')
  p.dom.window.close()
})

test('SPA content changes are scheduled without installing duplicate observers', async () => {
  const p = page()
  p.run(100)
  const schedule = p.dom.window.__moduPopupLayout
  p.run(150)
  assert.equal(p.dom.window.__moduPopupLayout, schedule)
  p.frame()
  const grid = p.doc.createElement('div')
  grid.style.display = 'grid'
  Object.defineProperty(grid, 'clientWidth', {value:300})
  Object.defineProperty(grid, 'scrollWidth', {value:900})
  p.doc.body.appendChild(grid)
  await Promise.resolve()
  p.frame()
  assert.ok(grid.hasAttribute('data-modu-popup-grid'))
  p.dom.window.close()
})
