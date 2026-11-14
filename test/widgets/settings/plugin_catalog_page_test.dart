import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/page/settings_page/plugins/plugins_page.dart';
import 'package:modu_reader/service/plugins/plugin_catalog.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_trust.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../service/plugins/plugin_catalog_test.dart'
    show catalogItem, catalogJson;
import '../../service/plugins/plugin_test_utils.dart';

class _CatalogTrust extends PluginTrust {
  String? accepted;
  @override
  Future<void> acceptCatalog(String signedRaw) async {
    accepted = signedRaw;
  }
}

class _Host extends PluginHost {
  _Host(this.inspected) : super(trust: _CatalogTrust());
  final PluginPreview inspected;
  PluginRecord? installed;
  @override
  String get appVersion => '1.3.10';
  @override
  List<PluginRecord> get plugins => installed == null ? [] : [installed!];
  @override
  PluginRecord? byId(String id) => installed?.id == id ? installed : null;
  @override
  Future<PluginPreview> preview(File package,
          {bool allowSameVersion = false}) async =>
      inspected;
  @override
  Future<PluginInstallResult> install(File package,
      {bool allowSameVersion = false, String? expectedSha256}) async {
    expect(expectedSha256, inspected.sha256);
    final manifest = inspected.manifest;
    installed = PluginRecord(
        id: manifest.id,
        version: manifest.version,
        name: manifest.name,
        license: manifest.license,
        installedAt: DateTime(2026),
        sha256: inspected.sha256,
        status: PluginStatus.enabled);
    notifyListeners();
    return PluginInstallResult(record: installed!);
  }
}

class _Catalog extends PluginCatalog {
  List<PluginCatalogEntry> entries = const [];
  bool fail = false;
  int loads = 0, downloads = 0, cleanups = 0;
  late File file;
  Future<List<PluginCatalogEntry>> Function(String source)? onLoad;
  @override
  String get signedCatalog => 'signed-test-catalog';
  @override
  Future<List<PluginCatalogEntry>> load() async {
    loads++;
    if (fail) throw const PluginCatalogFailure('network');
    if (onLoad != null) return onLoad!(sourceId);
    return entries;
  }

  @override
  Future<PluginCatalogDownload> download(PluginCatalogEntry entry) async {
    downloads++;
    return PluginCatalogDownload(file, () async {
      cleanups++;
    });
  }
}

void main() {
  late Directory temporary;
  late PluginHost host;
  late _Catalog catalog;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    await Prefs().saveLocaleToPrefs('en');
    temporary = await Directory.systemTemp.createTemp('plugin-catalog-ui-');
    final files = <String, String>{};
    for (final name in ['manifest.json', 'README.md', 'LICENSE']) {
      files[name] =
          await File('docs/examples/plugins/prompt-pack/$name').readAsString();
    }
    final bytes = buildPluginZip(files);
    host = _Host(PluginPreview(
        manifest: PluginManifest.parse(files['manifest.json']!),
        manifestText: files['manifest.json']!,
        sha256: sha256.convert(bytes).toString(),
        compressedBytes: bytes.length,
        readme: files['README.md'],
        warnings: const [],
        installedVersion: null));
    final file = File('${temporary.path}/sample.moduplugin');
    await file.writeAsBytes(bytes);
    catalog = _Catalog()..file = file;
    catalog.entries = PluginCatalog.parse(catalogJson([
      catalogItem(digest: sha256.convert(bytes).toString()),
    ]));
  });

  tearDown(() async {
    host.dispose();
    await temporary.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        home: Scaffold(body: PluginSettings(host: host, catalog: catalog))));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'catalog loads automatically and install still requires preview confirmation',
      (tester) async {
    await pump(tester);
    expect(catalog.loads, 1);
    expect(host.plugins, isEmpty);
    expect(catalog.downloads, 0);
    await tester.tap(find.byKey(
        const ValueKey('plugin-catalog-install-com.example.prompt-pack')));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    expect(find.byKey(const ValueKey('plugin-install-confirm')), findsOneWidget,
        reason: find
            .byType(Text)
            .evaluate()
            .map((element) => (element.widget as Text).data)
            .join('\n'));
    expect(
        tester
            .widget<DropdownButton<String>>(find.byKey(
                const ValueKey('plugin-catalog-source'),
                skipOffstage: false))
            .onChanged,
        isNull);
    expect(catalog.sourceId, 'github');
    expect(host.plugins, isEmpty);
    await tester.tap(find.byKey(const ValueKey('plugin-install-confirm')));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    expect(host.plugins.single.version, '1.1.0');
    expect(catalog.downloads, 1);
    expect((host.trust as _CatalogTrust).accepted, catalog.signedCatalog);
    expect(catalog.cleanups, 1);
    expect(find.text('Installed'), findsOneWidget);
  });

  testWidgets('cancelling the install preview leaves the plugin uninstalled',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(
        const ValueKey('plugin-catalog-install-com.example.prompt-pack')));
    for (var i = 0; i < 4; i++) {
      await settle(tester);
    }
    await tester.tap(find.byKey(const ValueKey('plugin-install-cancel')));
    await settle(tester);
    expect(host.plugins, isEmpty);
    expect(catalog.cleanups, 1);
  });

  testWidgets(
      'unsupported reviewed versions cannot download and failed loads can retry',
      (tester) async {
    final unsupported = catalogItem(version: '2.0.0')..['hostApi'] = 2;
    catalog.entries = PluginCatalog.parse(catalogJson([unsupported]));
    catalog.fail = true;
    await pump(tester);
    expect(find.text('Could not load plugins'), findsOneWidget);
    catalog.fail = false;
    await tester.tap(find.byKey(const ValueKey('plugin-catalog-retry')));
    await tester.pumpAndSettle();
    expect(catalog.loads, 2);
    expect(find.text('Update Modu to use'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey(
                'plugin-catalog-install-com.example.prompt-pack')))
            .onPressed,
        isNull);
    expect(catalog.downloads, 0);
    expect(find.byKey(const ValueKey('plugin-install')), findsOneWidget);
  });

  testWidgets(
      'switching catalog source clears stale rows and remembers the source',
      (tester) async {
    await pump(tester);
    final oldEntries = catalog.entries;
    final github = Completer<List<PluginCatalogEntry>>();
    final gitee = Completer<List<PluginCatalogEntry>>();
    catalog.onLoad =
        (source) => source == 'github' ? github.future : gitee.future;
    await tester.tap(find.byKey(const ValueKey('plugin-catalog-refresh')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('plugin-catalog-source')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Gitee').last);
    await tester.pump();
    expect(find.text('Example prompt pack'), findsNothing);
    final mirrored = catalogItem()..['name'] = {'en': 'Gitee mirror'};
    gitee.complete(PluginCatalog.parse(catalogJson([mirrored])));
    await tester.pumpAndSettle();
    github.complete(oldEntries);
    await tester.pumpAndSettle();
    expect(find.text('Gitee mirror'), findsOneWidget);
    expect(find.text('Example prompt pack'), findsNothing);
    expect(Prefs().pluginCatalogSource, 'gitee');
    expect(catalog.sourceId, 'gitee');
    final file = catalog.file;
    await tester.pumpWidget(const SizedBox.shrink());
    catalog = _Catalog()..file = file;
    await pump(tester);
    expect(
        tester
            .widget<DropdownButton<String>>(
                find.byKey(const ValueKey('plugin-catalog-source')))
            .value,
        'gitee');
    expect(catalog.sourceId, 'gitee');
  });
}
