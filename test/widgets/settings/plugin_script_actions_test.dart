import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_detail_page.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_install_preview.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../service/plugins/plugin_test_utils.dart';

class _Host extends PluginHost {
  _Host(this.manifest, this.status);
  final PluginManifest manifest;
  PluginStatus status;

  void setStatus(PluginStatus value) {
    status = value;
    notifyListeners();
  }

  @override
  PluginManifest? manifestFor(String id) => manifest;

  @override
  PluginRecord? byId(String id) => PluginRecord(
      id: manifest.id,
      version: manifest.version,
      name: manifest.name,
      license: manifest.license,
      installedAt: DateTime(2026),
      sha256: 'a' * 64,
      status: status);

  @override
  Future<String?> readmeFor(String id) async => null;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await Prefs().saveLocaleToPrefs('en');
  });

  PluginManifest manifest() => PluginManifest.parse(manifestJson(capabilities: [
        'script:run',
        'library:private',
        'note:write',
        'library:read',
        'ui:selection-action'
      ], contributes: [
        {
          'kind': 'scriptAction',
          'schema': 1,
          'id': 'open',
          'name': 'Open private books',
          'entry': 'main.js',
          'surface': 'library'
        },
        {
          'kind': 'scriptAction',
          'schema': 1,
          'id': 'clean',
          'name': 'Clean selected text',
          'entry': 'main.js',
          'surface': 'selection'
        },
      ]));

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(MaterialApp(locale: const Locale('en'), home: child));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'library actions run only while enabled and selection actions stay in reader',
      (tester) async {
    final host = _Host(manifest(), PluginStatus.enabled);
    addTearDown(host.dispose);
    final calls = <String>[];
    await pump(
        tester,
        PluginDetailPage(
            pluginId: host.manifest.id,
            host: host,
            onRunScriptAction: (pluginId, action) async =>
                calls.add('$pluginId:${action.id}')));
    final open = find.byKey(const ValueKey('plugin-script-action-open'));
    final clean = find.byKey(const ValueKey('plugin-script-action-clean'));
    expect(tester.widget<ListTile>(open).onTap, isNotNull);
    expect(tester.widget<ListTile>(clean).onTap, isNull);
    await tester.tap(open);
    expect(calls, ['${host.manifest.id}:open']);
    host.setStatus(PluginStatus.disabled);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(open).onTap, isNull);
    await tester.tap(open);
    expect(calls, hasLength(1));
  });

  testWidgets(
      'preview and details show all granted capabilities with script scope',
      (tester) async {
    final plugin = manifest();
    await pump(
        tester,
        PluginInstallPreviewPage(
            preview: PluginPreview(
                manifest: plugin,
                manifestText: '{}',
                sha256: 'a' * 64,
                compressedBytes: 100,
                readme: null,
                warnings: const [],
                installedVersion: null)));
    for (final text in [
      'Run plugin scripts',
      'Manage private books',
      'Save notes',
      'Read granted books'
    ]) {
      expect(find.text(text), findsOneWidget);
    }
    expect(find.text('Selected text only'), findsOneWidget);
    expect(find.text('Plugin action'), findsOneWidget);
    expect(find.text('This package adds nothing.'), findsNothing);
  });
}
