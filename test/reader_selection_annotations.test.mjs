import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runInNewContext } from 'node:vm'

const read = name => readFile(new URL(`../assets/foliate-js/src/${name}.js`, import.meta.url), 'utf8')
const cfiModule = `data:text/javascript;base64,${Buffer.from(await read('epubcfi')).toString('base64')}`
const source = (await read('selection-annotations')).replace("'./epubcfi.js'", JSON.stringify(cfiModule))
const { selectionAnnotationIds } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const cfi = (start, end, chapter = 4, node = 2) => `epubcfi(/6/${chapter}!/4/${node},/1:${start},/1:${end})`
const marks = [
  { id: 1, type: 'highlight', value: cfi(10, 30) },
  { id: 2, type: 'underline', value: cfi(40, 60) },
  { id: 3, type: 'highlight', value: cfi(10, 30, 6) },
  { id: 4, type: 'bookmark', value: cfi(10, 30) },
  { id: 5, type: 'highlight', value: cfi(10, 30, 4, 4) },
]

test('partial, exact, covering and cross-mark selections resolve saved IDs', () => {
  for (const [start, end, expected] of [
    [12, 15, [1]], [10, 30, [1]], [5, 35, [1]], [25, 45, [1, 2]],
    [42, 50, [2]], [0, 70, [1, 2]], [30, 40, []], [0, 10, []],
    [60, 70, []], [15, 15, []],
  ]) assert.deepEqual(selectionAnnotationIds(cfi(start, end), marks), expected)
})

test('different chapters, repeated passages, bookmarks and invalid marks are excluded', () => {
  assert.deepEqual(selectionAnnotationIds(cfi(12, 15, 6), marks), [3])
  assert.deepEqual(selectionAnnotationIds(cfi(12, 15, 4, 4), marks), [5])
  assert.deepEqual(selectionAnnotationIds(cfi(12, 15), [
    ...marks, marks[0], { id: 7, type: 'highlight', value: 'bad' },
    { id: null, type: 'highlight', value: cfi(10, 30) },
    { id: 8, type: 'highlight', value: 'epubcfi(/6/4!/4/2)' },
  ]), [1])
  assert.deepEqual(selectionAnnotationIds('bad', marks), [])
})

test('CFI text/id assertions do not require an identical range string', () => {
  const annotated = { id: 9, type: 'underline',
    value: 'epubcfi(/6/4[chapter]!/4/2[p],/1:10[before,after],/1:30)' }
  assert.deepEqual(selectionAnnotationIds(cfi(15, 20), [annotated]), [9])
})

test('selection event carries intersecting annotation IDs to Flutter', async () => {
  const book = await read('book')
  const start = book.indexOf('const handleSelection = ')
  const end = book.indexOf('\nconst AUTO_PAGE_DELAY_MS', start)
  const range = {}, events = []
  const select = runInNewContext(`${book.slice(start, end)}\nhandleSelection`, {
    getSelectionRange: () => range,
    getPosition: () => ({ left: 0, right: 1, top: 0, bottom: 1 }),
    buildRangeContextText: () => 'context', onSelectionEnd: e => events.push(e),
  })
  const view = {
    getCFI: () => cfi(12, 15),
    getSelectionAnnotationIds: cfi => selectionAnnotationIds(cfi, marks),
  }
  select(view, { getSelection: () => ({ toString: () => '局部文字' }) }, 1)
  assert.deepEqual(Array.from(events[0].annotationIds), [1])
  assert.equal(events[0].text, '局部文字')
  assert.equal(events[0].cfi, cfi(12, 15))
})
