import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';

const source = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
const between = (a, b) => source.slice(source.indexOf(a), source.indexOf(b));
const deferred = () => { let resolve, reject; const promise = new Promise((a, b) => {resolve = a; reject = b;}); return {promise, resolve, reject}; };
const tick = () => new Promise(resolve => setImmediate(resolve));

// Execute the production transaction against controlled iframe readiness.
function fixture() {
  const gate = deferred(), views = [];
  class View {
    element = {style: {}, inert: false, removed: false, remove() {this.removed = true;}};
    document = {head: null}; destroyed = false;
    constructor({onExpand}) {this.onExpand = onExpand; views.push(this);}
    async load(src, afterLoad, beforeRender) {
      afterLoad(this.document);
      await gate.promise;
      beforeRender({vertical: false, rtl: false});
      this.onExpand();
    }
    destroy() {this.destroyed = true;}
  }
  const Renderer = runInNewContext(`class Renderer {
    #view; #retiringView; #preparingView = false; #destroyed = false;
    #vertical = false; #rtl = false;
    #index = 0; #anchor = .8; #styleMap = new WeakMap(); #pendingRelocate;
    #container = {append(){}};
    anchors = []; events = []; loads = [];
    constructor() {this.#view = new View({onExpand(){}});}
    get view() {return this.#view} get index() {return this.#index}
    get preparing() {return this.#preparingView}
    #beforeRender() {return {}}
    render() {this.anchors.push('restore')}
    scrollToAnchor(anchor) {this.#anchor = anchor; this.anchors.push(anchor)}
    dispatchEvent(e) {this.events.push(e.type)}
    display() {return this.#display({index: 1, src: 'blob:next', anchor: () => 0,
      onLoad: ({index}) => this.loads.push(index)})}
    close() {
      this.#destroyed = true; this.#view?.destroy(); this.#retiringView?.destroy();
      this.#view = null; this.#retiringView = null;
    }
    ${between('  #createView()', '  #beforeRender(')}
    ${between('  async #display(promise)', '  #canGoToIndex(')}
  }; Renderer`, {View, CustomEvent: class {constructor(type) {this.type = type}}, console});
  return {renderer: new Renderer(), views, gate};
}

test('outgoing iframe remains attached until incoming fonts/layout are ready', async () => {
  const {renderer, views, gate} = fixture(); const old = renderer.view;
  const pending = renderer.display(); await tick();
  assert.equal(old.destroyed, false); assert.equal(old.element.removed, false);
  assert.equal(old.element.inert, true);
  assert.equal(renderer.view.element.style.visibility, 'hidden');
  assert.equal(renderer.view.element.style.contentVisibility, 'visible');
  assert.equal(renderer.anchors.length, 0);
  gate.resolve(); await pending;
  assert.equal(old.destroyed, true); assert.equal(old.element.removed, true);
  assert.equal(renderer.view, views[1]); assert.equal(renderer.index, 1);
  assert.equal(renderer.view.element.style.position, 'relative');
  assert.equal(renderer.view.element.style.visibility, '');
  assert.deepEqual(Array.from(renderer.anchors), [0], 'no fallback/old-anchor relocations');
  assert.deepEqual(Array.from(renderer.events), ['create-overlayer']);
});

test('failed incoming chapter restores old document/index and leaves it interactive', async () => {
  const {renderer, views, gate} = fixture(); const old = renderer.view;
  const pending = renderer.display(); const rejected = assert.rejects(pending, /failed/);
  await tick(); gate.reject(Error('failed')); await rejected;
  assert.equal(renderer.view, old); assert.equal(renderer.index, 0);
  assert.equal(renderer.preparing, false); assert.equal(old.destroyed, false);
  assert.equal(old.element.inert, false); assert.equal(old.element.removed, false);
  assert.equal(views[1].destroyed, true); assert.equal(views[1].element.removed, true);
  assert.deepEqual(Array.from(renderer.loads), [1, 0]);
  assert.equal(renderer.events.length, 0);
});

test('closing during a chapter load cannot revive a view or emit a relocation', async () => {
  const {renderer, gate} = fixture(); const pending = renderer.display();
  await tick(); renderer.close(); gate.resolve(); await pending;
  assert.equal(renderer.view, null);
  assert.equal(renderer.events.length, 0); assert.equal(renderer.anchors.length, 0);
});

test('e-ink disables animation for every layout without changing scroll mode', async () => {
  const book = await readFile(new URL('../assets/foliate-js/src/book.js', import.meta.url), 'utf8');
  const start = book.indexOf('  const turn = {', book.indexOf('const setStyle ='));
  const end = book.indexOf("  reader.view.renderer.setAttribute('mobile-image-fit'", start);
  for (const pageTurnStyle of ['slide', 'scroll', 'noAnimation']) {
    for (const eInkMode of [true, false]) {
      const turn = runInNewContext(`${book.slice(start, end)}; turn`, {style: {pageTurnStyle, eInkMode}});
      assert.equal(turn.scroll, pageTurnStyle === 'scroll');
      assert.equal(turn.animated, !eInkMode && pageTurnStyle !== 'noAnimation');
    }
  }
});

test('chapter turns do not animate into empty boundary pages or impose a fixed wait', () => {
  const methods = between('  #scrollPrev(distance)', '  prevSection()');
  assert.match(methods, /if \(page <= 0\) return true/);
  assert.match(methods, /if \(page >= pages - 1\) return true/);
  assert.doesNotMatch(methods, /wait\(100\)/);
});
