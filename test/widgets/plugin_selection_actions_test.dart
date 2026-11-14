import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/selection_toolbar.dart';
import 'package:modu_reader/service/plugins/handlers/script_action_handler.dart';
import 'package:modu_reader/widgets/context_menu/excerpt_menu.dart';
import 'package:modu_reader/widgets/context_menu/selection_action_toolbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../service/plugins/plugin_test_utils.dart';

void main() {
  testWidgets(
      'script selection actions appear at runtime without rewriting AI or saved toolbar',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    const defaults = SelectionToolbarConfig();
    final config = defaults.copyWith(items: [
      for (final item in defaults.items)
        item.copyWith(enabled: item.id == 'copy'),
      const SelectionToolbarItem('custom-existing', 'aiCommand',
          name: 'Existing AI', prompt: 'Explain {selection}'),
    ]);
    await Prefs().saveSelectionToolbar(config);
    final registry = PluginScriptActionRegistry.instance;
    const pluginId = 'com.example.selection-ui';
    addTearDown(() => registry
        .removeIds(registry.forPlugin(pluginId).map((item) => item.id)));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: Scaffold(
          body: Column(children: [
        ExcerptMenu(
          annoCfi: 'epubcfi(/6/4!/4/2,/1:0,/1:4)',
          annoContent: 'Selected text',
          contextText: 'Private context',
          bookId: 7,
          footnote: false,
          allowAnnotations: false,
          decoration: const BoxDecoration(),
          onClose: () {},
          toggleTranslationMenu: () {},
          toggleReaderNoteMenu: ({show}) {},
          openReaderNoteMenu: (_, {allowPopup = true}) async {},
          onNoteCreated: (_) {},
          axis: Axis.horizontal,
          reverse: false,
        ),
      ])),
    ));
    await tester.pumpAndSettle();
    List<SelectionToolbarItem> items() => tester
        .widget<SelectionActionToolbar>(find.byType(SelectionActionToolbar))
        .items;
    expect(items().where((item) => item.action == 'pluginScript'), isEmpty);
    final originalIds = items().map((item) => item.id).toList();
    final manifest = PluginManifest.parse(manifestJson(
      id: pluginId,
      capabilities: ['script:run', 'ui:selection-action'],
      contributes: [
        {
          'kind': 'scriptAction',
          'schema': 1,
          'id': 'clean',
          'name': 'Clean',
          'entry': 'main.js'
        },
        {
          'kind': 'scriptAction',
          'schema': 1,
          'id': 'library',
          'name': 'Library',
          'entry': 'main.js',
          'surface': 'library'
        },
      ],
    ));
    registry.replacePlugin(
        pluginId, manifest.contributions.cast<ScriptActionContribution>());
    await tester.pumpAndSettle();
    expect(items().where((item) => item.action == 'pluginScript').single.id,
        'script:$pluginId:clean');
    expect(items().singleWhere((item) => item.id == 'custom-existing').prompt,
        'Explain {selection}');
    expect(Prefs().selectionToolbar.encode(), config.encode());
    registry.removeIds(registry.forPlugin(pluginId).map((item) => item.id));
    await tester.pumpAndSettle();
    expect(items().where((item) => item.action == 'pluginScript'), isEmpty);
    expect(items().map((item) => item.id), originalIds);
    expect(tester.takeException(), isNull);
  });
}
