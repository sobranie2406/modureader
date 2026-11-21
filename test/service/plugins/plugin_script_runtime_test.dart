import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_host_api.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/plugins/plugin_network_guard.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_trust.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

class _RuntimeFixtureTrust extends FixturePluginTrust {
  Map<String, String> sealed = {};
  @override
  Future<Map<String, String>?> reviewedFiles(String id, String version) async =>
      Map.unmodifiable(sealed);
}

class Engine implements PluginScriptEngine {
  Engine() {
    result.future.ignore();
  }
  final ready = Completer<void>();
  final result = Completer<Map<String, dynamic>>();
  late PluginHostCall call;
  late Map<String, Object?> input;
  String? source;
  int disposed = 0;
  @override
  Future<Map<String, dynamic>> execute(
      String source, Map<String, Object?> input,
      {required PluginHostCall onCall}) {
    this.source = source;
    this.input = input;
    call = onCall;
    ready.complete();
    return result.future;
  }

  @override
  Future<void> dispose() async {
    disposed++;
    if (!result.isCompleted) result.completeError(StateError('disposed'));
  }
}

class Http extends PluginHttpClient {
  int requests = 0;
  @override
  Future<Uint8List> get(
      {required PluginGuardResult target,
      required Duration timeout,
      required int maxBytes,
      required String pluginId,
      CancelTokenLike? cancel}) async {
    requests++;
    return Uint8List.fromList(utf8.encode('ok'));
  }
}

class _DiagnosticEngine extends WebViewPluginScriptEngine {
  final delegate = Engine();
  @override
  String get diagnosticStage => 'waiting_bridge';
  @override
  Future<Map<String, dynamic>> execute(
          String source, Map<String, Object?> input,
          {required PluginHostCall onCall}) =>
      delegate.execute(source, input, onCall: onCall);
  @override
  Future<void> dispose() => delegate.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PluginHost host;
  late PluginScriptRuntime runtime;
  late Engine engine;
  late ScriptActionContribution action;
  late Map<String, String> files;
  const id = 'com.modu.text-tools';

  Future<void> install(
      {List<String>? capabilities, Map<String, dynamic>? network}) async {
    final m = jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
    if (capabilities != null) m['capabilities'] = capabilities;
    if (network != null) m['network'] = network;
    files['manifest.json'] = jsonEncode(m);
    (host.trust as _RuntimeFixtureTrust).sealed = {
      for (final entry in files.entries)
        entry.key: sha256.convert(utf8.encode(entry.value)).toString()
    };
    await host.install(await writePluginZip(temp, files),
        allowSameVersion: true);
    action = host
        .manifestFor(id)!
        .contributions
        .whereType<ScriptActionContribution>()
        .first;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    temp = await Directory.systemTemp.createTemp('plugin_script_test');
    host = PluginHost(
        trust: _RuntimeFixtureTrust(),
        paths: PluginPaths(rootPath: '${temp.path}/plugins'),
        appVersionResolver: () async => '1.3.10');
    await host.initialize();
    files = {
      for (final f in Directory('test/fixtures/plugins/text-tools')
          .listSync()
          .whereType<File>())
        f.uri.pathSegments.last: await f.readAsString()
    };
    await install();
    engine = Engine();
    runtime = PluginScriptRuntime(
        host: host,
        engineFactory: () => engine,
        timeout: const Duration(seconds: 1));
  });
  tearDown(() async {
    runtime.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    host.dispose();
    await temp.delete(recursive: true);
  });

  Future<Map<String, dynamic>> run([Map<String, Object?> input = const {}]) =>
      runtime.run(pluginId: id, action: action, input: input);
  Matcher failure(String code) =>
      isA<PluginScriptFailure>().having((e) => e.code, 'code', code);

  Future<void> installPrivateControls() => install(capabilities: [
        'script:run',
        'ui:selection-action',
        'library:private',
        'library:private-control'
      ]);

  test('private-control methods require their declared capability', () async {
    await install(
        capabilities: ['script:run', 'ui:selection-action', 'library:private']);
    var calls = 0;
    final response = runtime.run(
        pluginId: id,
        action: action,
        hostCall: (_, __) async {
          calls++;
          return null;
        });
    await engine.ready.future;
    for (final method in [
      'state',
      'updateOptions',
      'selectBooks',
      'setPrivate'
    ]) {
      await expectLater(engine.call('privateLibrary.$method', {}),
          throwsA(failure('permission')));
    }
    expect(calls, 0);
    engine.result.complete({'text': ''});
    await response;
  });

  test('native picker wait does not exhaust the script execution budget',
      () async {
    await installPrivateControls();
    runtime.dispose();
    runtime = PluginScriptRuntime(
        host: host,
        engineFactory: () => engine,
        timeout: const Duration(seconds: 1),
        nativeInteractionTimeout: const Duration(seconds: 3));
    final waiting = Completer<Object?>();
    final response = runtime.run(
        pluginId: id, action: action, hostCall: (_, __) => waiting.future);
    await engine.ready.future;
    final call = engine.call('privateLibrary.selectBooks', {});
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(runtime.isRunning(id), true);
    waiting.complete(<Object>[]);
    expect(await call, isEmpty);
    engine.result.complete({'text': 'selected'});
    expect(await response, {'text': 'selected'});
  });

  test(
      'native waits share a cumulative budget and cannot revive a cancelled job',
      () async {
    await installPrivateControls();
    runtime.dispose();
    runtime = PluginScriptRuntime(
        host: host,
        engineFactory: () => engine,
        timeout: const Duration(seconds: 2),
        nativeInteractionTimeout: const Duration(milliseconds: 350));
    var waiting = Completer<Object?>();
    final response = runtime.run(
        pluginId: id, action: action, hostCall: (_, __) => waiting.future);
    final expired = expectLater(response, throwsA(failure('timeout')));
    await engine.ready.future;
    final first = engine.call('privateLibrary.selectBooks', {});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    waiting.complete(<Object>[]);
    await first;
    waiting = Completer<Object?>();
    final second =
        engine.call('privateLibrary.updateOptions', {'privateOnly': true});
    final rejected = expectLater(second, throwsA(failure('cancelled')));
    await expired;
    waiting.complete({'privateOnly': true});
    await rejected;
    expect(runtime.isRunning(id), false);
    expect(engine.disposed, greaterThan(0));
  });

  test('private state reads retain the ordinary execution deadline', () async {
    await installPrivateControls();
    runtime.dispose();
    runtime = PluginScriptRuntime(
        host: host,
        engineFactory: () => engine,
        timeout: const Duration(milliseconds: 500));
    final waiting = Completer<Object?>();
    final response = runtime.run(
        pluginId: id, action: action, hostCall: (_, __) => waiting.future);
    final expired = expectLater(response, throwsA(failure('timeout')));
    await engine.ready.future;
    final state = engine.call('privateLibrary.state', {});
    final rejected = expectLater(state, throwsA(failure('cancelled')));
    await expired;
    waiting.complete({});
    await rejected;
  });

  test('import policy receives a safe summary and cannot call host methods',
      () async {
    final m = jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
    (m['contributes'] as List).first['surface'] = 'bookImport';
    files['manifest.json'] = jsonEncode(m);
    await install(capabilities: [
      'script:run',
      'library:private',
      'library:private-policy'
    ]);
    final response = runtime.run(
        pluginId: id,
        action: action,
        input: {
          'selection': 'secret text',
          'context': 'private context',
          'book': {
            'id': 8,
            'title': 'A book',
            'format': 'epub',
            'filePath': '/secret',
            'md5': 'hidden'
          }
        },
        hostCall: (_, __) async => throw StateError('must not reach host'));
    await engine.ready.future;
    expect(engine.input.keys.toSet(), {'book', 'settings', 'actionId'});
    expect(
        engine.input['book'], {'id': 8, 'title': 'A book', 'format': 'epub'});
    for (final method in [
      'privateLibrary.state',
      'privateLibrary.selectBooks',
      'http.get',
      'library.list',
      'notes.save'
    ]) {
      await expectLater(
          engine.call(method, {}), throwsA(failure('permission')));
    }
    engine.result.complete({'private': true});
    expect(await response, {'private': true});
  });

  test('import policy rejects an ambiguous result', () async {
    final m = jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
    (m['contributes'] as List).first['surface'] = 'bookImport';
    files['manifest.json'] = jsonEncode(m);
    await install(capabilities: [
      'script:run',
      'library:private',
      'library:private-policy'
    ]);
    final response = run({
      'book': {'id': 1}
    });
    await engine.ready.future;
    engine.result.complete({'private': false, 'text': 'unexpected'});
    await expectLater(response, throwsA(failure('result')));
  });

  Future<void> installDictionary() async {
    final m = jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
    (m['contributes'] as List).first['surface'] = 'dictionary';
    files['manifest.json'] = jsonEncode(m);
    await install(capabilities: [
      'script:run',
      'dictionary:transform',
      'library:read',
      'note:write',
      'article:capture'
    ]);
  }

  test('dictionary scripts receive only the word and cannot call any host API',
      () async {
    await installDictionary();
    var called = false;
    final result = runtime.run(
        pluginId: id,
        action: action,
        input: {
          'selection': 'apples',
          'context': 'private context',
          'book': {'id': 1, 'title': 'Private book'}
        },
        hostCall: (_, __) async {
          called = true;
          return null;
        });
    await engine.ready.future;
    expect(engine.input['selection'], 'apples');
    expect(engine.input.keys.toSet(), {'selection', 'settings', 'actionId'});
    for (final method in [
      'library.list',
      'notes.save',
      'articles.capture',
      'http.get'
    ]) {
      await expectLater(
          engine.call(method, {}), throwsA(failure('permission')));
    }
    expect(called, false);
    engine.result.complete({
      'candidates': ['apple']
    });
    expect(await result, {
      'candidates': ['apple']
    });
  });

  test('a declared but ungranted capability reports denied, not permission',
      () async {
    // 'permission' means the package never declared the token; 'denied' means it
    // did and the reader has not switched it on. Collapsing the two sent people
    // looking for a broken package instead of the consent sheet.
    await install(capabilities: [
      'script:run',
      'ui:selection-action',
      'ui:dialog',
    ]);
    final result = runtime.run(
        pluginId: id,
        action: action,
        hostApi: PluginHostApi(
            pluginId: id,
            services: PluginHostServices(askConfirm: (_, __) async => true)));
    await engine.ready.future;
    await expectLater(engine.call('ui.confirm', {'title': 'a', 'message': 'b'}),
        throwsA(failure('denied')));
    // Granting the capability makes the same call succeed without a restart.
    await host.grantPermissions(id, ['ui:dialog']);
    expect(await engine.call('ui.confirm', {'title': 'a', 'message': 'b'}),
        {'confirmed': true});
    engine.result.complete({'text': ''});
    await result;
  });

  Future<void> installArticle({String? source, bool library = false}) async {
    final m = jsonDecode(files['manifest.json']!) as Map<String, dynamic>;
    final extract =
        Map<String, dynamic>.from((m['contributes'] as List).first as Map)
          ..['surface'] = 'article'
          ..['scope'] = 'selection';
    m['contributes'] = [
      extract,
      if (library) {...extract, 'id': 'open', 'surface': 'library'}
    ];
    files['manifest.json'] = jsonEncode(m);
    if (source != null) files['main.js'] = source;
    await install(capabilities: [
      'script:run',
      'article:extract',
      'library:read',
      'note:write',
      'article:capture',
      'net:http'
    ], network: {
      'domains': ['example.com'],
      'timeoutMs': 1000,
      'maxResponseBytes': 65536,
      'requestsPerLookup': 1
    });
  }

  Map<String, Object?> articleInput(String html) => {
        'html': html,
        'url': 'https://example.com/article?a=1',
        'plainText': false,
        'selection': 'do not disclose',
        'context': 'do not disclose',
        'book': {'id': 4, 'title': 'Private book'},
        'token': 'secret'
      };

  test(
      'article receives only fetched document fields and refuses every host API',
      () async {
    await installArticle();
    var called = false;
    final response = runtime.run(
        pluginId: id,
        action: action,
        input: articleInput('<article>text</article>'),
        hostCall: (_, __) async {
          called = true;
          return null;
        });
    await engine.ready.future;
    expect(engine.input.keys.toSet(),
        {'html', 'url', 'plainText', 'settings', 'actionId'});
    expect(engine.input['html'], '<article>text</article>');
    for (final method in [
      'http.get',
      'library.list',
      'notes.save',
      'articles.capture',
      'privateLibrary.open',
      'unknown'
    ]) {
      await expectLater(
          engine.call(method, {}), throwsA(failure('permission')));
    }
    expect(called, false);
    engine.result
        .complete({'title': 'Article', 'markdown': '# Article\n\nText'});
    expect((await response)['title'], 'Article');
  });

  test('article accepts its larger UTF8 document, source and Markdown budgets',
      () async {
    await installArticle(
        source: '//${'s' * (PluginLimits.maxArticleScriptBytes - 2)}');
    final html = 'h' * PluginLimits.maxArticleHtmlBytes;
    final markdown = '汉' * (PluginLimits.maxArticleMarkdownBytes ~/ 3) +
        'a' * (PluginLimits.maxArticleMarkdownBytes % 3);
    final response = run(articleInput(html));
    await engine.ready.future;
    expect(engine.source!.length, PluginLimits.maxArticleScriptBytes);
    expect(engine.input['html'], html);
    engine.result.complete({'title': '标' * 200, 'markdown': markdown});
    expect((await response)['markdown'], markdown);
  });

  test('article UTF8 HTML and source limits reject before execution', () async {
    await installArticle();
    await expectLater(
        run(articleInput('汉' * (PluginLimits.maxArticleHtmlBytes ~/ 3 + 1))),
        throwsA(failure('size')));
    expect(engine.source, null);
    await Future<void>.delayed(Duration.zero);
    engine = Engine();
    await installArticle(
        source: '//${'s' * (PluginLimits.maxArticleScriptBytes - 1)}');
    await expectLater(run(articleInput('text')), throwsA(failure('size')));
    expect(engine.source, null);
  });

  test('article privilege does not enlarge the same package library source',
      () async {
    await installArticle(
        source: '//${'s' * PluginLimits.maxScriptBytes}', library: true);
    final library = host
        .manifestFor(id)!
        .contributions
        .whereType<ScriptActionContribution>()
        .singleWhere((c) => c.surface == PluginScriptSurface.library);
    await expectLater(
        runtime.run(pluginId: id, action: library), throwsA(failure('size')));
    expect(engine.source, null);
  });

  test('article capability does not enlarge ordinary action results', () async {
    await install(
        capabilities: ['script:run', 'ui:selection-action', 'article:extract']);
    final response = run();
    await engine.ready.future;
    engine.result.complete({'text': 'x' * (64 * 1024)});
    await expectLater(response, throwsA(failure('size')));
  });

  for (final invalid in <Map<String, dynamic>>[
    {
      'title': 'Article',
      'markdown': '汉' * (PluginLimits.maxArticleMarkdownBytes ~/ 3 + 1)
    },
    {'title': 'x' * 201, 'markdown': 'text'},
    {'title': 'Article', 'markdown': 'text', 'html': '<script>'},
    {
      'title': 'Article',
      'markdown': 'text',
      'sourceUrl': 'https://forged.example'
    },
    {'title': 'Article', 'markdown': '\u0000text'},
    {'title': 'Article', 'text': 'wrong shape'},
  ].indexed) {
    test('article rejects invalid or oversized result ${invalid.$1}', () async {
      await installArticle();
      final response = run(articleInput('text'));
      await engine.ready.future;
      engine.result.complete(invalid.$2);
      await expectLater(
          response, throwsA(failure(invalid.$1 == 0 ? 'size' : 'result')));
    });
  }

  test(
      'article rejects non-native-shaped document input without starting engine',
      () async {
    await installArticle();
    await expectLater(
        run({'html': 'text', 'url': 'http://example.com', 'plainText': false}),
        throwsA(failure('result')));
    expect(engine.source, null);
  });

  test(
      'pre-cancelled and rejected busy-job tokens cannot cancel an accepted job',
      () async {
    final cancelled = PluginCancelToken()..cancel();
    await expectLater(
        runtime.run(pluginId: id, action: action, cancel: cancelled),
        throwsA(failure('cancelled')));
    expect(engine.source, null);
    final accepted = PluginCancelToken(), rejected = PluginCancelToken();
    final response =
        runtime.run(pluginId: id, action: action, cancel: accepted);
    await engine.ready.future;
    await expectLater(
        runtime.run(pluginId: id, action: action, cancel: rejected),
        throwsA(failure('busy')));
    rejected.cancel();
    expect(engine.disposed, 0);
    final stopped = expectLater(response, throwsA(failure('cancelled')));
    accepted.cancel();
    await stopped;
  });

  test('a completed job token never cancels its same-ID successor', () async {
    final old = PluginCancelToken();
    final first = runtime.run(pluginId: id, action: action, cancel: old);
    await engine.ready.future;
    engine.result.complete({'text': 'first'});
    await first;
    await Future<void>.delayed(Duration.zero);
    engine = Engine();
    final next = runtime.run(pluginId: id, action: action);
    await engine.ready.future;
    old.cancel();
    expect(engine.disposed, 0);
    engine.result.complete({'text': 'second'});
    expect(await next, {'text': 'second'});
  });

  test(
      'dictionary output rejects control characters and unrelated result fields',
      () async {
    await installDictionary();
    final result = run({'selection': 'word'});
    await engine.ready.future;
    engine.result.complete({
      'candidates': ['bad\nword'],
      'text': 'unexpected'
    });
    await expectLater(result, throwsA(failure('result')));
  });

  test('runs reviewed source with only selected scope and declared settings',
      () async {
    final result = run({
      'selection': '文 字',
      'context': 'not allowed',
      'apiKey': 'secret',
      'actionId': 'forged',
      'book': {
        'id': 3,
        'title': '书',
        'filePath': '/private',
        'password': 'secret'
      }
    });
    await engine.ready.future;
    expect(engine.source, files['main.js']);
    expect(engine.input['selection'], '文 字');
    expect(engine.input.containsKey('context'), false);
    expect(engine.input.containsKey('apiKey'), false);
    expect(engine.input['actionId'], action.id);
    expect(engine.input['book'], {'id': 3, 'title': '书'});
    engine.result.complete({'title': 'Result', 'text': 'ok'});
    expect(await result, {'title': 'Result', 'text': 'ok'});
  });
  test('denies undeclared host methods and avoids calling host', () async {
    var called = false;
    final result = runtime.run(
        pluginId: id,
        action: action,
        hostCall: (_, __) async {
          called = true;
          return null;
        });
    await engine.ready.future;
    for (final method in [
      'library.list',
      'notes.save',
      'privateLibrary.open',
      'articles.capture',
      'http.get',
      'settings.read'
    ]) {
      await expectLater(
          engine.call(method, {}), throwsA(failure('permission')));
    }
    expect(called, false);
    engine.result.complete({'text': 'ok'});
    await result;
  });

  test('article capture is an explicit granted host action', () async {
    await install(
        capabilities: ['script:run', 'ui:selection-action', 'article:capture']);
    var called = false;
    final result = runtime.run(
        pluginId: id,
        action: action,
        hostCall: (method, args) async {
          expect(method, 'articles.capture');
          expect(args, isEmpty);
          called = true;
          return {'opened': true};
        });
    await engine.ready.future;
    expect(await engine.call('articles.capture', {}), {'opened': true});
    expect(called, true);
    engine.result.complete({'text': ''});
    await result;
  });
  test('one invocation per plugin and cancellation releases engine', () async {
    final result = run();
    await engine.ready.future;
    await expectLater(run(), throwsA(failure('busy')));
    final stopped = expectLater(result, throwsA(failure('cancelled')));
    runtime.cancelPlugin(id);
    await stopped;
    await expectLater(
        engine.call('library.list', {}), throwsA(failure('cancelled')));
    expect(engine.disposed, greaterThan(0));
  });
  test('an aborted job stops reserving the plugin once its engine releases',
      () async {
    // The slot used to be released only when the engine answered its disposal,
    // so an engine that never answers kept the plugin — and, through the global
    // two-job cap, every other plugin — permanently "busy".
    final engines = <Engine>[];
    runtime.dispose();
    runtime = PluginScriptRuntime(
        host: host,
        engineFactory: () {
          final created = Engine();
          engines.add(created);
          return created;
        },
        timeout: const Duration(milliseconds: 50));
    await expectLater(run(), throwsA(failure('timeout')));
    expect(engines.first.disposed, greaterThan(0));
    // The released slot is reusable immediately in this fixture: Engine.dispose
    // resolves at once, so the teardown map is cleared with it.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final second = run();
    await engines.last.ready.future;
    engines.last.result.complete({'text': 'again'});
    expect(await second, {'text': 'again'});
    expect(engines.length, 2);
  });

  test('bounds structured results and rejects HTML/action payload fields',
      () async {
    final result = run();
    await engine.ready.future;
    engine.result.complete({'text': 'ok', 'html': '<script>'});
    await expectLater(result, throwsA(failure('result')));
  });
  test('bounds input before engine creation', () async {
    await expectLater(
        run({'selection': 'x' * 70000}), throwsA(failure('size')));
    expect(engine.source, null);
  });
  test('timeout stops an unresponsive engine', () async {
    runtime.dispose();
    runtime = PluginScriptRuntime(
        host: host,
        engineFactory: () => engine,
        timeout: const Duration(milliseconds: 50));
    await expectLater(run(), throwsA(failure('timeout')));
    expect(engine.disposed, greaterThan(0));
  });
  test('timeout logs one safe warning with action, elapsed time and stage',
      () async {
    final records = <LogRecord>[];
    final listener = AnxLog.log.onRecord.listen(records.add);
    addTearDown(listener.cancel);
    runtime.dispose();
    runtime = PluginScriptRuntime(
        host: host,
        engineFactory: () => engine,
        timeout: const Duration(milliseconds: 50));
    await expectLater(
        run({'selection': 'PRIVATE_SELECTION', 'context': 'PRIVATE_CONTEXT'}),
        throwsA(failure('timeout')));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final record = records
        .singleWhere((r) => r.message.startsWith('Plugin script failed:'));
    expect(record.level, Level.WARNING);
    expect(record.message,
        contains('plugin=$id version=1.0.0 action=${action.id}'));
    expect(record.message, contains('code=timeout stage=execute'));
    expect(record.message, matches(r'elapsed_ms=\d+'));
    expect(record.message, isNot(contains('PRIVATE_')));
    expect(record.error, isNull);
    expect(record.stackTrace, isNull);
  });
  test('execution errors never log private exception text, source or inputs',
      () async {
    final records = <LogRecord>[];
    final listener = AnxLog.log.onRecord.listen(records.add);
    addTearDown(listener.cancel);
    final result = run({
      'selection': 'PRIVATE_SELECTION',
      'context': 'PRIVATE_CONTEXT',
      'book': {'title': 'PRIVATE_BOOK'}
    });
    await engine.ready.future;
    engine.result
        .completeError(StateError('PRIVATE_ERROR https://secret.example/PIN '
            'PRIVATE_SETTING PRIVATE_SOURCE /Users/private/book.epub'));
    await expectLater(result, throwsA(failure('execution')));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final record = records
        .singleWhere((r) => r.message.startsWith('Plugin script failed:'));
    expect(record.level, Level.WARNING);
    expect(record.message, contains('code=execution stage=execute'));
    expect(record.message, isNot(contains('PRIVATE_')));
    expect(record.message, isNot(contains('https://')));
    expect(record.message, isNot(contains('/Users/')));
    expect(record.message, isNot(contains(engine.source!)));
    expect(record.error, isNull);
    expect(record.stackTrace, isNull);
  });
  test('cancellation is recorded once as info despite late engine errors',
      () async {
    final records = <LogRecord>[];
    final listener = AnxLog.log.onRecord.listen(records.add);
    addTearDown(listener.cancel);
    final result = run();
    await engine.ready.future;
    final cancelled = expectLater(result, throwsA(failure('cancelled')));
    runtime.cancelPlugin(id);
    runtime.cancelPlugin(id);
    await cancelled;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final record = records
        .singleWhere((r) => r.message.startsWith('Plugin script failed:'));
    expect(record.level, Level.INFO);
    expect(record.message, contains('code=cancelled'));
    expect(records.where((r) => r.level >= Level.WARNING), isEmpty);
  });
  test('unknown failure codes cannot inject private values into diagnostics',
      () async {
    final records = <LogRecord>[];
    final listener = AnxLog.log.onRecord.listen(records.add);
    addTearDown(listener.cancel);
    final result = run();
    await engine.ready.future;
    engine.result.completeError(
        const PluginScriptFailure('PRIVATE_CODE https://secret.example'));
    await expectLater(result, throwsA(isA<PluginScriptFailure>()));
    final record = records
        .singleWhere((r) => r.message.startsWith('Plugin script failed:'));
    expect(record.message, contains('code=execution'));
    expect(record.message, isNot(contains('PRIVATE_CODE')));
    expect(record.message, isNot(contains('https://')));
  });
  test('a WebView timeout records its concrete bridge or worker stage',
      () async {
    final records = <LogRecord>[];
    final listener = AnxLog.log.onRecord.listen(records.add);
    addTearDown(listener.cancel);
    runtime.dispose();
    final diagnostic = _DiagnosticEngine();
    runtime = PluginScriptRuntime(
        host: host,
        engineFactory: () => diagnostic,
        timeout: const Duration(milliseconds: 50));
    final result = run();
    await diagnostic.delegate.ready.future;
    await expectLater(result, throwsA(failure('timeout')));
    final record = records
        .singleWhere((r) => r.message.startsWith('Plugin script failed:'));
    expect(record.message, contains('code=timeout stage=waiting_bridge'));
  });
  test(
      'unavailable metadata cannot inject a URL or multiline content into logs',
      () async {
    final records = <LogRecord>[];
    final listener = AnxLog.log.onRecord.listen(records.add);
    addTearDown(listener.cancel);
    await expectLater(
        runtime.run(
            pluginId: 'https://PRIVATE_URL\nPRIVATE_TEXT', action: action),
        throwsA(failure('unavailable')));
    final record = records
        .singleWhere((r) => r.message.startsWith('Plugin script failed:'));
    expect(record.message, contains('plugin=unknown'));
    expect(record.message, contains('code=unavailable stage=validate'));
    expect(record.message, isNot(contains('PRIVATE_')));
    expect(record.message, isNot(contains('https://')));
    expect(record.message, isNot(contains('\n')));
  });
  test('rejects source changes even with injected manifest trust', () async {
    await File('${host.paths.pluginDir(id).path}/main.js')
        .writeAsString('return {text:"changed"};');
    await expectLater(run(), throwsA(failure('unavailable')));
    expect(engine.source, null);
  });
  test('cancelled DNS resolution cannot send a later request', () async {
    runtime.dispose();
    await install(capabilities: [
      'script:run',
      'ui:selection-action',
      'net:http'
    ], network: {
      'domains': ['example.com']
    });
    // net:http is a runtime grant now; the network path is only reached after
    // the user has switched it on.
    await host.setPermission(id, 'net:http', true);
    final dns = Completer<List<InternetAddress>>();
    final http = Http();
    runtime = PluginScriptRuntime(
        host: host,
        engineFactory: () => engine,
        networkGuard: PluginNetworkGuard(resolver: (_) => dns.future),
        httpClient: http);
    final result = run();
    await engine.ready.future;
    final call = engine.call('http.get', {'url': 'https://example.com/test'});
    final done = expectLater(result, throwsA(failure('cancelled')));
    final refused = expectLater(call, throwsA(failure('cancelled')));
    runtime.cancelPlugin(id);
    dns.complete([InternetAddress('8.8.8.8')]);
    await done;
    await refused;
    expect(http.requests, 0);
  });

  test('approved package inventories match the separately distributed sources',
      () async {
    for (final package in ['text-tools', 'private-books']) {
      await PluginTrust().verify(Directory('test/fixtures/plugins/$package'),
          package == 'text-tools' ? id : 'com.modu.private-books', '1.0.0');
    }
  });

  test('a revoked reading context blocks network before DNS', () async {
    runtime.dispose();
    await install(capabilities: [
      'script:run',
      'ui:selection-action',
      'net:http'
    ], network: {
      'domains': ['example.com']
    });
    // net:http is a runtime grant now; the network path is only reached after
    // the user has switched it on.
    await host.setPermission(id, 'net:http', true);
    var valid = true, resolved = false;
    final http = Http();
    runtime = PluginScriptRuntime(
        host: host,
        engineFactory: () => engine,
        httpClient: http,
        networkGuard: PluginNetworkGuard(resolver: (_) async {
          resolved = true;
          return [InternetAddress('8.8.8.8')];
        }));
    final result =
        runtime.run(pluginId: id, action: action, isContextValid: () => valid);
    await engine.ready.future;
    valid = false;
    await expectLater(engine.call('http.get', {'url': 'https://example.com'}),
        throwsA(failure('cancelled')));
    expect(resolved, false);
    expect(http.requests, 0);
    final stopped = expectLater(result, throwsA(failure('cancelled')));
    runtime.cancelAll();
    await stopped;
  });

  test('network is restricted to declared domains and one GET', () async {
    runtime.dispose();
    await install(capabilities: [
      'script:run',
      'ui:selection-action',
      'net:http'
    ], network: {
      'domains': ['example.com']
    });
    // net:http is a runtime grant now; the network path is only reached after
    // the user has switched it on.
    await host.setPermission(id, 'net:http', true);
    final http = Http();
    runtime = PluginScriptRuntime(
        host: host,
        engineFactory: () => engine,
        httpClient: http,
        networkGuard: PluginNetworkGuard(
            resolver: (_) async => [InternetAddress('8.8.8.8')]));
    final result = run();
    await engine.ready.future;
    expect(await engine.call('http.get', {'url': 'https://example.com/test'}),
        {'text': 'ok'});
    await expectLater(
        engine.call('http.get', {'url': 'https://example.com/test'}),
        throwsA(failure('quota')));
    expect(http.requests, 1);
    engine.result.complete({'text': 'ok'});
    await result;
  });
}
