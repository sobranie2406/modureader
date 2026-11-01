import test from 'node:test'
import assert from 'node:assert/strict'
import {readFile} from 'node:fs/promises'
import {createRequire} from 'node:module'
const require = createRequire(`${process.env.MODU_JSDOM_ROOT ?? '/private/tmp/modu-reader-regression'}/package.json`)
const {JSDOM} = require('jsdom')
const dom = new JSDOM('')
globalThis.DOMParser = dom.window.DOMParser
// Node Blob and jsdom FileReader are different implementations.
globalThis.FileReader = class {
  async readAsDataURL(blob) {
    this.result = `data:${blob.type};base64,${Buffer.from(await blob.arrayBuffer()).toString('base64')}`
    this.onload()
  }
}
const code = await readFile(new URL('../assets/foliate-js/src/image-gallery.js', import.meta.url), 'utf8')
const {BookImageGallery} = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`)
function fixture() {
  let loads = 0, releases = 0
  const sections = [3,4,3].map((count, section) => {
    const html = `<html><body>${Array.from({length:count}, (_, ordinal) =>
      `<img src="data:image/png;base64,${Buffer.from(`${section}:${ordinal}`).toString('base64')}">`).join('')}</body></html>`
    return {
      createDocument: async () => new DOMParser().parseFromString(html, 'text/html'),
      loadImageDocument: async () => {
        loads++
        const src = URL.createObjectURL(new Blob([html], {type:'text/html'}))
        return {src, release() { releases++; URL.revokeObjectURL(src) }}
      }
    }
  })
  return {book:{sections}, stats:()=>({loads,releases})}
}
test('sixth image opens in book order; both directions cross chapter boundaries lazily', async () => {
  const f = fixture(), gallery = new BookImageGallery(f.book, 1, 2)
  assert.deepEqual(await gallery.index(), {count:10, initialIndex:5})
  assert.deepEqual(f.stats(), {loads:0,releases:0})
  for (const [index, expected] of [[4,'1:1'],[0,'0:0'],[9,'2:2'],[5,'1:2']]) {
    const data = await gallery.image(index)
    assert.equal(Buffer.from(data.split(',')[1], 'base64').toString(), expected)
  }
  assert.deepEqual(f.stats(), {loads:4,releases:4})
  gallery.close()
  await assert.rejects(gallery.image(5), /Invalid image/)
})
test('failed image releases resources and does not prevent opening another image', async () => {
  const f = fixture(), gallery = new BookImageGallery(f.book, 0, 0)
  await gallery.index()
  let released = false
  f.book.sections[0].loadImageDocument = async () => {
    const src = URL.createObjectURL(new Blob(['<img src="https://example.invalid/tracking.png">']))
    return {src, release(){released = true; URL.revokeObjectURL(src)}}
  }
  await assert.rejects(gallery.image(0), /not a local/)
  assert.equal(released, true)
  assert.match(await gallery.image(9), /^data:image/)
})
test('closing while indexing stops before loading the next chapter', async () => {
  let reads = 0
  const f = fixture(), gallery = new BookImageGallery(f.book, 0, 0)
  f.book.sections[0].createDocument = async () => {
    reads++; gallery.close()
    return new DOMParser().parseFromString('<img>', 'text/html')
  }
  await assert.rejects(gallery.index(), /closed/)
  assert.equal(reads, 1)
  assert.deepEqual(f.stats(), {loads:0,releases:0})
})
test.after(() => dom.window.close())
