const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '../assets/foliate-js');
const acorn = require(require.resolve('acorn', {
  paths: [process.env.MODU_READER_NODE_MODULES || root],
}));
const bootstrap = fs.readFileSync(path.join(root, 'reader-bootstrap.js'), 'utf8');
const flush = () => new Promise(resolve => setImmediate(resolve));

function start(version, { apple = false, bridge = true, importing = true } = {}) {
  const scripts = [], notices = [], calls = [], logs = [];
  const listeners = new Map();
  const window = {
    location: { search: importing ? '?importing=true' : '' },
    addEventListener(name, fn) { listeners.set(name, fn); },
    removeEventListener(name) { listeners.delete(name); },
  };
  const attachBridge = () => {
    window.flutter_inappwebview = { callHandler: (...args) => calls.push(args) };
    listeners.get('flutterInAppWebViewPlatformReady')?.();
  };
  if (bridge) attachBridge();
  vm.runInNewContext(bootstrap, {
    window, navigator: { userAgent: apple ? 'iPhone AppleWebKit/605.1' : `Android Chrome/${version}.0`, platform: '' },
    console: { log: (...args) => logs.push(args), error() {} },
    document: {
      createElement: () => ({ style: {} }),
      head: { appendChild: script => scripts.push(script) },
      body: { appendChild: notice => notices.push(notice) },
    },
  });
  return { scripts, notices, calls, logs, listeners, attachBridge };
}

test('bootstrap itself parses as ES5 and logs the UA in one console argument', () => {
  acorn.parse(bootstrap, { ecmaVersion: 5 });
  assert.match(fs.readFileSync(path.join(root, 'index.html'), 'utf8'), /src="\.\/reader-bootstrap.js"/);
  assert.match(fs.readFileSync(path.resolve(root, '../../pubspec.yaml'), 'utf8'), /- assets\/foliate-js\/reader-bootstrap.js/);
  assert.deepEqual(start(70).logs, [['ModuUA Android Chrome/70.0']]);
});

test('unsupported WebView fails before loading modern syntax, including a late bridge', () => {
  const state = start(60, { bridge: false });
  assert.equal(state.scripts.length, 0);
  assert.equal(state.notices.length, 1);
  state.attachBridge();
  state.attachBridge();
  assert.equal(state.calls.length, 1);
  assert.equal(state.calls[0][0], 'onImportError');
  assert.equal(state.calls[0][1].name, 'UnsupportedWebView');
});

for (const [version, apple, modern] of [[70, false, false], [99, false, false], [100, false, true], [0, true, true]]) {
  test(`PDF loads before reader: Chrome ${version}, Apple ${apple}`, async () => {
    const state = start(version, { apple });
    assert.equal(state.scripts.length, 1);
    assert.equal(state.scripts[0].src, modern ? './src/vendor/pdfjs/pdf.js' : './dist/pdf-legacy.js');
    state.scripts[0].onload();
    await flush();
    assert.equal(state.scripts[1].src, modern ? './src/book.js' : './dist/bundle.js');
    assert.equal(state.scripts[1].type, modern ? 'module' : undefined);
    state.scripts[1].onload();
    await flush();
    assert.equal(state.calls.length, 0);
    assert.equal(state.listeners.has('error'), false);
  });
}

test('syntax and resource failures report once instead of waiting for metadata timeout', async () => {
  for (const resource of [false, true]) {
    const state = start(70);
    if (resource) state.scripts[0].onerror();
    else {
      state.listeners.get('error')();
      state.scripts[0].onload();
    }
    await flush();
    assert.equal(state.calls.length, 1);
    assert.equal(state.calls[0][0], 'onImportError');
    assert.equal(state.calls[0][1].name, 'ReaderScriptError');
    assert.equal(state.scripts.length, 1);
  }
  const reader = start(60, { importing: false });
  assert.equal(reader.calls[0][0], 'onReaderLoadError');
});

test('all shipped legacy scripts exclude modern syntax and unsupported replaceChildren calls', () => {
  for (const file of ['bundle.js', 'pdf-legacy.js', 'pdf-legacy.worker.js']) {
    const source = fs.readFileSync(path.join(root, 'dist', file), 'utf8');
    // BigInt literals are valid since Chromium 67, but were standardized in ES2020.
    const tree = acorn.parse(source, { ecmaVersion: 2020 });
    const visit = node => {
      if (node.type === 'MemberExpression') {
        const property = node.computed ? node.property.value : node.property.name;
        assert.notEqual(property, 'replaceChildren', `${file}: unsupported DOM method`);
      }
      assert.notEqual(node.type, 'ChainExpression', `${file}: optional chaining`);
      assert.ok(!(node.type === 'LogicalExpression' && node.operator === '??'), `${file}: nullish coalescing`);
      if (node.type === 'Literal' && typeof node.value === 'number') {
        assert.ok(!node.raw.includes('_'), `${file}: numeric separators`);
      }
      for (const child of Object.values(node)) {
        if (Array.isArray(child)) child.forEach(value => { if (value?.type) visit(value); });
        else if (child?.type) visit(child);
      }
    };
    visit(tree);
  }
});

test('legacy PDF main and worker parse a PDF without native globalThis', async () => {
  const context = vm.createContext({ console, URL, URLSearchParams, setTimeout, clearTimeout, TextDecoder, TextEncoder, ReadableStream });
  vm.runInContext('globalThis = undefined; self = this; window = this;', context);
  for (const [file, globalName, member] of [
    ['pdf-legacy.js', 'pdfjsLib', 'getDocument'],
    ['pdf-legacy.worker.js', 'pdfjsWorker', 'WorkerMessageHandler'],
  ]) {
    vm.runInContext(fs.readFileSync(path.join(root, 'dist', file), 'utf8'), context, { timeout: 10000 });
    assert.ok(context[globalName]?.[member], `${file} must expose ${globalName}.${member}`);
  }
  const content = 'BT /F1 12 Tf 10 50 Td (Legacy PDF smoke test) Tj ET';
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
  ];
  let pdf = '%PDF-1.4\n';
  const offsets = [0];
  objects.forEach((object, i) => { offsets.push(pdf.length); pdf += `${i + 1} 0 obj\n${object}\nendobj\n`; });
  const xref = pdf.length;
  pdf += `xref\n0 6\n0000000000 65535 f \n${offsets.slice(1).map(offset => `${String(offset).padStart(10, '0')} 00000 n \n`).join('')}trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`;
  context.pdfData = Array.from(Buffer.from(pdf));
  const result = await vm.runInContext(`(async function () {
    const task = pdfjsLib.getDocument({data: new Uint8Array(pdfData), disableFontFace: true, verbosity: 0});
    const pdf = await task.promise;
    try { return (await (await pdf.getPage(1)).getTextContent()).items.map(item => item.str).join(''); }
    finally { await task.destroy(); }
  })()`, context);
  assert.equal(result, 'Legacy PDF smoke test');
});
