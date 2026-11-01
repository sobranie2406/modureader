import test from 'node:test';
import assert from 'node:assert/strict';
import {selectTargets} from '../scripts/release/matrix.mjs';

test('Android and Harmony beta builds exclude every other platform', () => {
  assert.deepEqual(selectTargets('android,harmony'), {
    desktop: [], has_desktop: false, android: true, ios: false, harmony: true,
  });
});
test('all still includes nine platforms; partial Android does not build Harmony', () => {
  const all = selectTargets('all');
  assert.equal(all.desktop.length, 6);
  assert.ok(all.android && all.ios && all.harmony);
  assert.equal(selectTargets('android').harmony, false);
  assert.throws(() => selectTargets('android,unknown'));
});
