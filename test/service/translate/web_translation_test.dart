import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/service/translate/web_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('web engines are offered for selection, not automatic full text', () {
    expect(TranslateService.selectionValues,
        containsAll(TranslateService.webValues));
    expect(TranslateService.readAnyValues.any((engine) => engine.isWebView),
        isFalse);
    // Keep old enum indexes for stored legacy configurations.
    expect(TranslateService.ai.index, 6);
    expect(TranslateService.googleWeb.index, 2);
  });

  for (final engine in [
    TranslateService.baiduWeb,
    TranslateService.youdaoWeb
  ]) {
    test('${engine.name} uses its official HTTPS site without API credentials',
        () {
      final provider = engine.provider as WebViewTranslateProvider;
      final url = Uri.parse(provider.getUrl(
          'PRIVATE_SELECTION', LangListEnum.auto, LangListEnum.english));
      expect(url.scheme, 'https');
      expect(
          url.host,
          engine == TranslateService.baiduWeb
              ? 'fanyi.baidu.com'
              : 'fanyi.youdao.com');
      expect(url.toString(), isNot(contains('PRIVATE_SELECTION')));
      expect(provider.getConfig(), isEmpty);
      expect(getTranslateService(engine.name), engine);
      expect(provider.prefillScript('text'), isNotNull);
    });

    test('${engine.name} opens the mobile editor directly on Android and iOS',
        () {
      final provider = engine.provider as WebViewTranslateProvider;
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        final url = Uri.parse(provider.getUrl('PRIVATE_SELECTION',
            LangListEnum.auto, LangListEnum.simplifiedChinese));
        expect(url.scheme, 'https');
        expect(
            url.host,
            engine == TranslateService.baiduWeb
                ? 'fanyi.baidu.com'
                : 'm.youdao.com');
        expect(url.path,
            engine == TranslateService.baiduWeb ? '/m/trans' : '/translate');
        expect(url.toString(), isNot(contains('PRIVATE_SELECTION')));
      }
    });

    test('${engine.name} selection and full-text preferences stay independent',
        () async {
      Prefs().fullTextTranslateService = TranslateService.deepl;
      Prefs().translateService = engine;
      expect(Prefs().fullTextTranslateService, TranslateService.deepl);
      expect(
          () => Prefs().fullTextTranslateService = engine, throwsArgumentError);
      expect(Prefs().fullTextTranslateService, TranslateService.deepl);
      await Prefs().prefs.setString('fullTextTranslateService', engine.name);
      expect(Prefs().fullTextTranslateService, TranslateService.microsoftFree);
    });

    test('${engine.name} is retained in global settings export', () async {
      Prefs().translateService = engine;
      Prefs().fullTextTranslateService = TranslateService.ai;
      final data = jsonDecode(await GlobalSettingsTransfer.export(Prefs()));
      expect(data['preferences']['translateService']['value'], engine.name);
      expect(data['preferences']['fullTextTranslateService']['value'], 'ai');
      final restored = GlobalSettingsTransfer.forImport(
          Map<String, dynamic>.from(data['preferences']));
      expect(restored['translateService']['value'], engine.name);
      Prefs().translateService = TranslateService.microsoftFree;
      Prefs().fullTextTranslateService = TranslateService.deepl;
      await GlobalSettingsTransfer.apply(Prefs(), restored);
      expect(Prefs().translateService, engine);
      expect(Prefs().fullTextTranslateService, TranslateService.ai);
    });

    test('${engine.name} prefill is escaped, host-bound and preserves drafts',
        () {
      final provider = engine.provider as WebViewTranslateProvider;
      const source = 'hello "世界"\n\'; globalThis.secretLeaked = true; //';
      final script = provider.prefillScript(source)!;
      final result = Process.runSync('node', [
        '-e',
        '''
const vm = require('node:vm');
const assert = require('node:assert/strict');
const script = ${jsonEncode(script)};
const host = ${jsonEncode(engine == TranslateService.baiduWeb ? 'fanyi.baidu.com' : 'fanyi.youdao.com')};
const source = ${jsonEncode(source)};
function run({hostname = host, protocol = 'https:', draft = '', delayed = false, native = false, placeholder = false, handledBeforeInput = false} = {}) {
  let ready = !delayed;
  let callback, timer, disconnected = false, inserted = [], events = [], queries = 0;
  const editor = {isConnected: true, textContent: native ? '' : draft, value: draft,
    tagName: native ? 'TEXTAREA' : 'DIV',
    cloneNode() {
      const clone = {textContent: placeholder ? '请输入文本' : draft};
      clone.querySelectorAll = () => placeholder ? [{remove() {clone.textContent = '';}}] : [];
      return clone;
    },
    getBoundingClientRect: () => ({width: 100}), focus() {},
    dispatchEvent(e) {
      events.push(e);
      if (handledBeforeInput && e.type === 'beforeinput') {
        inserted.push(e.data); this.textContent = e.data; return false;
      }
      return true;
    }};
  const window = {getSelection: () => ({removeAllRanges() {}, addRange() {}})};
  window.HTMLTextAreaElement = class {};
  Object.defineProperty(window.HTMLTextAreaElement.prototype, 'value', {
    set(text) {inserted.push(text); this.value = text;}
  });
  const context = {location: {protocol, hostname}, window,
    document: {documentElement: {}, querySelector() {queries++; return ready ? editor : null;},
      createRange: () => ({selectNodeContents() {}}),
      execCommand(command, showUI, text) {
        assert.equal(command, 'insertText'); inserted.push(text); editor.textContent = text;
      }},
    MutationObserver: class {constructor(cb) {callback = cb;} observe() {} disconnect() {disconnected = true;}},
    InputEvent: class {constructor(type, data) {Object.assign(this, {type}, data);}},
    setTimeout(cb) {timer = cb; return 1;}, clearTimeout() {timer = undefined;}};
  vm.runInNewContext(script, context);
  return {context, inserted, events, get queries() {return queries;},
    makeReady() {ready = true; callback();}, expire() {timer();},
    get disconnected() {return disconnected;}};
}
const normal = run();
assert.deepEqual(normal.inserted, [source]);
assert.equal(normal.events[0].data, source);
assert.equal(normal.context.secretLeaked, undefined);
vm.runInNewContext(script, normal.context);
assert.equal(normal.inserted.length, 1);
assert.equal(run({hostname: 'example.test'}).queries, 0);
assert.equal(run({protocol: 'http:'}).queries, 0);
assert.equal(run({draft: 'user text'}).inserted.length, 0);
assert.deepEqual(run({placeholder: true}).inserted, [source]);
assert.deepEqual(run({handledBeforeInput: true}).inserted, [source]);
const delayed = run({delayed: true});
assert.equal(delayed.inserted.length, 0);
delayed.makeReady();
assert.deepEqual(delayed.inserted, [source]);
assert.equal(delayed.disconnected, true);
const timeout = run({delayed: true}); timeout.expire();
assert.equal(timeout.disconnected, true);
const mobileHost = host === 'fanyi.youdao.com' ? 'm.youdao.com' : host;
const mobile = run({hostname: mobileHost, native: true});
assert.deepEqual(mobile.inserted, [source]);
assert.equal(mobile.events[0].data, source);
assert.equal(run({hostname: mobileHost, native: true, draft: 'user draft'}).inserted.length, 0);
assert.equal(run({hostname: 'fanyi.youdao.com.example.test', native: true}).queries, 0);
assert.equal(run({hostname: 'accounts.youdao.com', native: true}).queries, 0);
'''
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    });
  }
}
