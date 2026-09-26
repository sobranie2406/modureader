import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/global_settings.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/service/config_transfer/config_transfer_codec.dart';
import 'package:anx_reader/service/config_transfer/tts_config_transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The app's Sync notifier is a singleton. Keep its owning container alive
  // across page mounts, as the real app does; these tests cancel every import.
  late ProviderContainer container;
  setUpAll(() => container = ProviderContainer());
  tearDownAll(() => container.dispose());
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ttsRate': 1.2,
      'aiTemperature': 0.5,
      'autoSync': true,
      'customCSS': 'p { color: red; }',
      'remoteLibraryConnection': '{"url":"https://example.test/books/"}',
    });
    await Prefs().initPrefs();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: Locale('zh'),
        home: Scaffold(body: GlobalSettingsPage()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> preview(WidgetTester tester, String link) async {
    await tester.ensureVisible(find.text('粘贴 modu 链接恢复'));
    await tester.tap(find.text('粘贴 modu 链接恢复'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField), link);
    await tester.tap(find.text('继续'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  for (final entry in {
    'tts': '朗读配置',
    'ai': 'AI 供应商与对话',
    'webdav': '同步 WebDAV',
    'remote-library-webdav': '远程书库 WebDAV',
  }.entries) {
    testWidgets(
        'single ${entry.key} link names its scope even when all is selected',
        (tester) async {
      final file = await GlobalSettingsTransfer.export(Prefs(),
          scope: entry.key, includeSecrets: true);
      await open(tester);
      await preview(tester, GlobalSettingsTransfer.link(file));
      expect(find.text('恢复${entry.value}？'), findsOneWidget);
      expect(find.text('恢复全局设置？'), findsNothing);
      expect(find.textContaining('未包含的设置保持不变'), findsOneWidget);
      expect(find.textContaining('WebDAV 及自动同步需手动重新开启'),
          entry.key == 'webdav' ? findsOneWidget : findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(Prefs().ttsRate, 1.2);
      expect(Prefs().autoSync, true);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mixed payload lists actual scopes despite a single-scope label',
      (tester) async {
    final file = jsonDecode(
            await GlobalSettingsTransfer.export(Prefs(), includeSecrets: true))
        as Map<String, dynamic>;
    file['scope'] = 'tts';
    await open(tester);
    await preview(tester, GlobalSettingsTransfer.link(jsonEncode(file)));
    expect(find.text('恢复多项设置？'), findsOneWidget);
    expect(find.textContaining('导入范围：外观与书架、阅读与排版、CSS 模板与高亮规则'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'only global export is offered, with independent credential switch',
      (tester) async {
    await open(tester);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('导出全局设置文件'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy speech links use the same specific confirmation',
      (tester) async {
    await open(tester);
    await preview(
        tester,
        ConfigTransferCodec.encode(
            kind: 'tts', data: TtsConfigTransfer.defaults()));
    expect(find.text('恢复朗读配置？'), findsOneWidget);
    expect(find.textContaining('同步需手动重新开启'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty settings do not offer a misleading restore confirmation',
      (tester) async {
    final file =
        jsonDecode(await GlobalSettingsTransfer.export(Prefs(), scope: 'tts'))
            as Map<String, dynamic>;
    (file['preferences'] as Map).removeWhere((_, value) => value is Map);
    await open(tester);
    await preview(tester, GlobalSettingsTransfer.link(jsonEncode(file)));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('内容中没有可导入的设置，未作任何更改。'), findsOneWidget);
    expect(Prefs().ttsRate, 1.2);
    expect(Prefs().autoSync, true);
    expect(tester.takeException(), isNull);
  });
}
