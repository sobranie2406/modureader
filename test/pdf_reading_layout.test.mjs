import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const source = name => readFile(new URL(`../assets/foliate-js/src/${name}.js`, import.meta.url), 'utf8');
const uri = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const G = await import(uri((await source('pdf-reading-layout'))
    .replace("'./document-regions.js'", JSON.stringify(uri(await source('document-regions'))))));
const config = {version: 1, all: {preset: 'four', order: 'row-rtl'}, even: {preset: 'vertical2'}, pages: {2: {preset: 'single'}}};

test('next/previous traverse panels before original pages, including parity overrides', () => {
    let current = {page: -1, panel: 0};
    const visited = [];
    while ((current = G.adjacentPanel(config, 3, current.page, current.panel, 1))) visited.push(current);
    assert.deepEqual(visited, [
        {page: 0, panel: 0}, {page: 0, panel: 1}, {page: 0, panel: 2}, {page: 0, panel: 3},
        {page: 1, panel: 0}, {page: 1, panel: 1}, {page: 2, panel: 0}]);
    current = visited.at(-1); const reverse = [current];
    while ((current = G.adjacentPanel(config, 3, current.page, current.panel, -1))) reverse.push(current);
    assert.deepEqual(reverse, visited.toReversed());
    assert.equal(G.adjacentPanel(config, 0, -1, 0, 1), null);
});
test('resume requires original page, valid panel and exactly matching layout', () => {
    const saved = {page: 0, panel: 3, signature: G.layoutSignature(config, 0)};
    assert.equal(G.restoredPanel(config, 0, saved), 3);
    assert.equal(G.restoredPanel(config, 1, saved), 0);
    for (const panel of [-1, 4, 1.2]) assert.equal(G.restoredPanel(config, 0, {...saved, panel}), 0);
    assert.equal(G.restoredPanel({...config, all: {preset: 'four', order: 'row-ltr'}}, 0, saved), 0);
    assert.equal(G.restoredPanel(config, 0, null), 0);
});
test('layout snapshot is validated and isolated from later mutation', () => {
    const copy = G.validateReadingLayout(config);
    copy.all.preset = 'nine'; assert.equal(config.all.preset, 'four');
    for (const bad of [{}, {...config, pages: {'-1': {}}}, {...config, odd: {preset: 'bad'}}])
        assert.throws(() => G.validateReadingLayout(bad));
});
