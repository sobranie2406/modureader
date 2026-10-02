import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
test('Android reader keeps ActionMode handles without changing normal browser menus', () => {
  assert.match(read('android/build.gradle'), /apply from: 'modu_reader_selection.gradle'/);
  const patch = read('android/modu_reader_selection.gradle');
  assert.match(patch, /!customSettings.disableContextMenu && contextMenu != null/);
  assert.match(patch, /Boolean.TRUE.equals/);
  assert.match(patch, /hideDefaultSystemContextMenuItems/);
  assert.match(patch, /items instanceof List && \(\(List<\?>\) items\).isEmpty\(\)/);
  assert.match(patch, /sendOnCreateContextMenuEvent\(\);\s+return actionMode;/);
  assert.match(patch, /def anchor = 'Menu actionMenu = actionMode.getMenu\(\);'/);
  assert.match(patch, /actionMode.getMenu\(\).clear\(\);/);
  assert.match(patch, /android.sourceSets.main.java.setSrcDirs\(\[generated\]\)/);
  assert.match(patch, /dependsOn\(patchTask\)/);
  assert.match(patch, /throw new GradleException/);
});
