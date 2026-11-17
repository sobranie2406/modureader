import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';

const source = await readFile(new URL('../assets/foliate-js/src/paginator.js', import.meta.url), 'utf8');
const method = source.slice(source.indexOf('  flushAutoScrollPosition() {'),
  source.indexOf('  snap(vx, vy, touchState) {'));

function fixture(automatic, continuous = true) {
  const events = [];
  const window = {current: 'before-drag', track() {
    events.push('track');
    this.current = 'current-viewport';
  }};
  const reader = runInNewContext(`new (class {
    #autoScrolling = automatic;
    #continuous = window;
    #afterScroll(reason, flush) { report(reason, flush, this.#continuous?.current) }
    ${method}
  })`, {automatic, window: continuous ? window : null,
    report: (...values) => events.push(values)});
  return {reader, events};
}

test('resume flush tracks the manually reached chapter before saving its position', () => {
  const f = fixture(false);
  f.reader.flushAutoScrollPosition();
  assert.deepEqual(f.events, ['track', ['auto-scroll', true, 'current-viewport']]);
});

test('regular automatic progress does not repeat manual chapter tracking', () => {
  const f = fixture(true);
  f.reader.flushAutoScrollPosition();
  assert.deepEqual(f.events, [['auto-scroll', true, 'before-drag']]);
});

test('single-chapter scrolling still flushes its current position', () => {
  const f = fixture(false, false);
  f.reader.flushAutoScrollPosition();
  assert.deepEqual(f.events, [['auto-scroll', true, undefined]]);
});
