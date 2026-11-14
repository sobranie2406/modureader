import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { runInNewContext } from 'node:vm'

const source = readFileSync(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8')
const method = source.slice(source.indexOf('  #afterScroll('), source.indexOf('  #handleScrollBoundaries('))
const platform = source.match(/  #coalesceScrollProgress = .*/)[0]
function fixture(userAgent = 'Mozilla/5.0 (Phone; OpenHarmony 5.0) ArkWeb/114') {
  let now = 0, id = 0
  const timers = new Map()
  const Reader = runInNewContext(`(class {
    #scrollRelocateTimer = null; #lastScrollRelocate = -Infinity;
    ${platform}
    #preparingView = false; #destroyed = false; #view = {}; #ignoreNativeScroll = false; #autoScrolling = false;
    #continuous; #container = {scrollTop: 0}; #margin = 0; #anchor;
    #justAnchored; #index = 0; #touchState; #touchScrolled; #pendingRelocate;
    #readingActions = {isAction: reason => reason === 'scroll' || reason === 'auto-scroll'};
    scrolled = true; size = 600; viewSize = 10000; page = 1; pages = 20;
    scans = 0; tracks = 0; events = [];
    get start() {return this.#container.scrollTop}
    #getVisibleRange() {this.scans++; return {position: this.start}}
    dispatchEvent(e) {this.events.push(e.detail)}
    move(position, reason = 'scroll', flush = false) {
      this.#container.scrollTop = position; this.#afterScroll(reason, flush)
    }
    continuous() {
      const entry = index => ({index, view: {document: {}, element: {
        getBoundingClientRect: () => ({height: 1000})}}});
      this.#continuous = {current: entry(0), top: e => e.index * 1000,
        track: () => {this.tracks++; this.#continuous.current = entry(Math.floor(this.start / 1000))}};
    }
    preparing(value) {this.#preparingView = value}
    animating(value) {this.#ignoreNativeScroll = value}
    automatic(value) {this.#autoScrolling = value}
    close() {
      ${source.slice(source.indexOf('    this.#destroyed = true', source.indexOf('  destroy() {', source.indexOf('  get isNavigating'))), source.indexOf('    clearTimeout(this.#lineSettleTimer)', source.indexOf('  get isNavigating')))}
    }
    ${method}
  })`, {
    navigator: {userAgent}, performance: {now: () => now},
    clearTimeout: key => timers.delete(key),
    setTimeout: (fn, delay) => {timers.set(++id, {fn, at: now + delay}); return id},
    getVisibleRange: (_, start, end) => ({start, end}),
    CustomEvent: class {constructor(_, {detail}) {this.detail = detail}},
  })
  const reader = new Reader()
  const advance = to => {
    while (true) {
      const next = [...timers].sort((a, b) => a[1].at - b[1].at)[0]
      if (!next || next[1].at > to) break
      now = next[1].at; timers.delete(next[0]); next[1].fn()
    }
    now = to
  }
  return {reader, advance, timers}
}

for (const ua of ['OpenHarmony', 'HarmonyOS', 'Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36']) {
  test(`120 Hz ${ua} scroll bounds text scans and reports the final viewport without scrollend support`, () => {
    const {reader, advance, timers} = fixture(ua)
    for (let frame = 0; frame < 120; frame++) {
      advance(frame * 1000 / 120); reader.move(frame * 10)
    }
    advance(1100)
    assert.equal(reader.scans, 11)
    assert.equal(reader.events.at(-1).range.position, 1190)
    assert.equal(reader.events.at(-1).fraction, .119)
    assert.equal(reader.events.at(-1).readingAction, true)
    assert.equal(timers.size, 0)
  })
}

test('chapter activation remains per frame even while precise progress is coalesced', () => {
  const {reader, advance} = fixture()
  reader.continuous(); reader.move(0); advance(10); reader.move(1100)
  assert.equal(reader.tracks, 2)
  assert.equal(reader.events.length, 1)
  advance(100)
  assert.equal(reader.events.at(-1).index, 1)
  assert.equal(reader.events.at(-1).fraction, .1)
})

for (const reason of ['navigation', 'anchor', 'page', 'line-snap']) {
  test(`${reason} supersedes pending scroll progress immediately`, () => {
    const {reader, advance, timers} = fixture()
    reader.move(0); advance(10); reader.move(20); reader.move(800, reason)
    assert.equal(reader.events.at(-1).reason, reason)
    assert.equal(reader.events.at(-1).fraction, .08)
    assert.equal(timers.size, 0)
    advance(200); assert.equal(reader.events.length, 2)
  })
}

test('scrollend flushes immediately and close cancels delayed work', () => {
  const {reader, advance, timers} = fixture()
  reader.move(0); advance(10); reader.move(20); reader.move(30, 'scroll', true)
  assert.equal(reader.events.at(-1).range.position, 30)
  assert.equal(timers.size, 0)
  reader.move(40); assert.equal(timers.size, 1)
  reader.close(); assert.equal(timers.size, 0)
  advance(200); assert.equal(reader.events.length, 2)
  assert.match(source, /addEventListener\('scrollend',[\s\S]*?#afterScroll\('scroll', true\)/)
})

test('delayed work cannot inspect a chapter being replaced', () => {
  const {reader, advance} = fixture()
  reader.move(0); advance(10); reader.move(20); reader.preparing(true)
  advance(200); assert.equal(reader.scans, 1)
  reader.preparing(false); reader.move(1000, 'navigation')
  assert.equal(reader.events.at(-1).range.position, 1000)
})

test('an animated page turn suppresses old scroll work until its final position commits', () => {
  const {reader, advance} = fixture()
  reader.move(0); advance(10); reader.move(20); reader.animating(true)
  advance(100); assert.equal(reader.scans, 1)
  reader.move(600, 'page'); reader.animating(false)
  assert.equal(reader.events.at(-1).range.position, 600)
  assert.equal(reader.events.length, 2)
})

test('automatic scrolling suppresses native per-frame scans but explicitly saves its current position', () => {
  const {reader,advance}=fixture();
  reader.move(0);advance(10);reader.move(20);reader.automatic(true);
  advance(100);assert.equal(reader.scans,1);
  for(let i=0;i<30;i++)reader.move(i*3);
  assert.equal(reader.scans,1);
  reader.move(100,'auto-scroll',true);
  assert.equal(reader.events.at(-1).range.position,100);
  assert.equal(reader.events.at(-1).readingAction,true);
  assert.equal(reader.events.length,2);
});

test('Apple and desktop scrolling, and Android/Harmony paginated mode keep existing cadence', () => {
  for (const ua of ['Android', 'iPhone', 'Macintosh', 'Windows', 'OpenHarmony']) {
    const {reader} = fixture(ua)
    if (ua === 'OpenHarmony' || ua === 'Android') reader.scrolled = false
    for (let i = 0; i < 10; i++) reader.move(i)
    assert.equal(reader.scans, 10, ua)
  }
})
