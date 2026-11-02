import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/plugin_manifest.dart';
import 'package:anx_reader/models/plugin_state.dart';
import 'package:anx_reader/page/settings_page/plugins/plugins_page.dart';
import 'package:anx_reader/page/settings_page/experimental.dart';
import 'package:anx_reader/service/plugins/plugin_host.dart';
import 'package:anx_reader/service/plugins/plugin_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../service/plugins/plugin_test_utils.dart';

// Directory streams cannot be driven by the widget fake clock. Package/host
// tests cover the real startup sweep; these tests exercise the settings UI.
class _WidgetPluginPaths extends PluginPaths {
  _WidgetPluginPaths({required super.rootPath});

  @override
  Future<void> cleanStale() async {}
}

void main() {
  late Directory temp;
  late PluginHost host;
  File? nextPackage;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    Prefs().userPrompts = [];
    await Prefs().savePluginState(PluginState.empty);
    await Prefs().saveLocaleToPrefs('en');
    temp = await Directory.systemTemp.createTemp('modu_plugin_ui_');
    host = PluginHost(
      trust: const FixturePluginTrust(),
      paths: _WidgetPluginPaths(rootPath: p.join(temp.path, 'plugins')),
      appVersionResolver: () async => '1.3.1+10152',
    );
    await host.initialize();
    nextPackage = await writePluginZip(
        temp,
        samplePackageFiles(
            manifest: manifestJson(contributes: [
          aiSkill(
              id: 'deep-summary',
              name: const {'zh-CN': '深度摘要', 'en': 'Deep summary'}),
          aiSkill(
              id: 'socratic-questions',
              name: const {'zh-CN': '苏格拉底提问', 'en': 'Socratic questions'}),
        ])));
  });

  tearDown(() async {
    host.dispose();
    try {
      if (await temp.exists()) await temp.delete(recursive: true);
    } catch (_) {
      // Windows may still hold the temp directory briefly; leaking it in a
      // failing test run is harmless.
    }
  });

  Future<void> pumpSettings(WidgetTester tester,
      {VoidCallback? onPick,
      bool pickNothing = false,
      PluginHost? hostOverride}) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      home: Scaffold(
        body: PluginSettings(
          host: hostOverride ?? host,
          pickPackage: () async {
            onPick?.call();
            return pickNothing ? null : nextPackage;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> installSample(WidgetTester tester) async {
    await tester.runAsync(() => host.install(nextPackage!));
  }

  /// Lets real file-system futures started by a tap handler finish, which
  /// `pumpAndSettle` cannot observe because they schedule no frames.
  Future<void> settleAsync(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  testWidgets('empty state explains packages and offers install',
      (tester) async {
    await pumpSettings(tester);
    expect(find.text('Install plugin…'), findsOneWidget);
    expect(find.textContaining('No plugins installed yet'), findsOneWidget);
  });

  testWidgets('the install button opens the package picker', (tester) async {
    var picked = false;
    await pumpSettings(tester, onPick: () => picked = true, pickNothing: true);
    await tester.tap(find.byKey(const ValueKey('plugin-install')));
    await tester.pumpAndSettle();
    expect(picked, isTrue);
  });

  testWidgets('experimental switch requires confirmation on every enable',
      (tester) async {
    await tester.runAsync(() => host.setExperimentalEnabled(false));
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ExperimentalSettings(host: host))));
    await tester.pumpAndSettle();
    expect(find.text('Manage plugins'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Enable experimental plugins?'), findsOneWidget);
    expect(Prefs().experimentalPluginsEnabled, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(Prefs().experimentalPluginsEnabled, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('confirm-experimental-plugins')));
    for (var i = 0; i < 4; i++) {
      await settleAsync(tester);
    }
    expect(Prefs().experimentalPluginsEnabled, isTrue);
    expect(find.text('Manage plugins'), findsOneWidget);
    expect(host.isInitialized, isTrue,
        reason: 'enabling must complete before another toggle');
    await tester.tap(find.byType(Switch));
    await settleAsync(tester);
    expect(Prefs().experimentalPluginsEnabled, isFalse);
    expect(find.text('Manage plugins'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('Enable experimental plugins?'), findsOneWidget);
    expect(Prefs().experimentalPluginsEnabled, isFalse);
  });

  testWidgets('an installed plugin renders its name, version and status',
      (tester) async {
    await installSample(tester);
    await pumpSettings(tester);

    expect(find.text('Example prompt pack'), findsOneWidget);
    expect(find.textContaining('v1.0.0 · Enabled'), findsOneWidget);
    expect(Prefs().userPrompts, hasLength(2));
  });

  testWidgets('the switch disables and re-enables contributions',
      (tester) async {
    await installSample(tester);
    await pumpSettings(tester);

    await tester.tap(find.byType(Switch).first);
    await settleAsync(tester);
    expect(Prefs().userPrompts, isEmpty);
    expect(find.textContaining('v1.0.0 · Disabled'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await settleAsync(tester);
    expect(Prefs().userPrompts, hasLength(2));
  });

  testWidgets('uninstall asks for confirmation and cleans up', (tester) async {
    await installSample(tester);
    await pumpSettings(tester);

    await tester
        .tap(find.byKey(const ValueKey('plugin-menu-com.example.prompt-pack')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uninstall'));
    await tester.pumpAndSettle();

    expect(find.text('Uninstall plugin?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Uninstall'));
    await settleAsync(tester);

    expect(find.text('Example prompt pack'), findsNothing);
    expect(Prefs().userPrompts, isEmpty);
    expect(host.plugins, isEmpty);
  });

  testWidgets('details list permissions and contributed prompts',
      (tester) async {
    await installSample(tester);
    await pumpSettings(tester);

    await tester.tap(find.text('Example prompt pack'));
    await settleAsync(tester);

    expect(find.text('Permissions'), findsOneWidget);
    expect(find.text('Add AI prompt templates'), findsOneWidget);
    expect(find.text('Contributions'), findsOneWidget);
    expect(find.text('Deep summary'), findsWidgets);
    expect(find.text('Socratic questions'), findsWidgets);
    expect(find.text('Socratic questions'), findsWidgets);
  });

  testWidgets('details render toolbar actions and persist plugin settings',
      (tester) async {
    nextPackage = (await tester.runAsync(() => writePluginZip(
          temp,
          samplePackageFiles(
              manifest: manifestJson(
            capabilities: ['ai:prompt-pack', 'ui:selection-action'],
            contributes: [
              selectionAction(
                  id: 'explain', name: const {'zh-CN': '解释', 'en': 'Explain'}),
            ],
            settings: [
              {
                'key': 'enabled',
                'type': 'toggle',
                'label': const {'zh-CN': '启用魔法', 'en': 'Enable magic'},
                'defaultValue': true,
              },
              {
                'key': 'tone',
                'type': 'select',
                'label': const {'zh-CN': '语气', 'en': 'Tone'},
                'options': ['brief', 'detailed'],
                'defaultValue': 'brief',
              },
            ],
          )),
        )))!;
    await tester.runAsync(() => host.install(nextPackage!));
    await pumpSettings(tester);

    await tester.tap(find.text('Example prompt pack'));
    await settleAsync(tester);

    expect(find.text('Add selection toolbar actions'), findsOneWidget);
    expect(find.text('Explain'), findsWidgets);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Enable magic'), findsOneWidget);
    expect(find.text('Tone'), findsOneWidget);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Enable magic'));
    await tester.pump(const Duration(milliseconds: 500));
    await settleAsync(tester);

    expect(Prefs().pluginConfig('com.example.prompt-pack')['enabled'], isFalse);
  });

  testWidgets('installing shows the confirmation page and cancel writes nothing',
      (tester) async {
    final fake = _PreviewHost(packageFile: nextPackage!, previewResult: previewFor());
    await pumpSettings(tester, hostOverride: fake);
    await tester.tap(find.byKey(const ValueKey('plugin-install')));
    await tester.pumpAndSettle();

    expect(find.text('Install plugin'), findsOneWidget);
    expect(find.text('Add AI prompt templates'), findsOneWidget);
    expect(find.text('AI prompts'), findsOneWidget);
    expect(find.text('# Example prompt pack'), findsOneWidget,
        reason: 'README preview is shown before installing');

    await tester.tap(find.byKey(const ValueKey('plugin-install-cancel')));
    await tester.pumpAndSettle();
    expect(fake.installs, 0);
    expect(host.plugins, isEmpty);
  });

  testWidgets('confirming the preview installs the package', (tester) async {
    final fake = _PreviewHost(packageFile: nextPackage!, previewResult: previewFor());
    await pumpSettings(tester, hostOverride: fake);
    await tester.tap(find.byKey(const ValueKey('plugin-install')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plugin-install-confirm')));
    await tester.pumpAndSettle();

    expect(fake.installs, 1);
  });

  testWidgets('the details page shows the package README', (tester) async {
    await installSample(tester);
    await pumpSettings(tester);
    await tester.tap(find.text('Example prompt pack'));
    await settleAsync(tester);

    expect(find.text('Package README'), findsOneWidget);
    expect(find.textContaining('Example prompt pack'), findsWidgets);
  });
}

/// A preview/install host that never touches the file system, so widget tests
/// can assert navigation without waiting on real zip unpacking.
class _PreviewHost extends PluginHost {
  _PreviewHost({required this.packageFile, required this.previewResult})
      : super(trust: const FixturePluginTrust());

  final File packageFile;
  final PluginPreview previewResult;
  int installs = 0;

  @override
  Future<PluginPreview> preview(File file,
          {bool allowSameVersion = false}) async =>
      previewResult;

  @override
  Future<PluginInstallResult> install(File file,
      {bool allowSameVersion = false}) async {
    installs++;
    return PluginInstallResult(
        record: PluginRecord(
      id: previewResult.manifest.id,
      version: previewResult.manifest.version,
      name: previewResult.manifest.name,
      license: previewResult.manifest.license,
      installedAt: DateTime(2026),
      sha256: previewResult.sha256,
      status: PluginStatus.enabled,
    ));
  }
}

PluginPreview previewFor() => PluginPreview(
      manifest: PluginManifest.parse(manifestJson()),
      manifestText: manifestJson(),
      sha256: 'a' * 64,
      compressedBytes: 4096,
      readme: '# Example prompt pack',
      warnings: const [],
      installedVersion: null,
    );