import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import vm from 'node:vm';
const {JSDOM} = createRequire(`${process.env.MODU_JSDOM_ROOT}/package.json`)('jsdom');
const source = await readFile(new URL('../assets/foliate-js/src/custom-highlight.js', import.meta.url), 'utf8');
const {matcherSource, collectHighlightGroups, highlightDeclarations, applyCustomHighlights, clearCustomHighlights} = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);

function match(data) {
  let result;
  const context = vm.createContext({self: {postMessage: value => {result = value}}, data});
  vm.runInContext(`${matcherSource}\nself.onmessage({data});`, context, {timeout: 100});
  return JSON.parse(JSON.stringify(result));
}
function fixture() {
  const dom = new JSDOM('<html><head></head><body><h1>“标题”</h1><p>他说：“你<strong>好</strong>。”</p><p hidden>“隐藏”</p><aside role="doc-footnote">“注释”</aside><p>“第二段”</p></body></html>', {pretendToBeVisual: true});
  dom.window.CSS = {highlights: new Map()};
  dom.window.Highlight = class extends Set {};
  return {dom, doc: dom.window.document};
}

test('collects across inline nodes but excludes hidden text/notes, with heading scope', () => {
  const {dom, doc} = fixture();
  const {groups} = collectHighlightGroups(doc);
  assert.deepEqual(groups.map(g => g.text), ['“标题”', '他说：“你好。”', '“第二段”']);
  const result = match({rules: [{pattern: '“[^”]+”', scope: 'body'}], groups});
  assert.deepEqual(result.matches, [[0,1,3,8], [0,2,0,5]]);
  const title = match({rules: [{pattern: '.+', scope: 'title'}], groups});
  assert.equal(title.matches.length, 1);
  assert.equal(title.matches[0][1], 0);
  dom.window.close();
});
test('invalid expressions are skipped; empty matches advance over astral unicode', () => {
  const result = match({rules: [{pattern: '['}, {pattern: '(?:)'}, {pattern: '你好'}], groups: [{text:'😀你好'}]});
  assert.deepEqual(result.errors, [0]);
  assert.deepEqual(result.matches, [[2,0,2,4]]);
});
test('matching and text collection enforce safe limits', () => {
  const result = match({rules:[{pattern: 'a'}], groups:[{text:'a'.repeat(3000)}]});
  assert.equal(result.matches.length, 2000);
  assert.equal(result.limited, true);
  const {dom, doc} = fixture();
  doc.body.textContent = 'a'.repeat(500001);
  const collected = collectHighlightGroups(doc);
  assert.equal(collected.groups[0].text.length, 500000);
  dom.window.close();
});
test('declarations cannot inject selectors or load images; unsupported properties dropped', () => {
  const {dom, doc} = fixture();
  const css = highlightDeclarations(doc, 'color:red;background-image:url(https://example.test/a);font-size:99px;text-decoration-style:wavy;');
  assert.match(css, /color:red/);
  assert.match(css, /text-decoration-style:wavy/);
  assert.doesNotMatch(css, /url|font-size|background-image/);
  assert.doesNotMatch(highlightDeclarations(doc,'color:var(--unsafe)'), /var/);
  dom.window.close();
});
test('applies ranges without changing text nodes, then clears only owned highlights', async () => {
  const {dom, doc} = fixture();
  const oldWorker = globalThis.Worker;
  const workers = [];
  globalThis.Worker = class {
    constructor() {workers.push(this)}
    postMessage(data) {queueMicrotask(() => this.onmessage({data:match(data)}))}
    terminate() {this.terminated = true}
  };
  try {
    const text = doc.body.innerHTML;
    const node = doc.querySelector('strong').firstChild;
    const cfiRange = doc.createRange(); cfiRange.selectNodeContents(node);
    doc.defaultView.CSS.highlights.set('search', 'keep');
    await applyCustomHighlights(doc, [{pattern:'“[^”]+”', scope:'body', css:'color:red'}]);
    const ranges = [...doc.defaultView.CSS.highlights.get('modu-custom-rule-0')];
    assert.equal(doc.defaultView.CSS.highlights.get('modu-custom-rule-0').priority, -100);
    assert.deepEqual(ranges.map(r=>r.toString()), ['“你好。”','“第二段”']);
    assert.equal(doc.body.innerHTML, text);
    assert.equal(doc.querySelector('strong').firstChild, node);
    assert.equal(cfiRange.toString(), '好');
    await applyCustomHighlights(doc, []);
    assert.equal(doc.defaultView.CSS.highlights.size, 1);
    assert.equal(doc.defaultView.CSS.highlights.get('search'), 'keep');
    assert.ok(workers.every(w=>w.terminated));
  } finally {globalThis.Worker = oldWorker; dom.window.close()}
});
test('slow matching is terminated, disabling cancels pending work, unsupported is reported', async () => {
  const {dom, doc} = fixture();
  const oldWorker = globalThis.Worker;
  let stopped = 0;
  globalThis.Worker = class {postMessage() {} terminate() {stopped++}};
  try {
    const statuses = [];
    await applyCustomHighlights(doc, [{pattern:'.+', css:'color:red'}], {timeout:5, onStatus:s=>statuses.push(s)});
    assert.deepEqual(statuses, ['timeout']);
    assert.ok(stopped > 0);
    const pending = applyCustomHighlights(doc, [{pattern:'.+'}], {onStatus:s=>statuses.push(s)});
    clearCustomHighlights(doc);
    await pending;
    assert.equal(doc.defaultView.CSS.highlights.size, 0);
    assert.deepEqual(statuses, ['timeout']);
    delete doc.defaultView.Highlight;
    await applyCustomHighlights(doc, [{pattern:'.+'}], {onStatus:s=>statuses.push(s)});
    assert.equal(statuses.at(-1), 'unsupported');
  } finally {globalThis.Worker = oldWorker; dom.window.close()}
});
