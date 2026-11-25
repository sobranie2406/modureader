import test from 'node:test';
import assert from 'node:assert/strict';
import {selectTargets} from '../scripts/release/matrix.mjs';

test('Android and Harmony beta builds exclude every other platform', () => {
  assert.deepEqual(selectTargets('android,harmony'), {
    desktop: [], has_desktop: false, linux_appimage: false, android: true, ios: false, harmony: true,
  });
});
test('all still includes nine platforms; partial Android does not build Harmony', () => {
  const all = selectTargets('all');
  assert.equal(all.desktop.length, 7);
  assert.ok(all.android && all.ios && all.harmony);
  assert.equal(selectTargets('android').harmony, false);
  assert.throws(() => selectTargets('android,unknown'));
});
test('only Linux x64 requires the AppImage smoke test', () => {
  assert.equal(selectTargets('all').linux_appimage, true);
  assert.equal(selectTargets('android, linux-x64').linux_appimage, true);
  assert.equal(selectTargets('linux-arm64').linux_appimage, false);
  assert.equal(selectTargets('windows-x64').linux_appimage, false);
});
test('Linux x64 has one Debian build and one AppImage built on the Ubuntu baseline', () => {
  const {desktop} = selectTargets('linux-x64');
  assert.deepEqual(desktop.map(({container, appimage = false}) => [container, appimage]), [
    ['debian:trixie', false],
    ['ubuntu:24.04', true],
  ]);
});
