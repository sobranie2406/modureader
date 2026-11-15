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
  _Host(this.manifest);
  final PluginManifest manifest;
  PluginStatus status = PluginStatus.enabled;
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
          status: status,
          applied: [
            AppliedContribution(
                kind: kBookActionContributionKind,
                id: 'book:${manifest.id}:hide',
                contentSha256: 'b' * 64)
          ]);
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
        'ui:book-action',
        'library:private'
      ], contributes: [
        {
          'kind': 'bookAction',
          'schema': 1,
          'id': 'hide',
          'name': 'Hide in private library',
          'command': 'privateLibrary.hide'
        }
      ]));

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(MaterialApp(locale: const Locale('en'), home: page));
    await tester.pumpAndSettle();
  }

  testWidgets('declarative menu preview lists its action and both permissions',
      (tester) async {
    await pump(
        tester,
        PluginInstallPreviewPage(
            preview: PluginPreview(
                manifest: manifest(),
                manifestText: '{}',
                sha256: 'a' * 64,
                compressedBytes: 100,
                readme: null,
                warnings: const [],
                installedVersion: null)));
    expect(find.text('Hide in private library'), findsOneWidget);
    expect(find.text('Use from the book actions menu'), findsOneWidget);
    expect(find.text('Add book menu actions'), findsOneWidget);
    expect(find.text('Manage private books'), findsOneWidget);
    expect(find.text('Run plugin scripts'), findsNothing);
    expect(find.text('This package adds nothing.'), findsNothing);
  });

  testWidgets('details explain the book entry without executing it unbound',
      (tester) async {
    final host = _Host(manifest());
    addTearDown(host.dispose);
    var runs = 0;
    await pump(
        tester,
        PluginDetailPage(
            pluginId: host.manifest.id,
            host: host,
            onRunScriptAction: (_, __) async {
              runs++;
            }));
    final entry = find.byKey(const ValueKey('plugin-book-action-hide'));
    expect(find.text('Hide in private library'), findsOneWidget);
    expect(find.text('Use from the book actions menu'), findsOneWidget);
    expect(tester.widget<ListTile>(entry).enabled, true);
    expect(tester.widget<ListTile>(entry).onTap, isNull);
    expect(tester.widget<ListTile>(entry).trailing, isNull);
    host.status = PluginStatus.disabled;
    host.notifyListeners();
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(entry).enabled, false);
    expect(tester.widget<ListTile>(entry).onTap, isNull);
    expect(runs, 0);
  });
}
