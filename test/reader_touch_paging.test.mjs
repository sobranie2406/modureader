import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
const source = await readFile(new URL('../assets/foliate-js/src/touch-paging.js', import.meta.url), 'utf8');
const { touchPageDirection: direction } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const gesture = (dx, dy = 0, extra = {}) => direction({ dx, dy, duration: 300, size: 390, ...extra });

test('small tap jitter does not turn even when fast', () => {
  for (const dx of [-11, -5, 0, 5, 11]) assert.equal(gesture(dx, 0, { duration: 1 }), 0);
  assert.equal(gesture(20), 0);
});
test('short flick or long slow swipe turns exactly one page', () => {
  assert.equal(gesture(-20, 0, { duration: 40 }), 1);
  assert.equal(gesture(20, 0, { duration: 40 }), -1);
  assert.equal(gesture(-80, 8, { duration: 1000 }), 1);
  assert.equal(gesture(900), -1);
});
test('vertical and ambiguous diagonal motion does not page horizontal books', () => {
  for (const [x, y] of [[3, 100], [-40, 40], [40, 40], [-70, 80]])
    assert.equal(gesture(x, y), 0);
});
test('RTL and vertical-writing use their own page axis', () => {
  assert.equal(gesture(-80, 0, { rtl: true }), -1);
  assert.equal(gesture(80, 0, { rtl: true }), 1);
  assert.equal(gesture(0, -80, { vertical: true, rtl: true }), 1);
  assert.equal(gesture(80, 0, { vertical: true }), 0);
});
test('cancelled pinch/selection gestures and invalid layout never page', () => {
  assert.equal(gesture(-100, 0, { cancelled: true }), 0);
  assert.equal(gesture(-100, 0, { size: 0 }), 0);
  assert.equal(gesture(NaN), 0);
});
test('mobile-only pagination locks both scroll axes; quick mark keeps capture priority', async () => {
  const paginator = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
  assert.match(paginator, /else if \(this.mobileTouchPaging\) \{[\s\S]*?overflowX = 'hidden'[\s\S]*?overflowY = 'hidden'/);
  assert.match(paginator, /touchcancel/);
  assert.match(paginator, /doc.addEventListener\('pointerdown', rememberSelection, true\)/);
  assert.match(paginator, /this.#selectionAtPointerDown \|\|/);
  assert.match(paginator, /touchPageDirection\(\{ dx, dy/);
  const quick = await readFile(new URL('../assets/foliate-js/src/quick-mark.js', import.meta.url), 'utf8');
  assert.match(quick, /capture: true, passive: false/);
  assert.match(quick, /stopImmediatePropagation/);
});

test('tap-only actual handlers block swipes and pull gestures but preserve taps', async () => {
  const paginator = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
  const handlers = paginator.slice(paginator.indexOf('  #onTouchStart(e) {'), paginator.indexOf('  // allows one to process rects'));
  const Reader = runInNewContext(`class Reader {
    #touchState; #touchScrolled; #selectionAtPointerDown = false;
    #suppressTouchClickUntil = 0; #locked = false; #isSnapping = false;
    #pendingRelocate; #rtl = false; #container = {scrollLeft:390,scrollTop:0};
    mobileTouchPaging = true; tapOnlyPageTurn = true; scrolled = false;
    scrollProp = 'scrollLeft'; page = 1; size = 390; events = []; turns = 0;
    dispatchEvent(e) {this.events.push(e.type)}
    snap() {this.turns++;return Promise.resolve()}
    #turnPage() {this.turns++;return Promise.resolve()}
    get offset() {return this.#container.scrollLeft}
    get suppressed() {return this.#suppressTouchClickUntil > Date.now()}
    start(e) {this.#onTouchStart(e)} move(e) {this.#onTouchMove(e)}
    end(e) {this.#onTouchEnd(e)}
    ${handlers}
  }; Reader`, {window:{getSelection:()=>''},globalThis:{visualViewport:{scale:1}},
    CustomEvent:class {constructor(type){this.type=type}},
    requestAnimationFrame:fn=>fn(),Date,Promise,touchPageDirection:direction});
  for(const [dx,dy,drag] of [[-100,0,true],[100,0,true],[0,100,true],[-50,-80,true],[0,0,false],[3,2,false]]) {
    const reader=new Reader();
    const event=(x,y,end=false)=>({changedTouches:[{screenX:x,screenY:y}],
      touches:end?[]:[{screenX:x,screenY:y}],timeStamp:100,cancelable:true,
      prevented:false,preventDefault(){this.prevented=true}});
    reader.start(event(200,300));reader.move(event(200+dx,300+dy));
    const end=event(200+dx,300+dy,true);reader.end(end);
    assert.equal(reader.offset,390);assert.equal(reader.turns,0);
    assert.equal(reader.events.length,0);
    assert.equal(end.prevented,drag);assert.equal(reader.suppressed,drag);
  }
});
