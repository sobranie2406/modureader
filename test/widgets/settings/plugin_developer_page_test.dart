import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_detail_page.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_developer_page.dart';
import 'package:modu_reader/page/settings_page/plugins/plugin_install_preview.dart';
import 'package:modu_reader/page/settings_page/plugins/plugins_page.dart';
import 'package:modu_reader/service/plugins/plugin_catalog.dart';
import 'package:modu_reader/service/plugins/plugin_developer_session.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_host_api.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../service/plugins/plugin_test_utils.dart';

class _Host extends PluginHost {
  _Host() : super(development: true);
  var manifest = _manifest();
  static PluginManifest _manifest({bool dictionary = false}) =>
      PluginManifest.parse(manifestJson(
        id: 'com.example.local-test',
        capabilities: [
          'script:run',
          dictionary ? 'dictionary:transform' : 'ui:selection-action'
        ],
        contributes: [
          {
            'kind': 'scriptAction',
            'schema': 1,
            'id': 'clean',
            'name': 'Clean test text',
            'entry': 'main.js',
            'surface': dictionary ? 'dictionary' : 'selection',
          }
        ],
        settings: [
          {
            'key': 'uppercase',
            'type': 'toggle',
            'label': 'Uppercase output',
            'defaultValue': false,
          }
        ],
      ));
  bool installed = false;
  Map<String, dynamic> config = {};
  int saves = 0;
  PluginRecord get record => PluginRecord(
        id: manifest.id,
        version: manifest.version,
        name: manifest.name,
        license: manifest.license,
        installedAt: DateTime(2026),
        sha256: 'b' * 64,
        status: PluginStatus.enabled,
      );
  @override
  List<PluginRecord> get plugins => installed ? [record] : [];
  @override
  PluginRecord? byId(String id) =>
      installed && id == manifest.id ? record : null;
  @override
  PluginManifest? manifestFor(String id) => byId(id) == null ? null : manifest;
  @override
  Future<String?> readmeFor(String id) async => null;
  @override
  Map<String, dynamic> configFor(String id) => Map.of(config);
  @override
  Future<void> saveConfig(String id, Map<String, dynamic> values) async {
    config = Map.of(values);
    saves++;
    notifyListeners();
  }

  void replaceManifest({bool dictionary = false}) {
    manifest = _manifest(dictionary: dictionary);
    notifyListeners();
  }
}

class _Runtime extends PluginScriptRuntime {
  _Runtime(PluginHost host) : super(host: host);
  Completer<Map<String, dynamic>>? pending;
  final inputs = <Map<String, Object?>>[];
  @override
  Future<Map<String, dynamic>> run(
      {required String pluginId,
      required ScriptActionContribution action,
      Map<String, Object?> input = const {},
      PluginHostCall? hostCall,
      PluginHostApi? hostApi,
      bool Function()? isContextValid,
      PluginCancelToken? cancel}) {
    inputs.add(input);
    return pending?.future ??
        Future.value({
          'candidates': ['apple', 'appl']
        });
  }
}

class _Session extends PluginDeveloperSession {
  _Session(this.owner);
  final _Host owner;
  bool active = false;
  final events = <String>[];
  final _entries = <PluginDeveloperLog>[];
  String hash = 'b' * 64;
  bool failClose = false;
  Object? previewError;
  PluginScriptRuntime? testRuntime;
  @override
  bool get enabled => active;
  @override
  bool get busy => false;
  @override
  PluginHost? get host => active ? owner : null;
  @override
  PluginScriptRuntime? get runtime => active ? testRuntime : null;
  @override
  List<PluginDeveloperLog> get logs => List.unmodifiable(_entries);
  @override
  Future<void> setEnabled(bool value) async {
    events.add('enabled:$value');
    if (!value && failClose) throw StateError('Authentication cancelled.');
    active = value;
    if (!value) {
      owner.installed = false;
      owner.config = {};
      _entries.clear();
    }
    notifyListeners();
  }

  @override
  Future<PluginPreview> preview(File file) async {
    events.add('preview');
    if (previewError != null) throw previewError!;
    return PluginPreview(
        manifest: owner.manifest,
        manifestText: '{}',
        sha256: hash,
        compressedBytes: 123,
        readme: null,
        warnings: [],
        installedVersion: owner.installed ? owner.manifest.version : null);
  }

  @override
  Future<PluginInstallResult> install(File file,
      {required String expectedSha256}) async {
    events.add('install:$expectedSha256');
    owner.installed = true;
    _entries.add(PluginDeveloperLog(
        id: owner.manifest.id,
        action: 'clean',
        stage: 'complete',
        code: 'ok',
        elapsedMs: 7));
    notifyListeners();
    return PluginInstallResult(record: owner.record);
  }

  @override
  Future<PluginInstallResult> reload(File file,
      {required String expectedSha256}) async {
    events.add('reload:$expectedSha256');
    notifyListeners();
    return PluginInstallResult(record: owner.record);
  }

  @override
  Future<void> uninstall(String id) async {
    events.add('remove:$id');
    owner.installed = false;
    notifyListeners();
  }

  @override
  void clearLogs() {
    _entries.clear();
    notifyListeners();
  }
}

class _Catalog extends PluginCatalog {
  int loads = 0;
  @override
  Future<List<PluginCatalogEntry>> load() async {
    loads++;
    return [];
  }
}

class _Official extends PluginHost {
  int offCalls = 0;
  @override
  Future<void> setExperimentalEnabled(bool enabled) async {
    if (!enabled) {
      offCalls++;
      throw StateError('Authentication cancelled.');
    }
  }
}

void main() {
  late _Host host;
  late _Session session;
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    await Prefs().saveLocaleToPrefs('en');
    host = _Host();
    session = _Session(host);
  });
  tearDown(() {
    session.dispose();
    host.dispose();
  });

  Future<void> pump(WidgetTester tester, Widget child,
      {Locale locale = const Locale('en')}) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => L10n.delegate.load(locale));
    await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: child));
    await tester.pumpAndSettle();
  }

  Future<void> openImport(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('plugin-developer-import')));
    await tester.pumpAndSettle();
  }

  testWidgets('developer mode stays off until the local exception is confirmed',
      (tester) async {
    final catalog = _Catalog();
    await pump(
        tester,
        Scaffold(
            body: PluginSettings(
                host: host, catalog: catalog, developerSession: session)));
    expect(session.enabled, false);
    expect(find.byKey(const ValueKey('plugin-developer-open')), findsNothing);
    final toggle = find.byKey(const ValueKey('plugin-developer-switch'));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.textContaining('unreviewed, unsigned'), findsOneWidget);
    expect(session.events, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(session.enabled, false);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-plugin-developer')));
    await tester.pumpAndSettle();
    expect(session.events, ['enabled:true']);
    await tester.tap(find.byKey(const ValueKey('plugin-developer-open')));
    await tester.pumpAndSettle();
    expect(find.byType(PluginDeveloperPage), findsOneWidget);
  });

  testWidgets(
      'global off makes no catalog requests and offers no runtime entry',
      (tester) async {
    await Prefs().saveExperimentalPluginsEnabled(false);
    final catalog = _Catalog();
    await pump(
        tester,
        Scaffold(
            body: PluginSettings(
                host: host, catalog: catalog, developerSession: session)));
    expect(catalog.loads, 0);
    expect(find.byKey(const ValueKey('plugin-install')), findsNothing);
    expect(find.byKey(const ValueKey('plugin-developer-switch')), findsNothing);
    expect(find.byKey(const ValueKey('experimental-plugins-switch')),
        findsOneWidget);
  });

  testWidgets(
      'cancelled global deactivation never closes developer state first',
      (tester) async {
    final official = _Official();
    addTearDown(official.dispose);
    session.active = true;
    host.installed = true;
    await pump(
        tester,
        Scaffold(
            body: PluginSettings(
                host: official,
                catalog: _Catalog(),
                developerSession: session)));
    await tester.tap(find.byKey(const ValueKey('experimental-plugins-switch')));
    await tester.pumpAndSettle();
    expect(official.offCalls, 1);
    expect(session.events, isEmpty);
    expect(session.enabled, true);
    expect(host.installed, true);
    expect(Prefs().experimentalPluginsEnabled, true);
  });

  testWidgets(
      'temporary import and reload each require permission and hash confirmation',
      (tester) async {
    session.active = true;
    var picks = 0;
    await pump(
        tester,
        PluginDeveloperPage(
            session: session,
            pickPackage: () async {
              picks++;
              return File('/private/tmp/local-test.moduplugin');
            }));
    await openImport(tester);
    expect(find.byType(PluginInstallPreviewPage), findsOneWidget);
    expect(find.text('Import temporary plugin'), findsOneWidget);
    expect(find.text('Run plugin scripts'), findsOneWidget);
    expect(find.text('b' * 64), findsOneWidget);
    expect(session.events, ['preview']);
    await tester.tap(find.byKey(const ValueKey('plugin-install-cancel')));
    await tester.pumpAndSettle();
    expect(host.installed, false);
    await openImport(tester);
    await tester.tap(find.byKey(const ValueKey('plugin-install-confirm')));
    await tester.pumpAndSettle();
    expect(host.installed, true);
    expect(session.events.last, 'install:${'b' * 64}');
    session.hash = 'c' * 64;
    await tester.tap(
        find.byKey(ValueKey('plugin-developer-reload-${host.manifest.id}')));
    await tester.pumpAndSettle();
    expect(find.text('c' * 64), findsOneWidget);
    expect(session.events.last, 'preview');
    await tester.tap(find.byKey(const ValueKey('plugin-install-confirm')));
    await tester.pumpAndSettle();
    expect(session.events.last, 'reload:${'c' * 64}');
    expect(picks, 2, reason: 'reload reuses only the in-memory source path');
    expect(Prefs().pluginState.plugins, isEmpty);
  });

  testWidgets(
      'unsupported developer contributions get a concise localized error',
      (tester) async {
    await Prefs().saveLocaleToPrefs('zh-CN');
    session.active = true;
    session.previewError = const PluginInstallError(
        PluginErrorCode.capabilityUnavailable,
        'Development mode supports scriptAction and bookAction only; aiSkill and selectionAction are not supported.');
    await pump(
        tester,
        PluginDeveloperPage(
            session: session,
            pickPackage: () async => File('/private/tmp/local-test.zip')),
        locale: const Locale('zh'));
    await openImport(tester);
    expect(
        find.text(
            '本机调试仅支持 scriptAction 和 bookAction，请移除 aiSkill、selectionAction 后重新打包。'),
        findsOneWidget);
    expect(find.textContaining('capabilityUnavailable'), findsNothing);
  });

  testWidgets('other unavailable capabilities retain their own reason',
      (tester) async {
    session.active = true;
    session.previewError = const PluginInstallError(
        PluginErrorCode.capabilityUnavailable,
        'Dictionary networking is not supported.');
    await pump(
        tester,
        PluginDeveloperPage(
            session: session,
            pickPackage: () async => File('/private/tmp/local-test.zip')));
    await openImport(tester);
    expect(
        find.text(
            'capabilityUnavailable: Dictionary networking is not supported.'),
        findsOneWidget);
    expect(find.textContaining('Remove aiSkill'), findsNothing);
  });

  testWidgets(
      'developer detail saves through its host without touching official settings',
      (tester) async {
    session.active = true;
    host.installed = true;
    await Prefs().savePluginConfig(host.manifest.id, {'uppercase': false});
    await pump(
        tester, PluginDetailPage(pluginId: host.manifest.id, host: host));
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 450));
    expect(host.config['uppercase'], true);
    expect(host.saves, 1);
    expect(Prefs().pluginConfig(host.manifest.id)['uppercase'], false);
  });

  testWidgets(
      'same-ID reload drops a pending settings save from the old manifest',
      (tester) async {
    session.active = true;
    host.installed = true;
    await pump(
        tester, PluginDetailPage(pluginId: host.manifest.id, host: host));
    await tester.tap(find.byType(Switch));
    host.replaceManifest();
    await tester.pump(const Duration(milliseconds: 450));
    expect(host.saves, 0);
    expect(host.config, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dictionary testing displays candidates and reload removes old output',
      (tester) async {
    session.active = true;
    host.installed = true;
    host.replaceManifest(dictionary: true);
    final runtime = _Runtime(host);
    session.testRuntime = runtime;
    addTearDown(runtime.dispose);
    await pump(tester, PluginDeveloperPage(session: session));
    final run =
        find.byKey(ValueKey('plugin-developer-run-${host.manifest.id}-clean'));
    await tester.tap(run);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('plugin-developer-selection')), 'apples');
    await tester
        .tap(find.byKey(const ValueKey('plugin-developer-test-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Candidates'), findsOneWidget);
    expect(find.text('apple\nappl'), findsOneWidget);
    expect(runtime.inputs.single, {'selection': 'apples'});
    expect(session.logs, isEmpty);
    host.replaceManifest();
    await tester.pumpAndSettle();
    expect(find.text('Candidates'), findsNothing);
    expect(find.text('apple\nappl'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing a session ignores a late dictionary result',
      (tester) async {
    session.active = true;
    host.installed = true;
    host.replaceManifest(dictionary: true);
    final runtime = _Runtime(host)..pending = Completer<Map<String, dynamic>>();
    session.testRuntime = runtime;
    addTearDown(runtime.dispose);
    await pump(tester, PluginDeveloperPage(session: session));
    await tester.tap(
        find.byKey(ValueKey('plugin-developer-run-${host.manifest.id}-clean')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('plugin-developer-selection')), 'apples');
    await tester
        .tap(find.byKey(const ValueKey('plugin-developer-test-confirm')));
    await tester.pumpAndSettle();
    await session.setEnabled(false);
    runtime.pending!.complete({
      'candidates': ['private-test-output']
    });
    await tester.pumpAndSettle();
    expect(find.text('Candidates'), findsNothing);
    expect(find.text('private-test-output'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'back preserves a session, explicit close clears it, cancelled close preserves it',
      (tester) async {
    session.active = true;
    host.installed = true;
    session.failClose = true;
    await pump(
        tester,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                PluginDeveloperPage(session: session))),
                    child: const Text('Open debug')))));
    await tester.tap(find.text('Open debug'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(session.active, true);
    await tester.tap(find.text('Open debug'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plugin-developer-close')));
    await tester.pumpAndSettle();
    expect(find.text('Debug action failed'), findsOneWidget);
    expect(session.active, true);
    expect(host.installed, true);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    session.failClose = false;
    await tester.tap(find.byKey(const ValueKey('plugin-developer-close')));
    await tester.pumpAndSettle();
    expect(session.active, false);
    expect(host.installed, false);
    expect(find.byType(PluginDeveloperPage), findsNothing);
  });

  testWidgets('logs expose only fixed execution metadata and can be cleared',
      (tester) async {
    session.active = true;
    await session.install(File('/private/tmp/not-used'),
        expectedSha256: 'b' * 64);
    await pump(tester, PluginDeveloperPage(session: session));
    await tester.tap(find.byKey(const ValueKey('plugin-developer-logs')));
    await tester.pumpAndSettle();
    expect(find.text('${host.manifest.id} · clean'), findsOneWidget);
    expect(find.textContaining('complete · ok · 7ms'), findsOneWidget);
    expect(find.textContaining('/private/tmp'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('plugin-developer-clear-logs')));
    await tester.pumpAndSettle();
    expect(session.logs, isEmpty);
  });
}
