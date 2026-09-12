import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
const source = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
const between = (a, b) => source.slice(source.indexOf(a), source.indexOf(b));
// Execute the production navigation methods with deterministic layout metrics.
const Renderer = runInNewContext(`class Renderer {
  #view = {}; #locked = false; #index = 0; #rtl = false; #vertical = false;
  #ignoreNativeScroll = false; #justAnchored = false; #isSnapping = false; #touchState;
  #container = { scrollLeft: 600, scrollTop: 0, style: {} };
  #sectionCache = { load: async index => index, setCurrent() {} };
  #styles = []; size = 600; viewSize = 3000; scrolled = false;
  sections = [{}]; visits = []; relocations = 0;
  set index(n) { this.#index = n } get index() { return this.#index }
  set rtl(value) {this.#rtl = value}
  set vertical(value) {this.#vertical = value}
  get scrollProp() {return this.scrolled && !this.#vertical ? 'scrollTop' : 'scrollLeft'}
  get start() {return Math.abs(this.#container[this.scrollProp])}
  set start(n) {this.#container[this.scrollProp] = (this.#rtl || this.#vertical ? -1 : 1) * n}
  get end() {return this.start + this.size}
  get pages() {return Math.round(this.viewSize / this.size)}
  get page() {return Math.floor((this.start + this.end) / 2 / this.size)}
  get locked() {return this.#locked}
  get signedOffset() {return this.#container[this.scrollProp]}
  hasAttribute() {return false}
  #afterScroll() {this.relocations++}
  setStyles() {} dispatchEvent() {}
  async #display(target) {
    const {index, anchor} = await target; this.#index = index; this.visits.push(index);
    this.start = this.scrolled ? (anchor?.() ? this.viewSize - this.size : 0)
      : (anchor?.() ? this.pages - 2 : 1) * this.size;
  }
  offset(n) {return this.#scrollTo(n, 'anchor')}
  pageTo(n) {return this.#scrollToPage(n, 'page')}
  go(index) {return this.#goTo({index, anchor: () => 0})}
  ${between('  snap(vx, vy, touchState)', '  #onTouchStart(e)')}
  ${between('  async #scrollTo(offset,', '  async scrollToAnchor(')}
  ${between('  #canGoToIndex(index)', '  async goTo(target)')}
  ${between('  #scrollPrev(distance)', '  prevSection()')}
}; Renderer`, {wait: async () => {}, easeOutSine: x => x, CustomEvent: class {},
  console, Promise, Math, Number});

test('single-section books stop on the last real page, including repeated clicks/keys', async () => {
  for (const rtl of [false, true]) {
    const r = new Renderer(); r.rtl = rtl; r.start = 1200;
    await r.next(); assert.equal(r.page, 3);
    const count = r.relocations;
    for (let i = 0; i < 20; i++) await r.next();
    assert.equal(r.page, 3); assert.equal(r.relocations, count);
    assert.equal(r.visits.length, 0); assert.equal(r.locked, false);
    await r.prev(); assert.equal(r.page, 2);
    await r.prev(); await r.prev(); assert.equal(r.page, 1);
  }
});

test('inertial snapping cannot park in leading/trailing sentinel pages, including RTL', async () => {
  for (const rtl of [false, true]) {
    const r = new Renderer(); r.rtl = rtl;
    r.start = 4 * r.size; // Simulate native drag overshoot.
    await r.snap(2, 0); assert.equal(r.page, 3);
    assert.equal(r.signedOffset, (rtl ? -1 : 1) * 1800);
    r.start = 0; await r.snap(-2, 0); assert.equal(r.page, 1);
    assert.equal(r.visits.length, 0);
  }
});

test('normal chapter transitions remain available; trailing non-linear sections are not extra pages', async () => {
  const r = new Renderer(); r.sections = [{}, {}, {}, {linear: 'no'}]; r.index = 1;
  r.start = 1800; await r.next(); assert.equal(r.index, 2); assert.equal(r.page, 1);
  r.start = 1800; await r.next(); assert.equal(r.index, 2); assert.equal(r.page, 3);
  r.start = 600; await r.prev(); assert.equal(r.index, 1); assert.equal(r.page, 3);
  assert.deepEqual(Array.from(r.visits), [2, 1]);
});

test('scroll mode clamps to the last screen, short chapters and vertical writing included', async () => {
  for (const length of [300, 600, 1901]) for (const vertical of [false, true]) {
    const r = new Renderer(); r.scrolled = true; r.vertical = vertical; r.viewSize = length; r.start = 0;
    for (let i = 0; i < 10; i++) await r.next();
    assert.equal(r.start, Math.max(0, length - r.size));
    const count = r.relocations;
    await r.next(); assert.equal(r.relocations, count);
    await r.offset(length); assert.equal(r.start, Math.max(0, length - r.size));
    await r.offset(-100); assert.equal(r.start, 0);
    assert.equal(r.atStart, true);
    assert.equal(r.visits.length, 0);
  }
});

test('invalid section targets do not load the first chapter through null coercion', async () => {
  const r = new Renderer();
  for (const index of [null, undefined, NaN, -1, 1, .5, '0']) await r.go(index);
  assert.equal(r.visits.length, 0);
});

const progressSource = await readFile(new URL('../assets/foliate-js/src/progress.js', import.meta.url), 'utf8');
const { SectionProgress } = await import(`data:text/javascript;base64,${Buffer.from(progressSource).toString('base64')}`);
test('reported progress never exceeds 100 percent, including the reported 1.00010227620884', () => {
  for (const sections of [[{size: 100}], [{size: 50}, {size: 100}], [{size: 0}], []]) {
    const p = new SectionProgress(sections, 10, 10);
    for (const fraction of [-.01, 0, .5, 1, 1.00010227620884, Infinity, NaN]) {
      const result = p.getProgress(Math.max(0, sections.length - 1), fraction, .25);
      assert.ok(Number.isFinite(result.fraction));
      assert.ok(result.fraction >= 0 && result.fraction <= 1);
      assert.ok(result.time.total >= 0);
      assert.ok(result.location.next <= result.location.total);
    }
  }
});
