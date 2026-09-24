import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
const { JSDOM } = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/vertical-column-rules.js', import.meta.url), 'utf8');
const { VerticalColumnRules } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

test('rules fill changing viewport height and retain glyph alignment during opening scale', () => {
  const dom = new JSDOM('<div id="layer"><iframe></iframe></div>');
  const { document } = dom.window;
  const renderer = document.createElement('div');
  renderer.vertical = true;
  renderer.setAttribute('vertical-column-rules', 'true');
  const layer = document.querySelector('#layer');
  const frame = document.querySelector('iframe');
  const doc = frame.contentDocument;
  doc.body.textContent = '正文';
  let height = 600;
  let scale = 0.8;
  const width = 200;
  const rect = () => ({ left: 20, top: 40, width: width * scale, height: height * scale });
  layer.getBoundingClientRect = rect;
  frame.getBoundingClientRect = rect;
  for (const node of [layer, frame]) {
    Object.defineProperty(node, 'clientWidth', { get: () => width });
    Object.defineProperty(node, 'clientHeight', { get: () => height });
  }
  doc.createRange = () => ({
    selectNodeContents() {},
    getClientRects: () => [
      { left: 10, right: 30, top: 10, bottom: 300, width: 20, height: 290 },
      { left: 50, right: 70, top: 10, bottom: 300, width: 20, height: 290 },
    ],
  });
  renderer.getContents = () => [{ doc }];
  const previous = globalThis.ResizeObserver;
  const previousMutation = globalThis.MutationObserver;
  globalThis.ResizeObserver = class { observe() {} disconnect() {} };
  globalThis.MutationObserver = class { observe() {} disconnect() {} };
  try {
    const rules = new VerticalColumnRules(renderer, layer, layer);
    rules.draw();
    const line = rules.svg.querySelector('line');
    assert.equal(line.getAttribute('y2'), '100%', 'line must not retain the initial pixel height');
    assert.equal(Number(line.getAttribute('x1')), 40, 'screen scale must not shift the rule from the glyph gap');
    height = 800;
    scale = 1;
    // No relocate/font-size event is required for the existing SVG line to
    // follow its container height after first-open layout settles.
    assert.equal(line.getAttribute('y2'), '100%');
    rules.draw();
    assert.equal(Number(rules.svg.querySelector('line').getAttribute('x1')), 40);
    renderer.vertical = false;
    rules.draw();
    assert.equal(rules.svg.children.length, 0);
    rules.destroy();
  } finally {
    globalThis.ResizeObserver = previous;
    globalThis.MutationObserver = previousMutation;
    dom.window.close();
  }
});
