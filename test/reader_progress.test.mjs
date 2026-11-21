import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runInNewContext } from 'node:vm'

const root = new URL('../assets/foliate-js/src/', import.meta.url)
const source = await readFile(new URL('progress.js', root), 'utf8')
const { getChapterLocation, SectionProgress } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const viewSource = await readFile(new URL('view.js', root), 'utf8')
const bookSource = await readFile(new URL('book.js', root), 'utf8')
const plain = obj => JSON.parse(JSON.stringify(obj))

test('paginated chapter pages remove sentinels and remain separate from section index', () => {
  const section = { current: 6, total: 20 }
  assert.deepEqual(getChapterLocation({ page: 9, pages: 17 }, section), { current: 9, total: 15 })
  assert.deepEqual(getChapterLocation({ page: 0, pages: 17 }, section), { current: 1, total: 15 })
  assert.deepEqual(getChapterLocation({ page: 16, pages: 17 }, section), { current: 15, total: 15 })
})
test('single-chapter scrolling counts viewport pages without subtracting sentinels', () => {
  const renderer = { scrolled: true, size: 600, viewSize: 2100, page: 0, pages: 4 }
  const section = { current: 6, total: 20 }
  assert.deepEqual(getChapterLocation(renderer, section, { fraction: 0 }), { current: 1, total: 4 })
  assert.deepEqual(getChapterLocation(renderer, section, { fraction: 600 / 2100 }), { current: 2, total: 4 })
  assert.deepEqual(getChapterLocation(renderer, section, { fraction: 1500 / 2100 }), { current: 4, total: 4 })
})
test('continuous scroll uses active chapter height, not the multi-chapter container', () => {
  const renderer = { scrolled: true, continuous: true, size: 600, viewSize: 15000 }
  const section = { current: 8, total: 120 }
  const size = 600 / 9000
  assert.deepEqual(getChapterLocation(renderer, section, { fraction: 4800 / 9000, size }), { current: 9, total: 15 })
  assert.deepEqual(getChapterLocation(renderer, section, { fraction: 8400 / 9000, size }), { current: 15, total: 15 })
})
test('short chapters have one page; unknown viewport sizes do not show chapter count', () => {
  assert.deepEqual(getChapterLocation({ scrolled: true }, { current: 8, total: 120 }, { size: 2, fraction: 0 }), { current: 1, total: 1 })
  assert.deepEqual(getChapterLocation({ scrolled: true }, { current: 8, total: 120 }), { current: 0, total: 0 })
  assert.deepEqual(getChapterLocation({}, { current: 8, total: 120 }), { current: 1, total: 1 })
})
test('chapter preview table follows the renderer size-weighted section boundaries', () => {
  const method = viewSource.slice(viewSource.indexOf('  getProgressChapters() {'), viewSource.indexOf('\n  async getTOCItemOf('))
  const View = runInNewContext(`(class {
    #sectionProgress; #tocProgress;
    constructor(sections, progress) {
      this.book = {sections}; this.#sectionProgress = progress;
      this.#tocProgress = {getProgress: index => ({label: ['封面','长章节','结尾'][index]})};
    }
    ${method}
  })`)
  const sections = [{ size: 100 }, { size: 800 }, { size: 100 }]
  const progress = new SectionProgress(sections, 1500, 1600)
  const table = plain(new View(sections, progress).getProgressChapters())
  assert.deepEqual(table, [
    { number: 1, title: '封面', start: 0, end: .1 },
    { number: 2, title: '长章节', start: .1, end: .9 },
    { number: 3, title: '结尾', start: .9, end: 1 },
  ])
  assert.equal(progress.getSection(.8)[0] + 1, table[1].number)
  assert.equal(table.find(c => .8 >= c.start && .8 < c.end).title, '长章节')
})
test('100 percent seeks the last non-empty chapter instead of a trailing non-linear item', () => {
  const progress = new SectionProgress([
    {size:100}, {size:0}, {size:800}, {size:50, linear:'no'}, {size:0}
  ], 1500, 1600)
  assert.deepEqual(progress.getSection(1), [2, 1])
  assert.equal(progress.getSection(.99)[0], 2)
  assert.equal(progress.getSection(100)[0], 2)
})
test('relocation bridge reports section counts separately from chapter page counts', () => {
  const method = bookSource.slice(bookSource.indexOf('const onRelocated = (currentInfo) => {'), bookSource.indexOf('\nconst onAnnotationClick'))
  const events = []
  const relay = runInNewContext(`${method}; onRelocated`, {
    reader: { view: { renderer: {}, book: { sections: Array(20) } } },
    style: {}, window: {}, applyVerticalPageChrome() {},
    callFlutter: (type, data) => events.push([type, plain(data)]),
  })
  relay({ cfi: 'same', fraction: .27, section: { current: 6, total: 20 },
    chapterLocation: { current: 9, total: 15 }, location: { current: 40, total: 150 },
    tocItem: { label: '第七章', href: 'chapter7.xhtml' }, bookmark: {}, readingAction: true })
  assert.equal(events[0][0], 'onRelocated')
  assert.equal(events[0][1].currentChapter, 7)
  assert.equal(events[0][1].totalChapters, 20)
  assert.equal(events[0][1].chapterCurrentPage, 9)
  assert.equal(events[0][1].chapterTotalPages, 15)
})
test('layout changes notify fresh page counts even if the CFI is unchanged', () => {
  const method = viewSource.slice(viewSource.indexOf('  #onRelocate('), viewSource.indexOf('\n  #setChapterLanguage('))
  const View = runInNewContext(`(class {
    #sectionProgress = {getProgress: () => ({section: {current: 1, total: 3}})};
    #tocProgress; #pageProgress; #index; #lastCfi; #lastChapterLocation;
    #translator = {observeVisibleRange: range => this.translationRanges.push(range)};
    #translationPrefetchPages = 0;
    #scheduleTranslationPrefetch() {}
    book = {sections: Array(3)};
    events = []; translationRanges = []; renderer = {page: 2, pages: 12};
    history = {replaceState() {}};
    getCFI() {return 'unchanged-cfi'}
    #emit(type, detail) {this.events.push([type, detail.chapterLocation])}
    relocate(range) {this.#onRelocate({reason:'anchor', index:1, fraction:.1, size:.1, range})}
    ${method}
  })`, {getChapterLocation})
  const view = new View()
  view.relocate('first range')
  view.relocate('reflowed range')
  assert.equal(view.events.length, 1, 'identical events stay deduplicated')
  assert.deepEqual(plain(view.translationRanges), ['first range', 'reflowed range'])
  view.renderer.pages = 22
  view.relocate()
  assert.equal(view.events.length, 2, 'a font-size change refreshes total pages')
  assert.deepEqual(plain(view.events[1][1]), {current: 2, total: 20})
})
test('the reader menu opens progress by default with no extra circle button', async () => {
  const source = await readFile(new URL('../lib/page/reading_page.dart', import.meta.url), 'utf8')
  assert.match(source, /identical\(_currentPage, empty\)\s*\? \(isReflowActive\s*\? reflowReader\?\.progressPanel\(\) \?\? empty\s*:\s*ProgressWidget\(\s*epubPlayerKey: epubPlayerKey\)\)\s*:\s*_currentPage/)
  assert.doesNotMatch(source, /Icons\.data_usage|progressHandler/)
})
test('both scrolling paths include the active viewport fraction in relocation', async () => {
  const source = await readFile(new URL('paginator.js', root), 'utf8')
  const method = source.slice(source.indexOf('  #afterScroll('), source.indexOf('\n  #handleScrollBoundaries('))
  assert.match(method, /size: this\.size \/ Math\.max\(1, height\)/)
  assert.match(method, /detail\.size = this\.size \/ this\.viewSize/)
})

test('a changed page limit aborts an obsolete cross-chapter prefetch plan', async () => {
  const cancel = viewSource.slice(viewSource.indexOf('  #cancelTranslationPrefetch() {'),
    viewSource.indexOf('\n  goToTextStart()'))
  const schedule = viewSource.slice(viewSource.indexOf('  setTranslationPrefetchPages('),
    viewSource.indexOf('\n  setTranslationTextStyle('))
  const timers = new Set()
  const View = runInNewContext(`(class {
    #switchingRenderer = false;
    #translationPrefetchPages; #translationPrefetchTimer; #translationPrefetchController;
    #translationPrefetchWork;
    #translator = {
      getTranslationMode: () => 'bilingual',
      addPrefetchRange: (range, pages) => this.queued.push([range, pages]),
      clearPrefetchQueue: () => {this.queued = []}
    };
    #setChapterLanguage() {}
    ${cancel}
    ${schedule}
  })`, {
    TranslationMode: {OFF: 'off'}, AbortController,
    setTimeout: run => (timers.add(run), run), clearTimeout: run => timers.delete(run),
  })
  const view = new View()
  const plans = []
  view.renderer = {
    forEachTranslationPrefetchRange(pages, publish, signal) {
      return new Promise(finish => plans.push({pages, publish, signal, finish}))
    },
  }
  const run = () => {
    const [timer] = timers
    timers.delete(timer)
    return timer()
  }
  view.setTranslationPrefetchPages(5)
  const old = run()
  plans[0].publish('current chapter')
  assert.deepEqual(plain(view.queued), [['current chapter', 5]])
  view.setTranslationPrefetchPages(1)
  assert.equal(plans[0].signal.aborted, true)
  const updated = run()
  assert.equal(plans.length, 1, 'wait for the previous measurement to release its document')
  plans[0].publish('obsolete next chapter')
  plans[0].finish()
  await old
  assert.deepEqual(plain(view.queued), [])

  plans[1].publish('next chapter')
  plans[1].finish()
  await updated
  assert.deepEqual(plain(view.queued), [['next chapter', 1]])
  view.setTranslationPrefetchPages(0)
  assert.deepEqual(plain(view.queued), [])
  assert.equal(timers.size, 0)
})

test('translation prefetch counts forward viewports and stops at the end of the laid-out chapter', async () => {
  const source = await readFile(new URL('paginator.js', root), 'utf8')
  const method = source.slice(source.indexOf('  getTranslationPrefetchRange('), source.indexOf('\n  #afterScroll('))
  const Paginator = runInNewContext(`(class {
    #preparingView = false; #destroyed = false; #continuous = null; #margin = 12;
    #view = {document: {body: {}}, element: {getBoundingClientRect: () => ({height: 761})}};
    #rtl; #getRectMapper() {return rect => rect}
    page = 2; pages = 10; size = 100; end = 450; sideProp = 'height';
    constructor(rtl = false) {this.#rtl = rtl}
    ${method}
  })`, { getVisibleRange: (_, start, end) => [start, Math.ceil(end)] })
  const reader = new Paginator()
  for (const count of [1, 2, 3, 4, 5, 9]) {
    assert.deepEqual(reader.getTranslationPrefetchRange(count), [200, 200 + Math.min(count, 5) * 100])
  }
  assert.deepEqual(new Paginator(true).getTranslationPrefetchRange(1), [400, 500])
  reader.page = 7
  assert.deepEqual(reader.getTranslationPrefetchRange(5), [700, 800])
  reader.page = 8
  assert.equal(reader.getTranslationPrefetchRange(5), null)
  assert.equal(reader.getTranslationPrefetchRange(0), null)
  reader.scrolled = true
  assert.deepEqual(reader.getTranslationPrefetchRange(2), [438, 638])
  assert.deepEqual(reader.getTranslationPrefetchRange(5), [438, 761])
})

test('translation prefetch fills the remaining page budget across consecutive short chapters', async () => {
  const source = await readFile(new URL('paginator.js', root), 'utf8')
  const method = source.slice(source.indexOf('  async forEachTranslationPrefetchRange('),
    source.indexOf('\n  #measureTranslationRange('))
  const Paginator = runInNewContext(`(class {
    #view = {}; #continuous; #index = 0; #destroyed; #preparingView; #margin = 0;
    #container = {getBoundingClientRect: () => ({width: 500, height: 300})};
    scrolled = false; page = 1; pages = 5;
    getTranslationPrefetchRange(pages) {return Math.min(pages, 2)}
    #measureLayout() {}
    #measureTranslationRange() {throw Error('expected paginated chapters')}
    async #scanTranslationChapter(section, {remaining, addRange}) {
      const used = Math.min(remaining, section.pages)
      addRange(used)
      return used
    }
    ${method}
  })`)
  const reader = new Paginator()
  reader.sections = [3, 100, 1, 4, 8].map((pages, index) =>
    ({pages, load() {}, linear: index === 1 ? 'no' : 'yes'}))
  const ranges = []
  await reader.forEachTranslationPrefetchRange(5, (range, index) => ranges.push([index, range]))
  assert.deepEqual(ranges, [[0, 2], [2, 1], [3, 2]])
})

test('fixed-layout chapter buttons skip non-linear sections and stop at book ends', async () => {
  const source = await readFile(new URL('fixed-layout.js', root), 'utf8')
  const methods = source.slice(source.indexOf('    #adjacentSection('), source.indexOf('\n    getContents()'))
  const Layout = runInNewContext(`(class {
    index = 2;
    book = {sections: [{}, {linear:'no'}, {}, {linear:'no'}, {}]};
    goTo({index}) {this.index = index}
    ${methods}
  })`)
  const layout = new Layout()
  layout.prevSection()
  assert.equal(layout.index, 0)
  layout.prevSection()
  assert.equal(layout.index, 0)
  layout.nextSection()
  assert.equal(layout.index, 2)
  layout.nextSection()
  assert.equal(layout.index, 4)
  layout.nextSection()
  assert.equal(layout.index, 4)
})
