import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/plugins/plugin_network_guard.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_trust.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

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
        trust: FixturePluginTrust(),
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
