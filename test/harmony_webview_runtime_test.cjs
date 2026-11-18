// Executes patched native method bodies after TypeScript erasure. This verifies
// policy/control flow, not ArkTS SDK typing or real-device ArkWeb behavior.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {stripTypeScriptTypes} = require('node:module');
const sources = JSON.parse(fs.readFileSync(0, 'utf8'));
const prefix = 'flutter_inappwebview_ohos/ohos/src/main/ets/components/plugin/';
const viewSource = sources[prefix + 'webview/in_app_webview/InAppWebView.ets'];
const contentSource = sources[prefix + 'types/UserContentController.ets'];
const bridgeSource = sources[prefix + 'webview/JavaScriptBridgeInterface.ets'];
const channelSource = sources[prefix + 'webview/WebViewChannelDelegate.ets'];

function method(source, name) {
  const pattern = new RegExp('^  (?:(?:public|private|protected|async) )*' + name + '\\(', 'm');
  const start = source.search(pattern);
  assert.notEqual(start, -1, name);
  const end = source.indexOf('\n  }', start);
  assert.notEqual(end, -1, name + ' end');
  return source.slice(start, end + 4);
}
function harness(source, names, globals = {}) {
  const code = stripTypeScriptTypes('class Harness {\n' + names.map(n => method(source, n)).join('\n') + '\n}',
    {mode: 'transform'});
  return new (vm.runInNewContext(code + '\nHarness', globals))();
}
for (const [name, source] of Object.entries(sources)) {
  if (name.endsWith('.ets')) stripTypeScriptTypes(source, {mode: 'transform'});
}

// A native method request really happens; failures are not converted to success.
let focuses = 0;
const view = harness(viewSource, ['requestFocus', 'isJavaScriptBridgeEnabled']);
view.requireController = () => ({requestFocus: () => { focuses++; }});
assert.equal(view.requestFocus(), true);
assert.equal(focuses, 1);
view.requireController = () => ({requestFocus: () => {throw Error('detached');}});
assert.throws(() => view.requestFocus(), /detached/);

// A forged saved proxy reference must not reach any callback when disabled.
const bridge = harness(bridgeSource, ['_callHandler', '_hideContextMenu'], {
  OnJsBeforeUnloadJS: {HANDLER_NAME: 'beforeUnload'},
  OnZoomScaleChangedJS: {HANDLER_NAME: 'zoom'},
  InnerCallJsHandlerCallback: class {},
});
let dispatched = 0;
bridge.inAppWebView = new Proxy({isJavaScriptBridgeEnabled: () => false}, {
  get(target, key) {
    if (key in target) return target[key];
    throw Error('disabled bridge accessed native state: ' + String(key));
  },
});
for (const name of ['reader', '__onPopupWindowClose', '__windowOpenAboutBlank',
  'onPrintRequest', 'callAsyncJavaScript', 'evaluateJavaScriptWithContentWorld',
  'onWebMessageListenerPostMessageReceived', 'beforeUnload', 'zoom']) {
  bridge._callHandler(name, '123', 'not even valid JSON');
}
bridge._hideContextMenu();
bridge.inAppWebView = {
  isJavaScriptBridgeEnabled: () => true,
  channelDelegate: {onCallJsHandler: () => {dispatched++;}},
};
bridge._callHandler('reader', '1', '[]');
assert.equal(dispatched, 1, 'enabled local reader must keep its bridge');

// Script scheduling is independent of bridge scripts. Execute the retained
// page script in a browser-shaped VM and observe the zoom style mutation.
const PAGE = {equals: other => other === PAGE};
const zoom = 'document.documentElement.style.zoom = "125%";';
const content = harness(contentSource, [
  'addPluginScript', 'generatePluginScriptsCodeAt', 'generateContentWorldsCreatorCode',
  'generateCodeForDocumentStart', 'generateWrappedCodeForDocumentEnd',
  'generateUserOnlyScriptsCodeAt', 'wrapSourceCodeInContentWorld',
  'generateCodeForScriptEvaluation',
], {ContentWorld: {PAGE}, UserScriptInjectionTime: {AT_DOCUMENT_START: 0, AT_DOCUMENT_END: 1}});
content.inAppWebView = {isJavaScriptBridgeEnabled: () => false};
content.getUserOnlyScriptsAt = () => [{getSource: () => zoom, getContentWorld: () => PAGE}];
assert.equal(content.addPluginScript(null), false);
assert.equal(content.generatePluginScriptsCodeAt(0), '');
assert.equal(content.generateContentWorldsCreatorCode(), '');
for (const code of [content.generateCodeForDocumentStart(),
  content.generateWrappedCodeForDocumentEnd(), content.generateCodeForScriptEvaluation(zoom, null)]) {
  assert.ok(!code.includes('flutter_inappwebview'));
  const document = {documentElement: {style: {}}};
  vm.runInNewContext(code, {document});
  assert.equal(document.documentElement.style.zoom, '125%');
}
assert.throws(() => content.wrapSourceCodeInContentWorld({equals: () => false}, zoom), /require/);

// Run the ACTUAL method-channel switch for focus, policy changes, denied APIs,
// and evaluateJavascript; don't merely search for security-related strings.
const methodNames = [...channelSource.matchAll(/WebViewChannelDelegateMethods\.(\w+)/g)].map(m => m[1]);
const methods = Object.fromEntries(methodNames.map(n => [n, n]));
const channel = harness(channelSource, ['onMethodCall'], {
  WebViewChannelDelegateMethods: methods,
  ContentWorld: {fromMap: m => m == null ? null : {name: m.get('name')}},
  InAppBrowserSession: class {},
  InAppWebViewSettings: class { parse(value) { this.values = value; } },
  Log: {e() {}}, LOG_TAG: 'test',
});
async function call(name, argumentsMap = {}) {
  const response = {};
  await channel.onMethodCall({method: name, argument: key => argumentsMap[key]}, {
    success: value => {response.value = value;},
    error: (code, message) => {response.error = code; response.message = message;},
    notImplemented: () => {response.error = 'notImplemented';},
  });
  return response;
}
(async () => {
  // Exercise native Map serialization and the actual pinned page wrapper.
  const wrapperSource = sources[prefix + 'plugin_scripts_js/PluginScriptsUtil.ets'];
  const fields = wrapperSource.slice(
    wrapperSource.indexOf('  public static VAR_PLACEHOLDER_VALUE'),
    wrapperSource.indexOf('  public static EVALUATE_JAVASCRIPT_WITH_CONTENT_WORLD_WRAPPER_JS_SOURCE'));
  const scripts = vm.runInNewContext(stripTypeScriptTypes(
    'class PluginScriptsUtil {\n' + fields + '\n}\nPluginScriptsUtil', {mode: 'transform'}),
    {JavaScriptBridgeJS: {JAVASCRIPT_BRIDGE_NAME: 'flutter_inappwebview'}});
  let nextUuid = 0;
  const asyncView = harness(viewSource, ['stringifyJavaScriptArgument', 'callAsyncJavaScript'], {
    Map, Object, PluginScriptsUtil: scripts,
    util: {generateRandomUUID: () => String(++nextUuid)},
    Log: {e() {}}, TAG: 'test',
  });
  asyncView.callAsyncJavaScriptCallbacks = new Map();
  asyncView.waitControllerAttached = () => Promise.resolve();
  asyncView.requireUserContentController = () => ({generateCodeForScriptEvaluation: code => code});
  async function invokePage(body, args, pageFunctions) {
    return await new Promise(resolve => {
      const window = {...pageFunctions, flutter_inappwebview: {
        callHandler(name, response) {
          assert.equal(name, 'callAsyncJavaScript');
          const callback = asyncView.callAsyncJavaScriptCallbacks.get(response.resultUuid);
          assert.ok(callback);
          callback.onReceiveValue(JSON.stringify(response));
          asyncView.callAsyncJavaScriptCallbacks.delete(response.resultUuid);
        },
      }};
      asyncView.requireController = () => ({
        runJavaScriptExt(code) {
          vm.runInNewContext(code, {window});
          return Promise.resolve('null');
        },
      });
      asyncView.callAsyncJavaScript(body, args, null, {
        onReceiveValue: value => resolve(JSON.parse(value)),
      });
    });
  }
  const crop = new Map([['x', .1], ['y', .2], ['width', .6], ['height', .7]]);
  const label = '中 文 " \\ $& $\' $` 😀';
  const markers = [null, false, 0, '', undefined, new Map([['label', label]])];
  const request = new Map([['page', 3], ['width', 960], ['crop', crop], ['markers', markers],
    ['wrapped', {nested: new Map([['enabled', true]]), omit: undefined}],
    ['__proto__', new Map([['polluted', 'kept as data']])]]);
  const expected = {page: 3, width: 960, crop: {x: .1, y: .2, width: .6, height: .7},
    markers: [null, false, 0, '', null, {label}], wrapped: {nested: {enabled: true}},
    ['__proto__']: {polluted: 'kept as data'}};
  for (const name of ['renderPdfRegion', 'extractDocumentText']) {
    const result = await invokePage(`return await window.${name}(request);`,
      new Map([['request', request]]), {[name]: value => value});
    assert.equal(result.error, null);
    assert.deepEqual(result.value, expected);
    assert.equal(Object.hasOwn(result.value, '__proto__'), true);
    assert.equal(Object.getPrototypeOf(result.value), Object.prototype);
  }
  const layout = new Map([['columns', 2], ['margins', new Map([['top', .05]])]]);
  const readingView = new Map([['zoom', 1.5], ['rotation', 0], ['display', new Map([['hideWatermarks', true]])]]);
  const applied = await invokePage('return window.setPdfReadingLayout(config, enabled, view);',
    new Map([['config', layout], ['enabled', false], ['view', readingView]]),
    {setPdfReadingLayout: (config, enabled, view) => ({config, enabled, view})});
  assert.deepEqual(applied.value, {config: {columns: 2, margins: {top: .05}}, enabled: false,
    view: {zoom: 1.5, rotation: 0, display: {hideWatermarks: true}}});
  const reflow = await invokePage('return window.getDocumentReflowInfo(page, config, enabled, imageEpub, hideWatermarks);',
    new Map([['page', null], ['config', layout], ['enabled', true], ['imageEpub', false], ['hideWatermarks', true]]),
    {getDocumentReflowInfo: (page, config, enabled, imageEpub, hideWatermarks) => ({page, config, enabled, imageEpub, hideWatermarks})});
  assert.deepEqual(reflow.value, {page: null, config: {columns: 2, margins: {top: .05}},
    enabled: true, imageEpub: false, hideWatermarks: true});
  assert.equal(request.get('crop'), crop, 'transport must not mutate native arguments');
  assert.equal(asyncView.callAsyncJavaScriptCallbacks.size, 0);
  assert.equal({}.polluted, undefined);

  const clientSource = sources[prefix + 'webview/in_app_webview/InAppWebViewClient.ets'];
  let requestOptions;
  let destroyed = 0;
  const client = harness(clientSource, ['runRemoteHttpFallback'], {
    http: { HttpDataType: { ARRAY_BUFFER: 'buffer' }, createHttp: () => ({
      request: async (url, options) => {
        requestOptions = options;
        if ((options.maxLimit ?? 5 * 1024 * 1024) < 16662365) throw Error('response too large');
        return { responseCode: 200, result: new ArrayBuffer(16662365) };
      },
      destroy: () => { destroyed++; },
    }) },
    RequestBodyReader: { needsRequestBody: () => false },
    Log: { e() {}, w() {}, d() {} }, TAG: 'test',
  });
  client.isLoopbackHost = url => new URL(url).hostname === '127.0.0.1';
  for (const [url, success] of [['http://127.0.0.1:32869/book/test.epub', true],
    ['https://example.test/book.epub', false]]) {
    const outcome = await new Promise(resolve => client.runRemoteHttpFallback({
      getUrl: () => url, getHeaders: () => new Map(), getMethod: () => 'GET',
    }, undefined, response => resolve(response.result.byteLength), () => resolve(false)));
    assert.equal(outcome, success ? 16662365 : false);
    assert.equal(requestOptions.maxLimit, success ? 100 * 1024 * 1024 : undefined);
  }
  assert.equal(destroyed, 2);

  // Execute the real loopback fallback; query parameters must reach ArkWeb's
  // document URL, not merely its history URL. Other fallback policies stay put.
  let loaded;
  const local = harness(viewSource, ['loadPrivateHttpUrl'], {
    http: {
      RequestMethod: {GET: 'GET', POST: 'POST', HEAD: 'HEAD', PUT: 'PUT'},
      HttpDataType: {STRING: 'STRING'},
      createHttp: () => ({
        request: async () => ({responseCode: 200, result: '<html></html>', header: {}}),
        destroy() {},
      }),
    },
    InAppWebView: {httpResultToString: value => value},
    Log: {e: message => {throw Error(message);}, w() {}}, TAG: 'test',
  });
  local.getUrl = () => 'http://127.0.0.1/previous';
  local.isLoopbackHttpUrl = url => new URL(url).hostname === '127.0.0.1';
  local.buildLoopbackBaseUrl = url => new URL('.', url).href;
  local.loadDataWithBaseURL = async (...args) => {loaded = args;};
  local.waitForClientCertPageReadyThenDispatchLoadStop = () => {};
  const bookUrl = 'http://127.0.0.1:35035/foliate-js/index.html?importing=true&url=%22book%2Ftoken.epub%22&style=%7B%22fontSize%22%3A20%7D';
  await local.loadPrivateHttpUrl(bookUrl, 'GET', null, null);
  assert.equal(loaded[0], bookUrl);
  assert.equal(loaded[4], bookUrl);
  assert.equal(new URL(loaded[0]).searchParams.get('importing'), 'true');
  assert.equal(new URL(loaded[0]).searchParams.get('url'), '"book/token.epub"');
  assert.deepEqual(JSON.parse(new URL(loaded[0]).searchParams.get('style')), {fontSize: 20});
  assert.equal(new URL('dist/bundle.js', loaded[0]).pathname, '/foliate-js/dist/bundle.js');
  for (const [url, method] of [[bookUrl, 'POST'], [bookUrl, 'HEAD'],
    ['http://192.168.1.2/page?query=keep', 'GET']]) {
    await local.loadPrivateHttpUrl(url, method, null, null);
    assert.equal(loaded[0], new URL('.', url).href);
    assert.equal(loaded[4], url);
  }

  const document = {documentElement: {style: {}}};
  let updates = 0;
  channel.webView = {
    isJavaScriptBridgeEnabled: () => false,
    requestFocus: () => {focuses++; return true;},
    getInAppBrowserDelegate: () => null,
    setSettings: () => {updates++;},
    evaluateJavascript: (source, world, callback) => {
      vm.runInNewContext(source, {document});
      callback.onReceiveValue('true');
    },
  };
  assert.equal((await call('requestFocus')).value, true);
  channel.webView.requestFocus = () => {throw Error('native failure');};
  assert.equal((await call('requestFocus')).error, 'requestFocusError');
  for (const name of ['callAsyncJavaScript', 'createWebMessageChannel', 'addWebMessageListener']) {
    assert.equal((await call(name)).error, 'javaScriptBridgeDisabled');
  }
  assert.equal((await call('setSettings', {settings: new Map([['javaScriptBridgeEnabled', true]])})).error,
    'bridgePolicyImmutable');
  // Type assertions must not coerce values, change null handling, or bypass the
  // immutable policy gate. Settings contain mixed native codec value types.
  for (const value of [undefined, null, false]) {
    const settings = new Map([['javaScriptEnabled', true], ['minimumFontSize', 12]]);
    if (value !== undefined) settings.set('javaScriptBridgeEnabled', value);
    assert.equal((await call('setSettings', {settings})).value, true);
  }
  assert.equal(updates, 3);
  for (const value of [true, 'false', 0]) {
    assert.equal((await call('setSettings', {
      settings: new Map([['javaScriptBridgeEnabled', value]]),
    })).error, 'bridgePolicyImmutable');
  }
  assert.equal(updates, 3, 'rejected changes must not reach native setSettings');
  channel.webView.isJavaScriptBridgeEnabled = () => true;
  assert.equal((await call('setSettings', {
    settings: new Map([['javaScriptBridgeEnabled', false]]),
  })).error, 'bridgePolicyImmutable');
  assert.equal((await call('setSettings', {
    settings: new Map([['javaScriptBridgeEnabled', true]]),
  })).value, true);
  channel.webView.isJavaScriptBridgeEnabled = () => false;
  const response = await call('evaluateJavascript', {source: zoom, contentWorld: null});
  assert.equal(response.error, undefined);
  assert.equal(document.documentElement.style.zoom, '125%');
  assert.equal((await call('evaluateJavascript', {
    source: zoom, contentWorld: new Map([['name', 'page']]),
  })).error, undefined);
  assert.equal((await call('evaluateJavascript', {
    source: zoom, contentWorld: new Map([['name', 'defaultClient']]),
  })).error, 'javaScriptBridgeDisabled');
  assert.equal((await call('evaluateJavascript', {
    source: zoom, contentWorld: new Map(),
  })).error, 'javaScriptBridgeDisabled');
  console.log('Native control-flow and page zoom checks passed');
})().catch(error => {console.error(error); process.exitCode = 1;});
