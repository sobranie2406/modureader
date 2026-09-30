import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runInNewContext } from 'node:vm'

const book = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8')
const chunk = (start, end) => book.slice(book.indexOf(start), book.indexOf(end, book.indexOf(start)))
const Reader = runInNewContext(`(class {
  annotations = new Map(); annotationsByValue = new Map(); painted = [];
  hidden = 0; bookmarkActions = []; #bookmarkInfo;
  view = {addAnnotation: async (a, remove) => {this.painted.push([a, remove])}};
  #checkBookmark() {return true}
  #showBookmarkIcon() {}
  #hideBookmarkIcon() {this.hidden++}
  handleBookmark(remove) {this.bookmarkActions.push(remove)}
  ${chunk('  addAnnotation(annotation) {', '\n  #checkCurrentPageBookmark()')}
  ${chunk('  async removeAnnotation(cfi) {', '\n  installDesktopInput(doc)')}
})`)

const cfi = 'epubcfi(/6/4!/4/2,/1:0,/1:12)'
const other = 'epubcfi(/6/4!/4/4,/1:0,/1:9)'
const mark = (type = 'highlight', color = '#66CCFF') =>
  ({id: 41, value: cfi, type, color})

test('color and type updates replace a mark instead of accumulating copies', async () => {
  const reader = new Reader()
  for (const annotation of [mark(), mark('underline'), mark('highlight', '#FF0000')])
    await reader.addAnnotation(annotation)
  assert.equal(reader.annotations.get(1).length, 1)
  assert.equal(reader.annotations.get(1)[0].color, '#FF0000')
  assert.equal(reader.annotationsByValue.get(cfi).color, '#FF0000')
  await reader.removeAnnotation(cfi)
  assert.equal(reader.annotations.size, 0)
  assert.equal(reader.annotationsByValue.size, 0)
  assert.equal(reader.painted.at(-1)[1], true)
})

test('deletion clears old duplicate records so changing chapters cannot resurrect them', async () => {
  const reader = new Reader()
  const old = mark(), changed = mark('underline'), latest = mark('highlight', '#FF0000')
  // Reproduce the cache written by older versions, not just the fixed add path.
  reader.annotations.set(1, [old, changed, latest])
  reader.annotationsByValue.set(cfi, latest)
  await reader.removeAnnotation(cfi)
  const repainted = []
  for (const annotation of reader.annotations.get(1) ?? []) repainted.push(annotation)
  assert.equal(repainted.length, 0)
  assert.equal(reader.annotationsByValue.has(cfi), false)
  assert.equal(reader.painted.length, 1)
  assert.equal(reader.painted[0][1], true)
})

for (const type of ['highlight', 'underline']) {
  test(`deleting ${type} preserves neighboring marks and bookmarks`, async () => {
    const reader = new Reader()
    const neighbor = {id: 42, value: other, type: 'underline', color: '#FFD700'}
    const bookmark = {id: 41, value: 'epubcfi(/6/4!/4/6)', type: 'bookmark'}
    await reader.addAnnotation(mark(type))
    await reader.addAnnotation(neighbor)
    await reader.addAnnotation(bookmark)
    await reader.removeAnnotation(cfi)
    assert.deepEqual([...reader.annotationsByValue.keys()], [other, bookmark.value])
    assert.deepEqual(Array.from(reader.annotations.get(1), a => a.value), [other, bookmark.value])
    assert.equal(reader.hidden, 0)
    assert.equal(reader.bookmarkActions.length, 0)
  })
}

test('removal waits for the actual overlay and repeated deletion is harmless', async () => {
  const reader = new Reader()
  await reader.addAnnotation(mark())
  let finish
  reader.view.addAnnotation = () => new Promise(resolve => {finish = resolve})
  let completed = false
  const removed = reader.removeAnnotation(cfi).then(() => {completed = true})
  await Promise.resolve()
  assert.equal(completed, false)
  assert.equal(reader.annotationsByValue.has(cfi), true)
  finish()
  await removed
  assert.equal(completed, true)
  assert.equal(reader.annotationsByValue.has(cfi), false)
  reader.view.addAnnotation = () => {throw Error('Must not remove twice')}
  await reader.removeAnnotation(cfi)
})

test('overlay failure retains its registry so deletion can be retried', async () => {
  const reader = new Reader()
  await reader.addAnnotation(mark())
  reader.view.addAnnotation = async () => {throw Error('Transient renderer error')}
  await assert.rejects(reader.removeAnnotation(cfi), /Transient renderer error/)
  assert.equal(reader.annotationsByValue.has(cfi), true)
  assert.equal(reader.annotations.get(1).length, 1)
  reader.view.addAnnotation = async () => {}
  await reader.removeAnnotation(cfi)
  assert.equal(reader.annotationsByValue.has(cfi), false)
  assert.equal(reader.annotations.size, 0)
})

test('bookmark removal still updates its icon and native bookmark action', async () => {
  const reader = new Reader()
  await reader.addAnnotation(mark('bookmark'))
  await reader.removeAnnotation(cfi)
  assert.equal(reader.hidden, 1)
  assert.deepEqual([...reader.bookmarkActions], [true])
  assert.equal(reader.annotations.size, 0)
})
