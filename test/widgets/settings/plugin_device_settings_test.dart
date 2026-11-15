import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_detail_page.dart';
import 'package:modu_reader/page/settings_page/private_library_page.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../service/plugins/plugin_test_utils.dart';

class _Host extends PluginHost {
  final manifest = PluginManifest.parse(manifestJson(capabilities: [
    'library:private',
    'library:private-control',
    'settings:device'
  ], contributes: [], settings: [
    {
      'key': 'auto_import',
      'type': 'toggle',
      'label': 'Automatic import',
      'storage': 'device',
      'binding': 'privateLibrary.autoImport',
      'defaultValue': false
    }
  ]));
  bool enabled = true;
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
      status: enabled ? PluginStatus.enabled : PluginStatus.disabled);
  @override
  Future<String?> readmeFor(String id) async => null;
}

void main() {
  final library = PrivateLibrary.instance;
  late _Host host;
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    await Prefs().saveLocaleToPrefs('en');
    library.setPluginActive(true);
    host = _Host();
  });
  tearDown(() {
    host.dispose();
    library.setPluginActive(false);
  });
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: PluginDetailPage(pluginId: host.manifest.id, host: host)));
    await tester.pumpAndSettle();
  }

  final toggle = find.byKey(const ValueKey('plugin-binding-auto_import'));

  testWidgets(
      'native binding asks for unlock before changing and saves only native policy',
      (tester) async {
    await pump(tester);
    expect(
        tester
            .widget<PrivateLibrarySettings>(find.byType(PrivateLibrarySettings))
            .showPolicyOptions,
        false);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlertDialog, 'Unlock private library'),
        findsOneWidget);
    expect(library.autoImport, false);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(library.autoImport, true);
    expect(Prefs().pluginConfig(host.manifest.id), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled unlock leaves values unchanged', (tester) async {
    await pump(tester);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<SwitchListTile>(toggle).value, false);
    expect(library.autoImport, false);
  });

  testWidgets('lock invalidates a pending native option edit', (tester) async {
    await library.unlock();
    await pump(tester);
    await tester.tap(toggle);
    await tester.pump();
    library.lock();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(library.storedPolicyOptions['autoImport'], false);
    expect(tester.widget<SwitchListTile>(toggle).value, false);
  });

  testWidgets(
      'disabled owner cannot change a native option or retain its unlock dialog',
      (tester) async {
    await pump(tester);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    host.enabled = false;
    host.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Unlock private library'), findsNothing);
    expect(tester.widget<SwitchListTile>(toggle).onChanged, null);
    expect(library.autoImport, false);
  });
}
