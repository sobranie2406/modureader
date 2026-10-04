import 'dart:convert';
import 'dart:ui';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/service/config_transfer/config_qr_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  const own = SelectionToolbarItem('custom-own', 'aiCommand',
      name: '改写', icon: 'note', prompt: '请改写 {selection}');

  test('all seven templates start disabled; native actions remain enabled', () {
    const config = SelectionToolbarConfig();
    config.validate();
    expect(config.items.where((i) => i.isCustom), hasLength(7));
    expect(
        config.items.where((i) => i.isCustom).every((i) => !i.enabled), true);
    expect(config.availableItems().map((i) => i.id),
        SelectionToolbarConfig.defaultItems.map((i) => i.id));
    expect(config.availableItems(footnote: true).any((i) => i.action == 'note'),
        false);
    expect(config.availableItems(aiEnabled: false).any((i) => i.isAi), false);
    expect(config.copyWith(enabled: false).availableItems(), isEmpty);
  });

  test('toggle, order, label, icon, prompt and colours survive persistence',
      () async {
    final config = const SelectionToolbarConfig().copyWith(
        visibleCount: 3,
        items: [
          own,
          ...SelectionToolbarConfig.initialItems.reversed.map((i) =>
              i.id == 'copy'
                  ? i.copyWith(enabled: false, name: '复制原文', icon: 'star')
                  : i)
        ],
        annotations:
            SelectionToolbarConfig.defaultAnnotations.reversed.toList(),
        colors: ['00897B', 'FF8C00']);
    await Prefs().saveSelectionToolbar(config);
    await Prefs().initPrefs();
    expect(Prefs().selectionToolbar.encode(), config.encode());
    expect(config.availableItems().first.id, own.id);
    expect(config.availableItems().any((i) => i.id == 'copy'), false);
  });

  test('placeholder expansion quotes selected text once without recursion', () {
    const command = SelectionToolbarItem('custom-test', 'aiCommand',
        name: 'Test', prompt: '解释 {selection} / {{selection}}');
    const source = '"quoted"\n{selection} and {{selection}}';
    expect(command.promptForSelection(source),
        '解释 ${jsonEncode(source)} / ${jsonEncode(source)}');
  });

  test('all AI commands default to selection only and no network', () {
    for (final item
        in SelectionToolbarConfig.initialItems.where((i) => i.isAi)) {
      expect(item.scope, SelectionAiScope.selection);
      expect(item.webSearch, false);
      expect(item.toJson().containsKey('scope'), false);
      expect(item.toJson().containsKey('webSearch'), false);
    }
  });

  test('custom AI context and web choices survive roundtrip', () async {
    final item = own.copyWith(scope: SelectionAiScope.context, webSearch: true);
    final config = SelectionToolbarConfig(
        items: [item, ...SelectionToolbarConfig.initialItems]);
    await Prefs().saveSelectionToolbar(config);
    await Prefs().initPrefs();
    expect(
        Prefs().selectionToolbar.items.first.scope, SelectionAiScope.context);
    expect(Prefs().selectionToolbar.items.first.webSearch, true);
    expect(
        SelectionToolbarItem.fromJson({
          'id': own.id,
          'action': own.action,
          'name': own.name,
          'prompt': own.prompt
        }).scope,
        SelectionAiScope.selection);
  });

  test('invalid scopes and network flags are rejected', () {
    for (final raw in [
      {...own.toJson(), 'scope': 'chapter'},
      {...own.toJson(), 'scope': false},
      {...own.toJson(), 'webSearch': 'true'},
    ]) {
      expect(() => SelectionToolbarItem.fromJson(raw), throwsFormatException);
    }
    final config = const SelectionToolbarConfig().copyWith(items: [
      SelectionToolbarConfig.initialItems.first.copyWith(webSearch: true),
      ...SelectionToolbarConfig.initialItems.skip(1),
    ]);
    expect(config.validate, throwsFormatException);
  });

  test('bundled template text is omitted; only changed fields travel', () {
    const defaults = SelectionToolbarConfig();
    final raw = jsonDecode(defaults.encode()) as Map;
    final template = SelectionToolbarConfig.templateItems.first;
    final entry =
        (raw['items'] as List).firstWhere((i) => i['id'] == template.id) as Map;
    expect(entry, {'id': template.id, 'action': template.action});
    expect(
        SelectionToolbarConfig.decode(defaults.encode())
            .items
            .firstWhere((i) => i.id == template.id)
            .prompt,
        template.prompt);
    final edited = defaults.copyWith(items: [
      for (final item in defaults.items)
        item.id == template.id
            ? item.copyWith(enabled: true, prompt: '解释 {selection} 的意思')
            : item,
    ]);
    final changed = (jsonDecode(edited.encode())['items'] as List)
        .firstWhere((i) => i['id'] == template.id) as Map;
    expect(changed, {
      'id': template.id,
      'action': template.action,
      'enabled': true,
      'prompt': '解释 {selection} 的意思',
    });
  });

  test('restore resets presets disabled and keeps user commands', () {
    final config =
        const SelectionToolbarConfig().copyWith(enabled: false, items: [
      own,
      ...SelectionToolbarConfig.initialItems
          .map((i) => i.copyWith(enabled: true, name: '修改名称'))
    ], colors: [
      'FFFFFF'
    ]);
    final restored = config.restoreDefaults();
    restored.validate();
    expect(restored.enabled, true);
    expect(restored.items.last.id, own.id);
    expect(
        restored.items
            .where((i) => i.id.startsWith('custom-preset-'))
            .every((i) => !i.enabled),
        true);
    expect(restored.items.first.name, '');
  });

  test('restoring deleted presets never exceeds the user command limit', () {
    final config = SelectionToolbarConfig(items: [
      ...SelectionToolbarConfig.defaultItems,
      for (var i = 0; i < 24; i++)
        SelectionToolbarItem('custom-$i', 'aiCommand',
            name: '命令$i', prompt: '解释'),
    ]);
    config.restoreDefaults().validate();
    expect(config.restoreDefaults().items, hasLength(39));
  });

  test('classical translation preset quotes selection and omits bundled text',
      () {
    final preset = SelectionToolbarConfig.templateItems
        .singleWhere((item) => item.id == 'custom-preset-classical-chinese');
    expect(preset.localizedName(const Locale('zh', 'CN')), '文言文翻译');
    expect(preset.promptForSelection('学而时习之'), contains('"学而时习之"'));
    expect(
        preset.localizedPrompt(const Locale('en')), contains('modern Chinese'));
    expect(preset.toJson(), {'id': preset.id, 'action': 'aiCommand'});
    final edited = preset.copyWith(
        enabled: true,
        prompt: '逐句翻译 {selection}',
        scope: SelectionAiScope.context,
        webSearch: true);
    expect(SelectionToolbarItem.fromJson(edited.toJson()).toJson(),
        edited.toJson());
  });

  test('older settings gain only new preset and preserve edits and deletions',
      () {
    const id = 'custom-preset-classical-chinese';
    final old = const SelectionToolbarConfig().copyWith(items: [
      own,
      ...SelectionToolbarConfig.initialItems.reversed
          .where((item) => item.id != id && item.id != 'custom-preset-summary')
          .map((item) =>
              item.id == 'copy' ? item.copyWith(enabled: false) : item),
    ]);
    final raw = jsonDecode(old.encode()) as Map<String, dynamic>;
    raw.remove('templateRevision');
    final migrated = SelectionToolbarConfig.decode(jsonEncode(raw));
    expect(migrated.items.take(old.items.length).map((item) => item.toJson()),
        old.items.map((item) => item.toJson()));
    expect(migrated.items.last.id, id);
    expect(migrated.items.last.enabled, false);
    expect(migrated.items.any((item) => item.id == 'custom-preset-summary'),
        false);
    expect(SelectionToolbarConfig.decode(migrated.encode()).encode(),
        migrated.encode());
    final deleted = migrated.copyWith(
        items: migrated.items.where((item) => item.id != id).toList());
    expect(
        SelectionToolbarConfig.decode(deleted.encode())
            .items
            .any((item) => item.id == id),
        false);
  });

  test('global file, modu link and QR restore all toolbar parameters',
      () async {
    final config = const SelectionToolbarConfig().copyWith(items: [
      own.copyWith(scope: SelectionAiScope.context, webSearch: true),
      ...SelectionToolbarConfig.initialItems
    ], colors: [
      '00897B'
    ]);
    await Prefs().saveSelectionToolbar(config);
    final file = await GlobalSettingsTransfer.export(Prefs());
    final data = await GlobalSettingsTransfer.decode(file);
    expect(data['selectionToolbar']['value'], config.encode());
    final link = GlobalSettingsTransfer.link(file);
    expect(await GlobalSettingsTransfer.decode(link), data);
    final directory = await Directory.systemTemp.createTemp('modu-toolbar-qr-');
    try {
      final bytes = await ConfigQrBridge.generate(link);
      final image = File('${directory.path}/qr.png');
      await image.writeAsBytes(bytes!);
      final scanned = await ConfigQrBridge.decodeImage(image.path);
      expect(scanned, link);
    } finally {
      await directory.delete(recursive: true);
    }
    await Prefs().saveSelectionToolbar(const SelectionToolbarConfig());
    await GlobalSettingsTransfer.apply(Prefs(), data);
    expect(Prefs().selectionToolbar.encode(), config.encode());
  });

  test('invalid toolbar backup fails before any setting is written', () async {
    final data = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs()));
    data['selectionToolbar'] = {'type': 'string', 'value': '{"version":1}'};
    data['ttsRate'] = {'type': 'double', 'value': 1.3};
    final before = Prefs().prefs.getKeys().toSet();
    await expectLater(
        GlobalSettingsTransfer.apply(Prefs(), data), throwsFormatException);
    expect(Prefs().prefs.getKeys(), before);
  });

  for (final bad in <SelectionToolbarConfig>[
    const SelectionToolbarConfig(visibleCount: 0),
    const SelectionToolbarConfig(visibleCount: 9),
    const SelectionToolbarConfig(colors: []),
    const SelectionToolbarConfig(colors: ['not a colour']),
    const SelectionToolbarConfig(colors: ['FFFFFF', 'FFFFFF']),
    const SelectionToolbarConfig(items: []),
    const SelectionToolbarConfig(annotations: []),
    SelectionToolbarConfig(items: [
      ...SelectionToolbarConfig.initialItems,
      own.copyWith(prompt: '')
    ]),
    SelectionToolbarConfig(items: [
      ...SelectionToolbarConfig.initialItems,
      own.copyWith(icon: 'arbitrary-font-code')
    ]),
    SelectionToolbarConfig(items: [
      ...SelectionToolbarConfig.initialItems,
      own.copyWith(skillId: 'unrestricted-agent')
    ]),
  ].indexed) {
    test('reject malformed configuration ${bad.$1}', () {
      expect(bad.$2.validate, throwsFormatException);
    });
  }
}
