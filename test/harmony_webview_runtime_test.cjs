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
  const document = {documentElement: {style: {}}};
  channel.webView = {
    isJavaScriptBridgeEnabled: () => false,
    requestFocus: () => {focuses++; return true;},
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
  const response = await call('evaluateJavascript', {source: zoom, contentWorld: null});
  assert.equal(response.error, undefined);
  assert.equal(document.documentElement.style.zoom, '125%');
  assert.equal((await call('evaluateJavascript', {
    source: zoom, contentWorld: new Map([['name', 'defaultClient']]),
  })).error, 'javaScriptBridgeDisabled');
  console.log('Native control-flow and page zoom checks passed');
})().catch(error => {console.error(error); process.exitCode = 1;});
