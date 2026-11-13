import 'dart:io';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/models/selection_toolbar.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late PluginPaths paths;
  late PluginHost host;

  PluginHost createHost() => PluginHost(
        trust: const FixturePluginTrust(),
        paths: paths,
        appVersionResolver: () async => '1.3.1+10152',
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    Prefs().userPrompts = [];
    await Prefs().savePluginState(PluginState.empty);
    await Prefs().saveSelectionToolbar(const SelectionToolbarConfig());
    temp = await Directory.systemTemp.createTemp('modu_plugin_toolbar_');
    paths = PluginPaths(rootPath: p.join(temp.path, 'plugins'));
    host = createHost();
    await host.initialize();
  });

  tearDown(() async {
    host.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> package({
    String version = '1.0.0',
    List<Map<String, Object?>>? contributes,
    List<String> capabilities = const ['ai:prompt-pack', 'ui:selection-action'],
  }) {
    return writePluginZip(
      temp,
      samplePackageFiles(
          manifest: manifestJson(
        version: version,
        capabilities: capabilities,
        contributes: contributes ??
            [
              selectionAction(id: 'explain'),
            ],
      )),
      name: 'toolbar-$version.moduplugin',
    );
  }

  test('materialises a selectionAction as a custom AI command', () async {
    final result = await host.install(await package());
    expect(result.record.status, PluginStatus.enabled);
    expect(result.record.applied, hasLength(1));
    expect(result.record.applied.single.kind, kSelectionActionContributionKind);
    expect(result.record.applied.single.id,
        'custom-plugin:com.example.prompt-pack:explain');

    final item = Prefs().selectionToolbar.items.singleWhere(
        (item) => item.id == 'custom-plugin:com.example.prompt-pack:explain');
    expect(item.action, 'aiCommand');
    expect(item.isCustom, isTrue);
    expect(item.name, 'explain');
    expect(item.prompt, contains('{selection}'));
    expect(item.icon, 'lightbulb');
    expect(item.scope, SelectionAiScope.context);
    expect(item.skillId, 'selection_toolbar');
    expect(item.enabled, isTrue);
  });

  test('honours selection scope and disabled state', () async {
    await host.install(await package(contributes: [
      selectionAction(id: 'local', scope: 'selection', enabled: false),
    ]));
    final item = Prefs().selectionToolbar.items.singleWhere(
        (item) => item.id == 'custom-plugin:com.example.prompt-pack:local');
    expect(item.scope, SelectionAiScope.selection);
    expect(item.enabled, isFalse);
  });

  test('rejects an unknown icon, missing capability and bad scope', () async {
    final badIcon = await writePluginZip(
        temp,
        samplePackageFiles(
            manifest: manifestJson(
          capabilities: ['ui:selection-action'],
          contributes: [selectionAction(icon: 'no-such-icon')],
        )));
    await expectLater(
      () => host.install(badIcon),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.invalidContribution)),
    );

    final missingCapability = await writePluginZip(
        temp,
        samplePackageFiles(
            manifest: manifestJson(
          capabilities: ['ai:prompt-pack'],
          contributes: [selectionAction()],
        )));
    await expectLater(
      () => host.install(missingCapability),
      throwsA(isA<PluginInstallError>().having((error) => error.code, 'code',
          PluginErrorCode.capabilityUnavailable)),
    );

    expect(
      () => PluginManifest.parse(manifestJson(
        capabilities: ['ui:selection-action'],
        contributes: [selectionAction(scope: 'paragraph')],
      )),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.invalidContribution)),
    );
  });

  test('enforces the 30-character toolbar label limit', () {
    expect(
      () => PluginManifest.parse(manifestJson(
        capabilities: ['ui:selection-action'],
        contributes: [selectionAction(name: 'x' * 31)],
      )),
      throwsA(isA<PluginInstallError>()
          .having((error) => error.code, 'code', PluginErrorCode.nameTooLong)),
    );
  });

  test('rejects installation when the 24 custom toolbar slots are full',
      () async {
    final filler = [
      for (var i = 0; i < 24; i++)
        SelectionToolbarItem('custom-filler-$i', 'aiCommand',
            name: 'Filler $i', prompt: 'Prompt $i', icon: 'lightbulb'),
    ];
    await Prefs().saveSelectionToolbar(SelectionToolbarConfig(
        items: [...const SelectionToolbarConfig().items, ...filler]));
    final file = await package();
    expect(
      () => host.install(file),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.noToolbarSlots)),
    );
    expect(
        Prefs()
            .selectionToolbar
            .items
            .where((item) =>
                item.isCustom &&
                !SelectionToolbarConfig.templateItems
                    .any((preset) => preset.id == item.id))
            .length,
        24);
  });

  test('an upgrade does not count actions the plugin already owns', () async {
    await host.install(await package());
    final filler = [
      for (var i = 0; i < 23; i++)
        SelectionToolbarItem('custom-filler-$i', 'aiCommand',
            name: 'Filler $i', prompt: 'Prompt $i', icon: 'lightbulb'),
    ];
    await Prefs().saveSelectionToolbar(Prefs()
        .selectionToolbar
        .copyWith(items: [...Prefs().selectionToolbar.items, ...filler]));
    expect(
        Prefs()
            .selectionToolbar
            .items
            .where((item) =>
                item.isCustom &&
                !SelectionToolbarConfig.templateItems
                    .any((preset) => preset.id == item.id))
            .length,
        24);

    await host.install(await package(version: '1.1.0'), allowSameVersion: true);
    expect(host.byId('com.example.prompt-pack')!.version, '1.1.0');
    expect(
        Prefs()
            .selectionToolbar
            .items
            .where((item) => item.id.startsWith('custom-plugin:')),
        hasLength(1));
  });

  test('failed upgrade preserves old package and edited action', () async {
    await host.install(await package());
    const id = 'com.example.prompt-pack';
    final oldManifest = await paths.manifestFile(id).readAsString();
    final items = Prefs()
        .selectionToolbar
        .items
        .map((item) => item.id.startsWith('custom-plugin:')
            ? item.copyWith(prompt: 'My edit')
            : item)
        .toList();
    await Prefs()
        .saveSelectionToolbar(Prefs().selectionToolbar.copyWith(items: [
      ...items,
      for (var i = 0; i < 23; i++)
        SelectionToolbarItem('custom-filler-$i', 'aiCommand',
            name: 'Filler $i', prompt: 'Prompt $i', icon: 'lightbulb'),
    ]));
    final before = Prefs().selectionToolbar.encode();
    await expectLater(
        host.install(await package(version: '1.1.0')),
        throwsA(isA<PluginInstallError>()
            .having((e) => e.code, 'code', PluginErrorCode.noToolbarSlots)));
    expect(await paths.manifestFile(id).readAsString(), oldManifest);
    expect(host.byId(id)!.version, '1.0.0');
    expect(Prefs().selectionToolbar.encode(), before);
    await host.initialize();
    expect(host.byId(id)!.status, PluginStatus.enabled);
  });

  test('retired actions release slots before an upgrade', () async {
    await host.install(await package(contributes: [
      for (var i = 0; i < 24; i++) selectionAction(id: 'old-$i'),
    ]));
    await host.install(await package(version: '1.1.0', contributes: [
      for (var i = 0; i < 24; i++) selectionAction(id: 'new-$i'),
    ]));
    expect(
        Prefs()
            .selectionToolbar
            .items
            .where((item) => item.id.contains(':old-')),
        isEmpty);
    expect(
        Prefs()
            .selectionToolbar
            .items
            .where((item) => item.id.contains(':new-')),
        hasLength(24));
  });

  test('disable and uninstall remove untouched toolbar actions', () async {
    await host.install(await package());
    await host.disable('com.example.prompt-pack');
    expect(
        Prefs().selectionToolbar.items.where(
            (item) => item.isCustom && item.id.startsWith('custom-plugin:')),
        isEmpty);

    await host.enable('com.example.prompt-pack');
    expect(
        Prefs().selectionToolbar.items.where(
            (item) => item.isCustom && item.id.startsWith('custom-plugin:')),
        hasLength(1));

    await host.uninstall('com.example.prompt-pack');
    expect(
        Prefs().selectionToolbar.items.where(
            (item) => item.isCustom && item.id.startsWith('custom-plugin:')),
        isEmpty);
  });

  test('uninstall keeps a user-edited action as a normal custom command',
      () async {
    await host.install(await package());
    final config = Prefs().selectionToolbar;
    final item = config.items.singleWhere(
        (item) => item.id == 'custom-plugin:com.example.prompt-pack:explain');
    await Prefs().saveSelectionToolbar(config.copyWith(items: [
      for (final current in config.items)
        current.id == item.id ? current.copyWith(name: '我改过的动作') : current,
    ]));

    await host.uninstall('com.example.prompt-pack');

    final remaining = Prefs().selectionToolbar.items.where((item) =>
        item.id.startsWith('custom-') &&
        !item.id.startsWith('custom-plugin:') &&
        !SelectionToolbarConfig.templateItems
            .any((preset) => preset.id == item.id));
    expect(remaining, hasLength(1));
    expect(remaining.single.name, '我改过的动作');
    expect(remaining.single.prompt, item.prompt);
    expect(remaining.single.id, isNot(item.id));
  });

  test('a restart does not duplicate toolbar actions', () async {
    await host.install(await package());
    final restarted = createHost();
    addTearDown(restarted.dispose);
    await restarted.initialize();

    expect(
        Prefs()
            .selectionToolbar
            .items
            .where((item) => item.id.startsWith('custom-plugin:')),
        hasLength(1));
    expect(restarted.byId('com.example.prompt-pack')!.status,
        PluginStatus.enabled);
  });

  test('refuses to overwrite a toolbar action the plugin does not own',
      () async {
    final id = 'custom-plugin:com.example.prompt-pack:explain';
    await Prefs().saveSelectionToolbar(SelectionToolbarConfig(items: [
      ...const SelectionToolbarConfig().items,
      SelectionToolbarItem(id, 'aiCommand',
          name: 'User action', prompt: 'User prompt', icon: 'lightbulb'),
    ]));
    await expectLater(
      () async => host.install(await package()),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.toolbarConflict)),
    );
    expect(host.plugins, isEmpty);
  });

  test('hash guard covers name and icon edits, not only prompt text', () async {
    await host.install(await package());
    final config = Prefs().selectionToolbar;
    final item = config.items.singleWhere(
        (item) => item.id == 'custom-plugin:com.example.prompt-pack:explain');
    await Prefs().saveSelectionToolbar(config.copyWith(items: [
      for (final current in config.items)
        current.id == item.id ? current.copyWith(icon: 'heart') : current,
    ]));

    await host.uninstall('com.example.prompt-pack');

    final kept = Prefs()
        .selectionToolbar
        .items
        .singleWhere((item) => item.icon == 'heart');
    expect(kept.id, startsWith('custom-'));
    expect(kept.id, isNot(item.id));
  });
}
