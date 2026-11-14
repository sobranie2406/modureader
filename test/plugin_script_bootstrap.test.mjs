import assert from 'node:assert/strict';
import {getEventListeners} from 'node:events';
import {readFile} from 'node:fs/promises';
import {test} from 'node:test';
import vm from 'node:vm';
import {Worker as Thread} from 'node:worker_threads';

const bootstrap = await readFile(new URL('../assets/plugin-runtime/runtime.js', import.meta.url), 'utf8');

// Use real, separately scheduled workers so termination tests cannot hang the
// test runner. This browser-shaped adapter does not emulate or verify CSP.
const workerHost = `
  const {parentPort, workerData} = require('node:worker_threads');
  const vm = require('node:vm');
  const scope = {postMessage: value => parentPort.postMessage(value), setTimeout, clearTimeout};
  scope.self = scope;
  for (const name of ['fetch','XMLHttpRequest','WebSocket','EventSource','importScripts','Worker','SharedWorker','indexedDB','caches'])
    scope[name] = () => { throw new Error('Unmediated API reached'); };
  vm.createContext(scope);
  new vm.Script(workerData).runInContext(scope);
  parentPort.on('message', data => {
    Promise.resolve(scope.onmessage?.({data})).catch(() => parentPort.postMessage({kind:'error'}));
  });
  parentPort.postMessage({runtimeReady:true});
`;

function fixture({workerAvailable = true, bridgeReady = true, onCall = async () => ({value: null})} = {}) {
  const blobs = new Map(), workers = [], messages = [];
  const events = new EventTarget(), readyEvent = 'flutterInAppWebViewPlatformReady';
  let next = 0, complete;
  const result = new Promise(resolve => { complete = resolve; });
  class BrowserBlob {
    constructor(parts) { this.source = parts.join(''); }
  }
  class BrowserWorker {
    constructor(url) {
      assert.ok(blobs.has(url), 'the worker Blob must exist when construction starts');
      this.thread = new Thread(workerHost, {eval: true, workerData: blobs.get(url).source});
      this.sent = [];
      this.finished = new Promise(resolve => this.thread.once('exit', resolve));
      this.ready = new Promise(resolve => {
        this.thread.on('message', value => {
          if (value.runtimeReady) resolve();
          else this.onmessage?.({data: value});
        });
      });
      this.thread.on('error', error => this.onerror?.(error));
      workers.push(this);
    }
    postMessage(value) { this.sent.push(value); this.thread.postMessage(value); }
    terminate() { this.terminated = true; void this.thread.terminate(); }
  }
  const host = {
    addEventListener: events.addEventListener.bind(events),
    removeEventListener: events.removeEventListener.bind(events),
    Blob: BrowserBlob,
    Worker: workerAvailable ? BrowserWorker : undefined,
    URL: {
      createObjectURL(blob) {
        const url = `blob:plugin-test/${++next}`;
        blobs.set(url, blob);
        return url;
      },
      revokeObjectURL: url => blobs.delete(url),
    },
    flutter_inappwebview: {
      async callHandler(handler, text) {
        assert.equal(handler, 'host-only-handler');
        const value = JSON.parse(text);
        messages.push(value);
        if (value.kind === 'call') return onCall(value);
        complete(value);
        return null;
      },
    },
  };
  const nativeBridge = host.flutter_inappwebview;
  if (!bridgeReady) host.flutter_inappwebview = undefined;
  host.window = host;
  vm.createContext(host);
  new vm.Script(bootstrap).runInContext(host);
  return {
    host, messages, workers, blobs, result,
    start(source, input = {}) {
      host.moduPluginStart({source, input, handler: 'host-only-handler'});
    },
    readyBridge() {
      host.flutter_inappwebview = nativeBridge;
      events.dispatchEvent(new Event(readyEvent));
    },
    get readyListeners() { return getEventListeners(events, readyEvent).length; },
    async dispose() {
      host.moduPluginStop();
      await Promise.all(workers.map(worker => worker.finished));
    },
  };
}

async function within(promise, milliseconds = 3000) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('Worker did not finish')), milliseconds);
    })]);
  } finally { clearTimeout(timer); }
}

test('text and HTML-looking plugin source remain in the worker, without DOM or native bridge', async t => {
  const f = fixture(); t.after(() => f.dispose());
  f.start(`
    const text = '</script><script>window.escaped=true</script>';
    return {title: input.selection, text, isolated:
      typeof window === 'undefined' && typeof document === 'undefined' &&
      typeof flutter_inappwebview === 'undefined'};
  `, {selection: '例句'});
  const message = await within(f.result);
  assert.equal(message.kind, 'result');
  assert.equal(message.value.title, '例句');
  assert.equal(message.value.text, '</script><script>window.escaped=true</script>');
  assert.equal(message.value.isolated, true);
  assert.equal(f.host.escaped, undefined);
  assert.equal(f.workers.length, 1);
  assert.equal(f.workers[0].terminated, true);
  assert.equal(f.blobs.size, 0);
});

test('only frozen, named host API methods are exposed and direct network/storage constructors reject', async t => {
  const f = fixture({onCall: async message => ({value: message.method})});
  t.after(() => f.dispose());
  f.start(`
    const blocked = [];
    for (const name of ['fetch','XMLHttpRequest','WebSocket','EventSource','importScripts','Worker','SharedWorker','indexedDB','caches']) {
      try { self[name](); } catch (_) { blocked.push(name); }
      if (Object.getOwnPropertyDescriptor(self,name).writable) throw new Error('Mutable API');
    }
    const methods = [await modu.http.get({url:'https://example.com'}),
      await modu.library.list({limit:1}), await modu.notes.save({text:'note'}),
      await modu.articles.capture(),
      await modu.privateLibrary.open(), await modu.privateLibrary.lock()];
    return {blocked, methods, keys:Object.keys(modu), frozen:Object.isFrozen(modu)};
  `);
  const message = await within(f.result);
  assert.equal(message.kind, 'result');
  assert.equal(message.value.blocked.length, 9);
  assert.deepEqual(message.value.methods,
    ['http.get','library.list','notes.save','articles.capture','privateLibrary.open','privateLibrary.lock']);
  assert.deepEqual(message.value.keys, ['http','library','notes','articles','privateLibrary']);
  assert.equal(message.value.frozen, true);
  assert.deepEqual(f.messages.filter(message => message.kind === 'call').map(message => message.id), [1,2,3,4,5,6]);
});

for (const kind of ['result', 'request']) test(`oversized ${kind} is stopped before reaching the native bridge`, async t => {
  const f = fixture(); t.after(() => f.dispose());
  f.start(kind === 'result'
    ? `return {text:'x'.repeat(65537)};`
    : `return await modu.http.get({url:'x'.repeat(65537)});`);
  assert.deepEqual(await within(f.result), {kind:'error'});
  assert.equal(f.messages.length, 1);
  assert.equal(f.workers[0].terminated, true);
});

test('a forged worker message flood is bounded even when package code bypasses its API', async t => {
  const f = fixture(); t.after(() => f.dispose());
  f.start(`
    for(let i=0;i<100;i++) self.postMessage({kind:'call',id:i,method:'unknown',arguments:{}});
    await new Promise(() => {});
  `);
  assert.deepEqual(await within(f.result), {kind:'error'});
  assert.equal(f.messages.filter(message => message.kind === 'call').length, 40);
  assert.equal(f.workers[0].terminated, true);
});

test('an infinite loop is terminated without blocking the host or leaving a worker alive', async t => {
  const f = fixture(); t.after(() => f.dispose());
  f.start('while(true) {}');
  await within(f.workers[0].ready);
  assert.equal(f.blobs.size, 1, 'retain the Blob URL until the worker stops');
  f.host.moduPluginStop();
  await within(f.workers[0].finished);
  assert.equal(f.workers[0].terminated, true);
  assert.equal(f.blobs.size, 0);
  assert.deepEqual(f.messages, []);
});

test('a host response arriving after cancellation cannot revive or message the stopped worker', async t => {
  let release, called;
  const waiting = new Promise(resolve => { release = resolve; });
  const entered = new Promise(resolve => { called = resolve; });
  const f = fixture({onCall: async () => { called(); return waiting; }});
  t.after(() => f.dispose());
  f.start(`const value = await modu.library.list({}); return {text:String(value)};`);
  await within(entered);
  f.host.moduPluginStop();
  release({value:'late response'});
  await within(f.workers[0].finished);
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(f.workers[0].sent.length, 1, 'only the initial input reached the worker');
  assert.equal(f.messages.length, 1);
  assert.equal(f.messages[0].kind, 'call');
});

test('host failures expose a fixed error rather than native exception details', async t => {
  const f = fixture({onCall: async () => { throw new Error('secret-native-error'); }});
  t.after(() => f.dispose());
  f.start(`
    try { await modu.library.list({}); }
    catch(error) { return {text:error.message}; }
  `);
  const message = await within(f.result);
  assert.equal(message.kind, 'result');
  assert.equal(message.value.text, 'Plugin request failed');
  assert.equal(JSON.stringify(f.messages).includes('secret-native-error'), false);
});

test('invalid plugin source reports failure and releases its worker', async t => {
  const f = fixture(); t.after(() => f.dispose());
  f.start('return {');
  assert.deepEqual(await within(f.result), {kind:'error'});
  assert.equal(f.workers[0].terminated, true);
});

test('missing Worker fails closed without evaluating package code in the host', async t => {
  const f = fixture({workerAvailable:false}); t.after(() => f.dispose());
  f.start('window.escaped = true;');
  assert.deepEqual(await within(f.result), {kind:'error'});
  assert.equal(f.host.escaped, undefined);
  assert.equal(f.workers.length, 0);
});

test('an older WebView can deliver its native bridge after startup without losing or repeating input', async t => {
  const f = fixture({bridgeReady:false}); t.after(() => f.dispose());
  f.start('return {text:input.selection};', {selection:'delayed bridge'});
  assert.equal(f.workers.length, 0);
  assert.equal(f.readyListeners, 1);
  f.readyBridge();
  const message = await within(f.result);
  assert.deepEqual(message, {kind:'result',value:{text:'delayed bridge'}});
  assert.equal(f.readyListeners, 0);
  f.readyBridge();
  assert.equal(f.workers.length, 1);
  assert.equal(f.messages.length, 1);
});

test('stopping while the native bridge is pending removes its listener and ignores late readiness', async t => {
  const f = fixture({bridgeReady:false}); t.after(() => f.dispose());
  f.start('return {text:"must not run"};');
  assert.equal(f.readyListeners, 1);
  f.host.moduPluginStop();
  assert.equal(f.readyListeners, 0);
  f.readyBridge();
  f.start('return {text:"must not restart"};');
  assert.equal(f.workers.length, 0);
  assert.equal(f.blobs.size, 0);
  assert.deepEqual(f.messages, []);
});
