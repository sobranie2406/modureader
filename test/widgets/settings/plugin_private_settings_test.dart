import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/main.dart' show navigatorKey;
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/page/settings_page/more_settings_page.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_detail_page.dart';
import 'package:modu_reader/page/settings_page/plugins/plugins_page.dart';
import 'package:modu_reader/page/settings_page/private_library_page.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../service/plugins/plugin_test_utils.dart';

class _Host extends PluginHost {
  _Host({bool private = true})
      : manifest = PluginManifest.parse(manifestJson(
            capabilities: private ? ['library:private'] : [],
            contributes: [],
            settings: [
              {
                'key': 'ordinary_option',
                'type': 'toggle',
                'label': 'Ordinary plugin option',
                'defaultValue': false
              }
            ]));
  final PluginManifest manifest;
  bool installed = true;
  PluginStatus status = PluginStatus.enabled;
  @override
  PluginManifest? manifestFor(String id) => installed ? manifest : null;
  @override
  PluginRecord? byId(String id) => !installed
      ? null
      : PluginRecord(
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
  final privacy = PrivateLibrary.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await Prefs().saveLocaleToPrefs('en');
    privacy.setPluginActive(true);
  });
  tearDown(() => privacy.setPluginActive(false));

  Future<void> pump(WidgetTester tester, Widget page,
      {Size size = const Size(1000, 3000), double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            locale: const Locale('en'),
            navigatorKey: navigatorKey,
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: L10n.localizationsDelegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: page)));
    await tester.pumpAndSettle();
  }

  testWidgets('the main settings list never adds a private-library section',
      (tester) async {
    await privacy.unlock();
    await pump(tester, const SubMoreSettings(), size: const Size(390, 844));
    expect(find.text('Private library'), findsNothing);
    expect(find.byType(PrivateLibrarySettings), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the plugin menu uses its name and puzzle icon without an intermediate page',
      (tester) async {
    await Prefs().saveExperimentalPluginsEnabled(false);
    await pump(tester, const SubMoreSettings(), size: const Size(390, 4000));
    final tile = find.widgetWithText(ListTile, 'Plugins');
    expect(tile, findsOneWidget);
    expect(
        find.descendant(
            of: tile, matching: find.byIcon(Icons.extension_outlined)),
        findsOneWidget);
    expect(find.text('Experimental features'), findsNothing);
    expect(find.byIcon(Icons.science_outlined), findsNothing);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(PluginSettings), findsOneWidget);
    expect(find.text('Manage plugins'), findsNothing);
    expect(find.text('Enable plugins'), findsOneWidget);
  });

  testWidgets('private settings live beside the plugin manifest settings',
      (tester) async {
    final host = _Host();
    addTearDown(host.dispose);
    await pump(
        tester, PluginDetailPage(pluginId: host.manifest.id, host: host));
    final embedded = tester
        .widget<PrivateLibrarySettings>(find.byType(PrivateLibrarySettings));
    expect(embedded.embedded, true);
    expect(find.text('Private book settings'), findsOneWidget);
    expect(find.text('Ordinary plugin option'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(
        find.byKey(const ValueKey('private-library-unlock')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled, missing or inactive private plugins mount no settings',
      (tester) async {
    final host = _Host();
    addTearDown(host.dispose);
    final page = PluginDetailPage(pluginId: host.manifest.id, host: host);
    await pump(tester, page);
    expect(find.byType(PrivateLibrarySettings), findsOneWidget);
    host.status = PluginStatus.disabled;
    host.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(PrivateLibrarySettings), findsNothing);
    host.status = PluginStatus.enabled;
    host.notifyListeners();
    privacy.setPluginActive(false);
    await tester.pumpAndSettle();
    expect(find.byType(PrivateLibrarySettings), findsNothing);
    privacy.setPluginActive(true);
    await tester.pumpAndSettle();
    expect(find.byType(PrivateLibrarySettings), findsOneWidget);
    host.installed = false;
    host.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(PrivateLibrarySettings), findsNothing);
    expect(find.text('This plugin is no longer installed.'), findsOneWidget);
  });

  testWidgets(
      'other plugins keep their own settings without inheriting privacy',
      (tester) async {
    final host = _Host(private: false);
    addTearDown(host.dispose);
    await pump(
        tester, PluginDetailPage(pluginId: host.manifest.id, host: host));
    expect(find.text('Ordinary plugin option'), findsOneWidget);
    expect(find.byType(PrivateLibrarySettings), findsNothing);
  });

  testWidgets(
      'all embedded controls remain reachable on a narrow large-text page',
      (tester) async {
    final host = _Host();
    addTearDown(host.dispose);
    await privacy.unlock();
    await pump(tester, PluginDetailPage(pluginId: host.manifest.id, host: host),
        size: const Size(320, 700), scale: 1.5);
    Future<void> reveal(Finder target) async {
      for (var i = 0; i < 30 && target.hitTestable().evaluate().isEmpty; i++) {
        await tester.drag(find.byKey(const ValueKey('plugin-details-scroll')),
            const Offset(0, -240));
        await tester.pumpAndSettle();
      }
      expect(target.hitTestable(), findsOneWidget);
    }

    await reveal(find.text('Private only'));
    expect(find.byType(PrivateLibrarySettings), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Private only'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(privacy.privateOnly, true);
    await reveal(find.text('Make new imports private'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Make new imports private'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(privacy.autoImport, true);
    await reveal(find.text('Manage private books'));
    expect(find.text('Manage private books'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
