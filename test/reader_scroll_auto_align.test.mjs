import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import vm from 'node:vm'

const source = readFileSync(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8')
const methods = source.slice(source.indexOf('  #scheduleLineSettle() {'), source.indexOf('  #scrollNext(distance) {'))

function harness() {
  let pending
  const calls = []
  const context = vm.createContext({
    setTimeout: callback => { pending = callback; return 1 },
    clearTimeout: () => { pending = undefined },
    lineAlignedOffset: (...args) => { calls.push(args); return args[1] + 8 },
  })
  const reader = vm.runInContext(`new (class {
    #lineSettleTimer; #needsLineSettle = true; #vertical = false;
    #destroyed = false; #scrollPointerDown = false; #touchState = null;
    #locked = false; #ignoreNativeScroll = false; #scrollDirection = 1;
    #settledAt; #continuous; #margin = 0; #view = { document: {} };
    scrolled = true; start = 100; size = 500; viewSize = 2000;
    attribute = null; selected = ''; scrolls = [];
    getAttribute(name) {
      if (name !== 'scroll-auto-align') throw Error(name);
      return this.attribute;
    }
    getContents() { return [{doc: {getSelection: () => this.selected}}] }
    #scrollTo(...args) { this.scrolls.push(args) }
    align(...args) { return this.#alignScrollTarget(...args) }
    scrollPageTarget(target) {return target}
    schedule(direction = 1) { this.#needsLineSettle = true; this.#scrollDirection = direction; this.#scheduleLineSettle() }
    ${methods}
  })`, context)
  return { reader, calls, flush: () => { const task = pending; pending = undefined; task?.() } }
}

test('missing preference preserves existing alignment in both directions', () => {
  const { reader, calls } = harness()
  assert.equal(reader.align(180, 100), 188)
  assert.equal(reader.align(20, 100), 28)
  assert.deepEqual(calls.map(args => args.slice(1)), [[180, 100, 500, false], [20, 100, 500, false]])
})

test('disabled alignment preserves exact targets without measuring text', () => {
  const { reader, calls, flush } = harness()
  reader.attribute = 'false'
  assert.equal(reader.align(180, 100), 180)
  assert.equal(reader.align(20, 100), 20)
  reader.schedule()
  flush()
  assert.equal(calls.length, 0)
  assert.equal(reader.scrolls.length, 0)
})

test('disabling a queued settle prevents delayed snapping', () => {
  const { reader, calls, flush } = harness()
  reader.schedule()
  reader.attribute = 'false'
  flush()
  assert.equal(calls.length, 0)
  assert.equal(reader.scrolls.length, 0)
})

for (const direction of [-1, 1]) {
  test(`re-enabling retains original directional settling: ${direction}`, () => {
    const { reader, calls, flush } = harness()
    reader.attribute = 'false'
    reader.schedule(direction)
    reader.attribute = 'true'
    reader.schedule(direction)
    flush()
    assert.deepEqual(calls[0].slice(1), [100, 100 - direction, 500, true])
    assert.equal(reader.scrolls[0][0], 108)
    assert.equal(reader.scrolls[0][1], 'line-snap')
  })
}

test('active text selection still prevents idle snapping', () => {
  const { reader, calls, flush } = harness()
  reader.selected = 'selected text'
  reader.schedule()
  flush()
  assert.equal(calls.length, 0)
})

test('live preference updates only the renderer attribute without reloading', () => {
  const book = readFileSync(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8')
  const setter = book.slice(book.indexOf('window.setScrollAutoAlign ='), book.indexOf('\nwindow.nextSection'))
  const attributes = new Map()
  const context = { window: {}, style: {}, reader: { view: { renderer: {
    setAttribute: (name, value) => attributes.set(name, value),
  } } } }
  vm.runInNewContext(setter, context)
  for (const enabled of [false, true]) {
    context.window.setScrollAutoAlign(enabled)
    assert.equal(context.style.scrollAutoAlign, enabled)
    assert.equal(attributes.get('scroll-auto-align'), String(enabled))
  }
  assert.match(book, /'scroll-auto-align': String\(style\.scrollAutoAlign !== false\)/)
})
