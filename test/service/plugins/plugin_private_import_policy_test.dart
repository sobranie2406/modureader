import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/handlers/script_action_handler.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_private_import_policy.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/service/plugins/plugin_host_api.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

class _Host extends PluginHost {
  _Host(this.id) : manifest = createManifest(id);
  final String id;
  PluginManifest manifest;
  bool runnable = true;
  Map<String, dynamic> config = {};
  static PluginManifest createManifest(String id) =>
      PluginManifest.parse(manifestJson(id: id, capabilities: [
        'script:run',
        'library:private',
        'library:private-policy'
      ], contributes: [
        {
          'kind': 'scriptAction',
          'schema': 1,
          'id': 'policy',
          'name': 'Policy',
          'entry': 'policy.js',
          'surface': 'bookImport',
          'scope': 'selection',
          'enabledSetting': 'enabled'
        }
      ], settings: [
        {'key': 'enabled', 'type': 'toggle', 'defaultValue': true},
        {'key': 'rule', 'type': 'text', 'defaultValue': 'old'}
      ]));
  @override
  PluginManifest? manifestFor(String id) => manifest;
  @override
  bool isScriptRunnable(String id) => runnable;
  @override
  Map<String, dynamic> configFor(String id) => Map.of(config);
}

class _Runtime extends PluginScriptRuntime {
  _Runtime(PluginHost host) : super(host: host);
  int calls = 0;
  Map<String, Object?>? received;
  bool Function()? current;
  Future<Map<String, dynamic>> Function() result =
      () async => {'private': false};
  @override
  Future<Map<String, dynamic>> run(
      {required String pluginId,
      required ScriptActionContribution action,
      Map<String, Object?> input = const {},
      PluginHostCall? hostCall,
      PluginHostApi? hostApi,
      bool Function()? isContextValid,
      PluginCancelToken? cancel}) {
    calls++;
    received = input;
    current = isContextValid;
    return result();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PluginScriptActionRegistry registry;
  final hosts = <String, _Host>{};
  final runtimes = <String, _Runtime>{};
  final book = Book.mock().copyWith(
      id: -1,
      title: 'Pending title',
      author: 'Pending author',
      filePath: '/PRIVATE_USER_HOME/book.epub',
      md5: 'PRIVATE_CHECKSUM');
  Matcher failure(String code) =>
      isA<PluginScriptFailure>().having((error) => error.code, 'code', code);
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    registry = PluginScriptActionRegistry();
  });
  tearDown(() {
    for (final runtime in runtimes.values) {
      runtime.dispose();
    }
    for (final host in hosts.values) {
      host.dispose();
    }
    registry.dispose();
    hosts.clear();
    runtimes.clear();
  });
  _Host add(String name) {
    final host = _Host('com.example.$name');
    hosts[host.id] = host;
    runtimes[host.id] = _Runtime(host);
    registry.replacePlugin(
        host.id,
        host.manifest.contributions
            .whereType<ScriptActionContribution>()
            .toList());
    return host;
  }

  Future<bool?> evaluate([Book? value]) =>
      PluginPrivateImportPolicy.evaluate(value ?? book,
          registry: registry,
          resolveHost: (id) => hosts[id]!,
          resolveRuntime: (id) => runtimes[id]!);

  test('no active import policy returns null and creates no worker', () async {
    expect(await evaluate(), isNull);
    final host = add('inactive');
    host.runnable = false;
    expect(await evaluate(), isNull);
    expect(runtimes[host.id]!.calls, 0);
  });

  test(
      'an explicit false setting skips its worker and returns a public decision',
      () async {
    final host = add('gated');
    host.config['enabled'] = false;
    expect(await evaluate(), false);
    expect(runtimes[host.id]!.calls, 0);
  });

  test('only safe pending-book metadata enters the policy', () async {
    final host = add('metadata');
    await evaluate();
    final input = runtimes[host.id]!.received!;
    expect(input.keys, ['book']);
    expect(input['book'], {
      'id': -1,
      'title': book.title,
      'author': book.author,
      'format': 'epub'
    });
    expect(jsonEncode(input), isNot(contains('PRIVATE_USER_HOME')));
    expect(jsonEncode(input), isNot(contains('PRIVATE_CHECKSUM')));
    await evaluate(book.copyWith(filePath: '/PRIVATE_USER_HOME/no-extension'));
    expect(jsonEncode(runtimes[host.id]!.received),
        isNot(contains('PRIVATE_USER_HOME')));
  });

  test(
      'plugin true and false decisions are preserved across multiple providers',
      () async {
    final first = add('first');
    final second = add('second');
    expect(await evaluate(), false);
    runtimes[second.id]!.result = () async => {'private': true};
    expect(await evaluate(), true);
    expect(runtimes[first.id]!.calls, 2);
  });

  test('malformed or failed policies abort rather than falling back to public',
      () async {
    final host = add('failure');
    final runtime = runtimes[host.id]!;
    for (final invalid in [
      <String, dynamic>{},
      {'private': 'true'},
      {'private': false, 'extra': true}
    ]) {
      runtime.result = () async => invalid;
      await expectLater(evaluate(), throwsA(failure('result')));
    }
    runtime.result = () async => throw const PluginScriptFailure('timeout');
    await expectLater(evaluate(), throwsA(failure('timeout')));
  });

  test('same-version owner reload rejects a delayed policy result', () async {
    final host = add('reload');
    final runtime = runtimes[host.id]!;
    final result = Completer<Map<String, dynamic>>();
    runtime.result = () => result.future;
    final request = evaluate();
    final rejected = expectLater(request, throwsA(failure('cancelled')));
    host.manifest = _Host.createManifest(host.id);
    expect(runtime.current!(), false);
    result.complete({'private': false});
    await rejected;
  });

  test('settings changing during a policy invalidate its old public result',
      () async {
    final host = add('settings');
    final runtime = runtimes[host.id]!;
    final result = Completer<Map<String, dynamic>>();
    runtime.result = () => result.future;
    final request = evaluate();
    final rejected = expectLater(request, throwsA(failure('cancelled')));
    host.config['rule'] = 'new';
    result.complete({'private': false});
    await rejected;
  });

  test('earlier policy settings remain guarded while later policies execute',
      () async {
    final first = add('earlier');
    final second = add('later');
    final started = Completer<void>();
    final result = Completer<Map<String, dynamic>>();
    runtimes[second.id]!.result = () {
      started.complete();
      return result.future;
    };
    final request = evaluate();
    final rejected = expectLater(request, throwsA(failure('cancelled')));
    await started.future;
    first.config['enabled'] = false;
    result.complete({'private': false});
    await rejected;
  });

  test('native binding changes invalidate an in-flight import before insertion',
      () async {
    final host = add('native');
    final result = Completer<Map<String, dynamic>>();
    runtimes[host.id]!.result = () => result.future;
    final library = PrivateLibrary(preferences: Prefs().prefs)
      ..setPluginActive(true)
      ..importPolicy = ((value) => evaluate(value));
    addTearDown(library.dispose);
    await library.unlock();
    final importing = library.onImported(book, isNew: true);
    final rejected = expectLater(importing, throwsStateError);
    await library.setOptions(autoImport: true);
    result.complete({'private': false});
    await rejected;
    expect(library.isPrivate(book), false);
  });
}
