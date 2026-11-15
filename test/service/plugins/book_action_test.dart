import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/service/plugins/handlers/book_action_handler.dart';
import 'package:modu_reader/service/plugins/handlers/script_action_handler.dart';
import 'package:modu_reader/service/plugins/plugin_contribution_handler.dart';
import 'package:modu_reader/service/plugins/plugin_contributions.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

Map<String, Object?> _action(String id) => {
      'kind': 'bookAction',
      'schema': 1,
      'id': id,
      'name': id,
      'command': 'privateLibrary.hide'
    };

PluginManifest _manifest(String id, List<String> actions,
        {bool script = false}) =>
    PluginManifest.parse(manifestJson(id: id, capabilities: [
      'ui:book-action',
      'library:private',
      if (script) 'script:run'
    ], contributes: [
      for (final action in actions) _action(action),
      if (script)
        {
          'kind': 'scriptAction',
          'schema': 1,
          'id': 'open',
          'name': 'Open',
          'entry': 'main.js',
          'surface': 'library'
        }
    ]));

PluginManifest _withCapabilities(
        PluginManifest original, Set<String> capabilities) =>
    PluginManifest(
        schemaVersion: original.schemaVersion,
        id: original.id,
        version: original.version,
        name: original.name,
        description: original.description,
        author: original.author,
        license: original.license,
        minAppVersion: original.minAppVersion,
        capabilities: capabilities,
        contributions: original.contributions,
        settings: original.settings,
        hostApi: original.hostApi,
        warnings: original.warnings);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runtime-only book entries register, notify and remove per plugin',
      () async {
    final registry = PluginBookActionRegistry();
    addTearDown(registry.dispose);
    var notifications = 0;
    registry.addListener(() => notifications++);
    final handler = BookActionContributionHandler(registry: registry);
    final first = _manifest('com.example.first', ['hide', 'other']);
    final second = _manifest('com.example.second', ['hide']);
    final applied = await handler.apply(first, first.contributions);
    await handler.apply(second, second.contributions);
    expect(handler.runtimeOnly, true);
    expect(registry.all, hasLength(3));
    expect(registry.byId('book:${first.id}:hide')?.pluginId, first.id);
    expect(applied.first.contentSha256, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(handler.isApplied(applied.first), true);
    expect(() => registry.all.clear(), throwsUnsupportedError);
    await handler.remove(applied);
    expect(registry.forPlugin(first.id), isEmpty);
    expect(registry.forPlugin(second.id), hasLength(1));
    expect(handler.isApplied(applied.first), false);
    expect(notifications, 3);
    registry.removeIds(['missing']);
    expect(notifications, 3);
  });

  test('reapplying a plugin replaces retired entries without duplication',
      () async {
    final registry = PluginBookActionRegistry();
    addTearDown(registry.dispose);
    final handler = BookActionContributionHandler(registry: registry);
    final old = _manifest('com.example.first', ['old', 'kept']);
    final update = _manifest(old.id, ['kept', 'new']);
    await handler.apply(old, old.contributions);
    await handler.apply(update, update.contributions);
    await handler.apply(update, update.contributions);
    expect(registry.all.map((entry) => entry.action.id), ['kept', 'new']);
    expect(registry.byId('book:${old.id}:old'), isNull);
    await handler.apply(_withCapabilities(update, {}), []);
    expect(registry.all, isEmpty);
  });

  test(
      'handler independently validates capabilities and bounded native commands',
      () {
    final registry = PluginBookActionRegistry();
    addTearDown(registry.dispose);
    final handler = BookActionContributionHandler(registry: registry);
    final manifest = _manifest('com.example.first', ['hide']);
    for (final capabilities in <Set<String>>[
      {},
      {kBookActionCapability},
      {kLibraryPrivateCapability}
    ]) {
      expect(
          () => handler.validate(_withCapabilities(manifest, capabilities),
              manifest.contributions),
          throwsA(isA<PluginInstallError>()));
    }
    for (final command in ['privateLibrary.lock', 'http.get']) {
      final invalid = BookActionContribution(
          kind: 'bookAction',
          schema: 1,
          id: 'hide',
          index: 0,
          raw: const {},
          name: const PluginText({'en': 'Hide'}),
          command: command);
      expect(() => handler.validate(manifest, [invalid]),
          throwsA(isA<PluginInstallError>()));
    }
    expect(
        () => handler.validate(manifest, [
              const UnknownContribution(
                  kind: 'bookAction', schema: 1, id: 'hide', index: 0, raw: {})
            ]),
        throwsA(isA<PluginInstallError>()));
    expect(
        () => handler.validate(
            manifest,
            List.filled(PluginLimits.maxBookActionsPerPlugin + 1,
                manifest.contributions.single)),
        throwsA(isA<PluginInstallError>()));
    expect(registry.all, isEmpty);
  });

  test('standard contributions register book and script entries independently',
      () async {
    final manifest = _manifest('com.example.mixed', ['hide'], script: true);
    final standard = PluginContributions.standard();
    final applied = await standard.apply(manifest);
    addTearDown(() => standard.remove(applied));
    expect(
        PluginBookActionRegistry.instance.forPlugin(manifest.id), hasLength(1));
    expect(PluginScriptActionRegistry.instance.forPlugin(manifest.id),
        hasLength(1));
    expect(
        applied.map((entry) => entry.kind),
        containsAll(
            [kBookActionContributionKind, kScriptActionContributionKind]));
    await standard.remove(applied);
    expect(PluginBookActionRegistry.instance.forPlugin(manifest.id), isEmpty);
    expect(PluginScriptActionRegistry.instance.forPlugin(manifest.id), isEmpty);
  });

  test('host install, restart, disable, enable and uninstall own book entries',
      () async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    final directory =
        await Directory.systemTemp.createTemp('plugin-book-action-');
    addTearDown(() => directory.delete(recursive: true));
    final registry = PluginBookActionRegistry();
    addTearDown(registry.dispose);
    final scripts = PluginScriptActionRegistry();
    addTearDown(scripts.dispose);
    PluginHost newHost() => PluginHost(
        paths: PluginPaths(rootPath: '${directory.path}/plugins'),
        trust: FixturePluginTrust(),
        appVersionResolver: () async => '1.3.10',
        contributions: PluginContributions(PluginContributionRegistry([
          BookActionContributionHandler(registry: registry),
          ScriptActionContributionHandler(registry: scripts)
        ])));
    var host = newHost();
    addTearDown(() => host.dispose());
    await host.initialize();
    const id = 'com.example.declarative-private';
    final package = await writePluginZip(
        directory,
        samplePackageFiles(
            manifest: manifestJson(
                id: id,
                capabilities: ['ui:book-action', 'library:private'],
                contributes: [_action('hide')])));
    await host.install(package);
    expect(registry.forPlugin(id), hasLength(1));
    expect(scripts.forPlugin(id), isEmpty);
    host.dispose();
    registry.replacePlugin(id, []);
    host = newHost();
    await host.initialize();
    expect(host.byId(id)!.status, PluginStatus.enabled);
    expect(registry.forPlugin(id), hasLength(1));
    await host.disable(id);
    expect(registry.forPlugin(id), isEmpty);
    await host.enable(id);
    expect(registry.forPlugin(id), hasLength(1));
    await host.uninstall(id);
    expect(registry.forPlugin(id), isEmpty);
    expect(host.byId(id), isNull);
  });
}
