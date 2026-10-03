import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const read = file => readFile(new URL(`../assets/foliate-js/src/${file}.js`, import.meta.url), 'utf8');
const uri = code => `data:text/javascript;base64,${Buffer.from(code).toString('base64')}`;
const geometryUri = uri(await read('document-regions'));
const G = await import(geometryUri);
const { regionRenderPlan, createPdfRegionRenderer } = await import(uri(
    (await read('pdf-region-renderer')).replace("'./document-regions.js'", JSON.stringify(geometryUri))
      .replace("'./document-image-processing.js'", JSON.stringify(uri(await read('document-image-processing'))))));
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, `${a} != ${b}`);

test('crop and quarter-turn coordinate chains are reversible', () => {
    const crop = { x: .12, y: .18, width: .7, height: .65 };
    for (const rotation of [-90, 0, 90, 180, 270, 450]) {
        for (const point of [{ x: .12, y: .18 }, { x: .4, y: .6 }, { x: .82, y: .83 }]) {
            const restored = G.regionToSource(G.sourceToRegion(point, crop, rotation), crop, rotation);
            near(restored.x, point.x); near(restored.y, point.y);
        }
        const restored = G.rotateRegion(G.rotateRegion(crop, rotation), -rotation);
        for (const k of Object.keys(crop)) near(restored[k], crop[k]);
    }
});
test('invalid regions, rotations and orders are rejected instead of silently clipping', () => {
    for (const region of [{ x: -1, y: 0, width: 1, height: 1 }, { x: 0, y: 0, width: 0, height: 1 },
        { x: .5, y: 0, width: 1, height: 1 }, { x: NaN, y: 0, width: 1, height: 1 }])
        assert.throws(() => G.validateRegion(region), RangeError);
    assert.throws(() => G.normalizeRotation(45), RangeError);
    assert.throws(() => G.splitRegions({ order: 'random' }), RangeError);
    assert.throws(() => G.splitRegions({ preset: 'missing' }), RangeError);
});
test('all seven grid presets partition only the crop and preserve original coordinates', () => {
    const crop = { x: .1, y: .2, width: .8, height: .6 };
    for (const [preset, [columns, rows]] of Object.entries(G.GRID_PRESETS)) {
        const regions = G.splitRegions({ crop, preset });
        assert.equal(regions.length, columns * rows);
        near(regions.reduce((area, r) => area + r.width * r.height, 0), crop.width * crop.height);
        for (const r of regions) {
            G.validateRegion(r);
            assert.ok(r.x >= crop.x && r.y >= crop.y);
            assert.ok(r.x + r.width <= crop.x + crop.width + 1e-9);
        }
    }
});
test('row/column and left/right reading orders are distinct; stacked pages stay top to bottom', () => {
    const order = value => G.splitRegions({ preset: 'four', order: value }).map(r => `${r.row}${r.column}`);
    assert.deepEqual(order('row-ltr'), ['00', '01', '10', '11']);
    assert.deepEqual(order('row-rtl'), ['01', '00', '11', '10']);
    assert.deepEqual(order('column-ltr'), ['00', '10', '01', '11']);
    assert.deepEqual(order('column-rtl'), ['01', '11', '00', '10']);
    assert.deepEqual(G.splitRegions({ preset: 'vertical2', order: 'row-rtl' }).map(r => r.row), [0, 1]);
});
test('original page override wins over odd/even and whole-document defaults', () => {
    const config = { all: 'all', odd: 'odd', even: 'even', pages: { 2: 'page3' } };
    assert.equal(G.pageLayout(config, 0), 'odd');
    assert.equal(G.pageLayout(config, 1), 'even');
    assert.equal(G.pageLayout(config, 2), 'page3');
    assert.equal(G.pageLayout({ all: 'all' }, 4), 'all');
    assert.equal(G.pageLayout(null, 0), null);
    assert.throws(() => G.pageLayout(config, -1), RangeError);
});

function mockPage({ width = 600, height = 800, rotation = 0, render } = {}) {
    return { getViewport: ({ scale, rotation: turn = rotation }) => ({
        width: (turn % 180 === rotation % 180 ? width : height) * scale,
        height: (turn % 180 === rotation % 180 ? height : width) * scale,
        rotation: turn, scale,
    }), render: render ?? (() => ({ promise: Promise.resolve(), cancel() {} })) };
}
test('1500% zoom renders a viewport-sized region, not a 15x full-page bitmap', () => {
    const plan = regionRenderPlan(mockPage(), { width: 1200, height: 1600,
        region: { x: .4, y: .3, width: 1 / 15, height: 1 / 15 } });
    assert.equal(plan.width, 1200); assert.equal(plan.height, 1600);
    assert.equal(plan.viewport.width, 18000); assert.equal(plan.viewport.height, 24000);
    assert.deepEqual(plan.transform, [1, 0, 0, 1, -7200, -7200]);
});
test('render budgets handle huge outputs and panoramic pages, preserving page rotation', () => {
    for (const [width, height] of [[600, 800], [50000, 300], [30, 60000]]) {
        const plan = regionRenderPlan(mockPage({ width, height, rotation: 90 }), {
            rotation: 270, width: 1e6, height: 1e6 });
        assert.ok(plan.width * plan.height <= 2097152);
        assert.ok(Math.max(plan.width, plan.height) <= 2048);
        assert.equal(plan.viewport.rotation, 0);
    }
    assert.throws(() => regionRenderPlan(mockPage(), { width: Infinity }), RangeError);
});

function harness(page = mockPage(), options = {}) {
    const canvases = [];
    const source = createPdfRegionRenderer({ numPages: 6, getPage: async () => page }, {
        createCanvas: () => { const canvas = { width: 0, height: 0, getContext: () => ({}) }; canvases.push(canvas); return canvas; },
        encode: async () => new Blob(['image']), ...options,
    });
    return { source, canvases };
}
test('actual render request clips with transform, caches hits, and releases its canvas', async () => {
    let calls = 0;
    const { source, canvases } = harness(mockPage({ render: options => {
        calls++; assert.deepEqual(options.transform, [1, 0, 0, 1, -1200, -1200]);
        return { promise: Promise.resolve(), cancel() {} };
    }}));
    const request = { page: 0, region: { x: .25, y: .1875, width: .25, height: .1875 } };
    const result = await source.render(request);
    assert.equal(result.blob.size, 5); assert.equal(calls, 1);
    assert.equal((await source.render(request)).blob, result.blob);
    assert.equal(calls, 1); assert.equal(canvases[0].width, 0); assert.equal(canvases[0].height, 0);
    source.clear(); await source.render(request); assert.equal(calls, 2);
});
test('rapid changes cancel active tasks and only the latest queued render allocates', async () => {
    let active, cancelled = 0, calls = 0;
    const { source, canvases } = harness(mockPage({ render: () => {
        calls++;
        if (calls > 1) return { promise: Promise.resolve(), cancel() {} };
        return { promise: new Promise((resolve, reject) => { active = reject; }),
            cancel: () => { cancelled++; active(new Error('cancelled')); } };
    }}));
    const first = source.render({ page: 0 });
    const rejectsFirst = assert.rejects(first, { name: 'AbortError' });
    await new Promise(resolve => setImmediate(resolve));
    const second = source.render({ page: 1 });
    const rejectsSecond = assert.rejects(second, { name: 'AbortError' });
    const last = source.render({ page: 2 });
    await Promise.all([rejectsFirst, rejectsSecond]);
    assert.equal((await last).page, 2); assert.equal(cancelled, 1); assert.equal(canvases.length, 2);
    assert.ok(canvases.every(c => c.width === 0 && c.height === 0));
});
test('closing during encoding drops stale output and frees bitmap; reopening works', async () => {
    let finish;
    const { source, canvases } = harness(mockPage(), { encode: () => new Promise(resolve => { finish = resolve; }) });
    const first = source.render({ page: 0 });
    const rejected = assert.rejects(first, { name: 'AbortError' });
    await new Promise(resolve => setImmediate(resolve));
    source.clear(); finish(new Blob(['old'])); await rejected;
    assert.equal(canvases[0].width, 0);
    const next = source.render({ page: 0 });
    await new Promise(resolve => setImmediate(resolve));
    finish(new Blob(['new'])); assert.equal(await (await next).blob.text(), 'new');
});
test('external cancellation, invalid pages and encoding failures never leave live canvases', async () => {
    const controller = new AbortController(); controller.abort();
    const { source, canvases } = harness(mockPage(), { encode: async () => { throw new Error('encode'); } });
    await assert.rejects(source.render({ page: 0 }, { signal: controller.signal }), { name: 'AbortError' });
    await assert.rejects(source.render({ page: -1 }), RangeError);
    await assert.rejects(source.info(6), RangeError);
    await assert.rejects(source.render({ page: 0 }), /encode/);
    assert.equal(canvases.length, 1); assert.equal(canvases[0].width, 0);
});
test('region cache evicts old pages and distinguishes rotation, rectangle and output size', async () => {
    let calls = 0;
    const { source } = harness(mockPage({ render: () => {
        calls++; return { promise: Promise.resolve(), cancel() {} };
    }}));
    for (let page = 0; page < 6; page++) await source.render({ page });
    await source.render({ page: 5 }); assert.equal(calls, 6);
    await source.render({ page: 0 }); assert.equal(calls, 7);
    await source.render({ page: 0, rotation: 90 });
    await source.render({ page: 0, width: 300 });
    await source.render({ page: 0, region: { x: 0, y: 0, width: .5, height: .5 } });
    assert.equal(calls, 10);
});
