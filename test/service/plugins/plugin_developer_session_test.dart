import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/service/plugins/handlers/script_action_handler.dart';
import 'package:modu_reader/service/plugins/plugin_developer_session.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/plugins/plugin_trust.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

class _Engine implements PluginScriptEngine {
  final ready = Completer<void>();
  Completer<Map<String, dynamic>>? pending;
  Map<String, Object?>? input;
  PluginHostCall? call;
  int disposed = 0;
  Future<Map<String, dynamic>> Function(PluginHostCall)? handler;
  @override
  Future<Map<String, dynamic>> execute(
      String source, Map<String, Object?> input,
      {required PluginHostCall onCall}) {
    this.input = input;
    call = onCall;
    ready.complete();
    return pending?.future ??
        handler?.call(onCall) ??
        Future.value({'text': 'done'});
  }

  @override
  Future<void> dispose() async {
    disposed++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PluginHost official;
  late PluginDeveloperSession session;
  late List<_Engine> engines;
  _Engine Function()? nextEngine;
  const id = 'dev.example.echo';
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    temp = await Directory.systemTemp.createTemp('modu-plugin-dev-');
    official = PluginHost(
        paths: PluginPaths(rootPath: '${temp.path}/official'),
        trust: FixturePluginTrust(),
        appVersionResolver: () async => '1.3.10');
    await official.initialize();
    engines = [];
    nextEngine = null;
    session = PluginDeveloperSession(
        officialHost: official,
        cacheDirectory: () async =>
            Directory('${temp.path}/cache')..createSync(),
        engineFactory: () {
          final engine = nextEngine?.call() ?? _Engine();
          engines.add(engine);
          return engine;
        });
  });
  tearDown(() async {
    session.dispose();
    official.dispose();
    await Future<void>.delayed(Duration.zero);
    await temp.delete(recursive: true);
  });
  Future<File> package(
          {String packageId = id,
          String source = 'return {text:"done"};',
          List<String> capabilities = const ['script:run'],
          List<Map<String, Object?>>? contributions}) =>
      writePluginZip(temp, {
        'manifest.json': manifestJson(
            id: packageId,
            capabilities: capabilities,
            settings: [
              {'key': 'label', 'type': 'text', 'defaultValue': 'default'}
            ],
            contributes: contributions ??
                [
                  {
                    'kind': 'scriptAction',
                    'schema': 1,
                    'id': 'echo',
                    'name': 'Echo',
                    'entry': 'main.js',
                    'surface': 'library'
                  }
                ]),
        'main.js': source,
      });
  Future<void> install(File file) async {
    final preview = await session.preview(file);
    await session.install(file, expectedSha256: preview.sha256);
  }

  ScriptActionContribution action() => session.host!
      .manifestFor(id)!
      .contributions
      .whereType<ScriptActionContribution>()
      .single;
  Future<Map<String, dynamic>> run() =>
      session.runtime!.run(pluginId: id, action: action());

  test(
      'default off; preview neither accepts source nor touches official state/proofs',
      () async {
    final file = await package();
    expect(session.enabled, false);
    await expectLater(
        session.preview(file), throwsA(isA<PluginInstallError>()));
    final keys = Prefs().prefs.getKeys();
    await session.setEnabled(true);
    await session.preview(file);
    expect(session.host!.plugins, isEmpty);
    await expectLater(
        session.host!.install(file), throwsA(isA<PluginInstallError>()));
    expect(await PluginTrust().reviewedFiles(id, '1.0.0'), isNull);
    expect(Prefs().pluginState.plugins, isEmpty);
    expect(Prefs().prefs.getKeys(), keys);
    expect(
        await Directory('${session.host!.paths.root.path}/.catalog-proofs')
            .exists(),
        false);
  });

  test(
      'confirmed developer package runs with memory-only configuration and diagnostics',
      () async {
    await Prefs().savePluginConfig(id, {'label': 'official-config'});
    final before = Prefs().pluginState.toJson();
    await session.setEnabled(true);
    await install(await package());
    await session.host!.saveConfig(id, {'label': 'local-debug'});
    expect(await run(), {'text': 'done'});
    expect((engines.single.input!['settings'] as Map)['label'], 'local-debug');
    expect(Prefs().pluginConfig(id)['label'], 'official-config');
    expect(Prefs().pluginState.toJson(), before);
    expect(session.logs.map((e) => e.code),
        containsAll(['installed', 'started', 'completed']));
    expect(PluginHost.executionHostFor(id), same(session.host));
    expect(PluginHost.runtimeFor(id), same(session.runtime));
    expect(PluginScriptActionRegistry.instance.forPlugin(id), hasLength(1));
  });

  test('normal project trust never accepts a developer-approved package',
      () async {
    await session.setEnabled(true);
    await install(await package());
    final owner = session.host!;
    await expectLater(
        PluginTrust().verify(owner.paths.pluginDir(id), id, '1.0.0'),
        throwsA(isA<PluginInstallError>()));
    await expectLater(
        owner.trust.acceptCatalog('{}'), throwsA(isA<PluginInstallError>()));
  });

  test(
      'changed package after preview and modified installed source are rejected',
      () async {
    await session.setEnabled(true);
    final file = await package();
    final preview = await session.preview(file);
    final changed = await package(source: 'return {text:"changed"};');
    await expectLater(session.install(changed, expectedSha256: preview.sha256),
        throwsA(isA<PluginInstallError>()));
    expect(session.host!.plugins, isEmpty);
    await install(file);
    await File('${session.host!.paths.pluginDir(id).path}/main.js')
        .writeAsString('tampered');
    await expectLater(run(), throwsA(isA<PluginScriptFailure>()));
    expect(engines.single.input, isNull);
  });

  test(
      'persistent declarative contributions are explicitly rejected before installation',
      () async {
    await session.setEnabled(true);
    final file = await package(
        capabilities: ['ai:prompt-pack'], contributions: [aiSkill()]);
    await expectLater(
        session.preview(file),
        throwsA(isA<PluginInstallError>().having((e) => e.message, 'message',
            contains('scriptAction and bookAction only'))));
    expect(Prefs().userPrompts, isEmpty);
    expect(session.host!.plugins, isEmpty);
  });

  test(
      'developer session cannot replace disabled official packages with the same ID',
      () async {
    final file = await package();
    await official.install(file);
    await official.disable(id);
    await session.setEnabled(true);
    await expectLater(
        session.preview(file), throwsA(isA<PluginInstallError>()));
    expect(official.byId(id)!.status, PluginStatus.disabled);
    expect(session.host!.plugins, isEmpty);
  });

  test(
      'official installation cannot replace a developer package with the same ID',
      () async {
    final file = await package();
    await session.setEnabled(true);
    await install(file);
    await expectLater(
        official.install(file), throwsA(isA<PluginInstallError>()));
    expect(session.host!.plugins, hasLength(1));
    expect(official.plugins, isEmpty);
  });

  test(
      'concurrent official and developer installs reserve an ID for exactly one owner',
      () async {
    final file = await package();
    await session.setEnabled(true);
    final preview = await session.preview(file);
    final results = await Future.wait([
      official
          .install(file)
          .then<Object>((_) => true, onError: (Object e) => e),
      session
          .install(file, expectedSha256: preview.sha256)
          .then<Object>((_) => true, onError: (Object e) => e),
    ]);
    expect(results.where((r) => r == true), hasLength(1));
    expect(results.whereType<PluginInstallError>(), hasLength(1));
    expect(official.plugins.length + session.host!.plugins.length, 1);
  });

  test(
      'same-version reload cancels the old job and replaces its manifest identity',
      () async {
    await session.setEnabled(true);
    await install(await package());
    final oldManifest = session.host!.manifestFor(id);
    final engine = _Engine()..pending = Completer<Map<String, dynamic>>();
    nextEngine = () => engine;
    final pending = run();
    final rejected = expectLater(
        pending,
        throwsA(isA<PluginScriptFailure>()
            .having((e) => e.code, 'code', 'cancelled')));
    await engine.ready.future;
    final file = await package(source: 'return {text:"reloaded"};');
    final preview = await session.preview(file);
    await session.reload(file, expectedSha256: preview.sha256);
    await rejected;
    expect(session.host!.manifestFor(id), isNot(same(oldManifest)));
    engine.pending!.complete({'text': 'old late result'});
    await Future<void>.delayed(Duration.zero);
    expect(session.logs.any((e) => e.code == 'cancelled'), true);
  });

  test(
      'closing cancels jobs, removes only development contributions/configuration and cache',
      () async {
    await official.install(await package(packageId: 'official.example.echo'));
    await session.setEnabled(true);
    await install(await package());
    await session.host!.saveConfig(id, {'label': 'private debug value'});
    final directory = session.host!.paths.root;
    final engine = _Engine()..pending = Completer<Map<String, dynamic>>();
    nextEngine = () => engine;
    final pending = run();
    final rejected = expectLater(pending, throwsA(isA<PluginScriptFailure>()));
    await engine.ready.future;
    await session.setEnabled(false);
    await rejected;
    engine.pending!.complete({'text': 'late'});
    expect(session.enabled, false);
    expect(session.host, isNull);
    expect(session.logs, isEmpty);
    expect(await directory.exists(), false);
    expect(PluginScriptActionRegistry.instance.forPlugin(id), isEmpty);
    expect(
        PluginScriptActionRegistry.instance.forPlugin('official.example.echo'),
        hasLength(1));
    expect(official.byId('official.example.echo'), isNotNull);
    expect(Prefs().pluginState.plugins.single.id, 'official.example.echo');
  });

  test(
      'global plugins switch closes development session and leaves no developer state',
      () async {
    await session.setEnabled(true);
    await install(await package());
    final directory = session.host!.paths.root;
    await official.setExperimentalEnabled(false);
    expect(Prefs().experimentalPluginsEnabled, false);
    expect(session.enabled, false);
    expect(await directory.exists(), false);
    expect(PluginScriptActionRegistry.instance.forPlugin(id), isEmpty);
    await expectLater(
        session.setEnabled(true), throwsA(isA<PluginInstallError>()));
  });

  test('restarting does not accept or execute the last developer package',
      () async {
    await session.setEnabled(true);
    await install(await package());
    final directory = session.host!.paths.root;
    session.dispose();
    await Future<void>.delayed(Duration.zero);
    session = PluginDeveloperSession(
        officialHost: official,
        cacheDirectory: () async => Directory('${temp.path}/cache'));
    expect(session.enabled, false);
    expect(session.host, isNull);
    await session.setEnabled(true);
    expect(session.host!.plugins, isEmpty);
    expect(await directory.exists(), false);
  });

  test(
      'developer privacy activates native policy, and cancelled removal preserves it',
      () async {
    await session.setEnabled(true);
    await install(
        await package(capabilities: ['script:run', 'library:private']));
    expect(PrivateLibrary.instance.active, true);
    await expectLater(
        session.setEnabled(false), throwsA(isA<PluginInstallError>()));
    expect(session.enabled, true);
    expect(session.host!.plugins, hasLength(1));
    await expectLater(official.setExperimentalEnabled(false),
        throwsA(isA<PluginInstallError>()));
    expect(session.enabled, true);
    expect(Prefs().experimentalPluginsEnabled, true);
    expect(PrivateLibrary.instance.active, true);
  });

  test(
      'ungranted native calls fail and logs never include source/settings/inputs',
      () async {
    await session.setEnabled(true);
    await install(await package(source: 'SOURCE_SECRET'));
    await session.host!.saveConfig(id, {'label': 'CONFIG_SECRET'});
    nextEngine = () => _Engine()
      ..handler = (call) async {
        await call('notes.save', {'text': 'INPUT_SECRET'});
        return {};
      };
    await expectLater(
        run(),
        throwsA(isA<PluginScriptFailure>()
            .having((e) => e.code, 'code', 'permission')));
    final log = session.logs.map((e) => e.message).join('\n');
    expect(log, contains('permission'));
    for (final secret in ['SOURCE_SECRET', 'CONFIG_SECRET', 'INPUT_SECRET']) {
      expect(log, isNot(contains(secret)));
    }
  });

  test('restoring official state never steals the live development registry',
      () async {
    final file = await package();
    await session.setEnabled(true);
    await install(file);
    final devAction = PluginScriptActionRegistry.instance.forPlugin(id).single;
    final record = session.host!.byId(id)!;
    final target = official.paths.pluginDir(id);
    await target.create(recursive: true);
    for (final source
        in session.host!.paths.pluginDir(id).listSync().whereType<File>()) {
      await source.copy('${target.path}/${source.uri.pathSegments.last}');
    }
    await Prefs().savePluginState(PluginState(plugins: [record]));
    await official.initialize();
    expect(official.byId(id)!.status, PluginStatus.disabled);
    expect(PluginScriptActionRegistry.instance.forPlugin(id).single,
        same(devAction));
    await expectLater(official.enable(id), throwsA(isA<PluginInstallError>()));
    expect(PluginScriptActionRegistry.instance.forPlugin(id).single,
        same(devAction));
  });

  test('closing one private provider preserves an enabled official provider',
      () async {
    await official.install(await package(
        packageId: 'official.example.private',
        capabilities: ['script:run', 'library:private']));
    await session.setEnabled(true);
    await install(
        await package(capabilities: ['script:run', 'library:private']));
    expect(PrivateLibrary.instance.active, true);
    await session.setEnabled(false);
    expect(session.enabled, false);
    expect(PrivateLibrary.instance.active, true);
    expect(official.byId('official.example.private')!.status,
        PluginStatus.enabled);
  });

  test('disposing while startup awaits cache cannot revive a developer session',
      () async {
    session.dispose();
    final cacheReady = Completer<Directory>();
    final closing = PluginDeveloperSession(
        officialHost: official, cacheDirectory: () => cacheReady.future);
    final pending = closing.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    closing.dispose();
    cacheReady.complete(Directory('${temp.path}/late-cache'));
    await expectLater(pending, throwsStateError);
    expect(closing.enabled, false);
    expect(PluginHost.hasDevelopmentSession, false);
    expect(await Directory('${temp.path}/late-cache').exists(), false);
    session = PluginDeveloperSession(
        officialHost: official,
        cacheDirectory: () async => Directory('${temp.path}/cache'));
  });
}
