import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/app_language.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_catalogs.g.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/widgets/settings/database_backup_section.dart';
import 'package:anx_reader/widgets/settings/settings_export_dialog.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    for (final locale in appLocales) {
      await L10n.delegate.load(locale);
    }
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<void> open(WidgetTester tester,
      {Locale locale = const Locale('en'),
      AnxPlatformEnum platform = AnxPlatformEnum.windows,
      bool busy = false,
      VoidCallback? onExport,
      VoidCallback? onImport}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: appLocales,
      localeListResolutionCallback: resolveAppLocale,
      localizationsDelegates: L10n.localizationsDelegates,
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: SingleChildScrollView(
            child: DatabaseBackupSection(
              platform: platform,
              busy: busy,
              onExport: onExport ?? () {},
              onImport: onImport ?? () {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final locale in appLocales) {
    testWidgets('$locale backup names and instructions fit a small screen',
        (tester) async {
      await open(tester, locale: locale);
      final catalog = moduCatalogs[appLocaleKey(locale)]!;
      for (final key in [
        'ui_database_backup_title',
        'ui_database_backup_export',
        'ui_database_backup_import',
        'ui_database_backup_contents',
        'ui_database_backup_export_step',
        'ui_database_backup_import_step',
        'ui_database_backup_save_windows',
      ]) {
        expect(find.text(catalog[key]!), findsOneWidget, reason: key);
      }
      expect(find.text('Export/Import'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in AnxPlatformEnum.values) {
    testWidgets('$platform accurately describes the destination',
        (tester) async {
      await open(tester, platform: platform);
      final key = switch (platform) {
        AnxPlatformEnum.windows => 'ui_database_backup_save_windows',
        AnxPlatformEnum.macos ||
        AnxPlatformEnum.linux =>
          'ui_database_backup_save_desktop',
        _ => 'ui_database_backup_save_mobile',
      };
      final hint = moduCatalogs['en']![key]!;
      expect(find.widgetWithText(SelectableText, hint), findsOneWidget);
      if (platform == AnxPlatformEnum.windows) {
        expect(hint, contains(r'C:\Users\<username>\Downloads'));
      } else {
        expect(hint, contains('system save dialog'));
        expect(hint, isNot(contains(r'C:\Users\')));
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final busy in [false, true]) {
    testWidgets('backup actions are routed correctly and gated by busy=$busy',
        (tester) async {
      var exports = 0, imports = 0;
      await open(tester,
          busy: busy, onExport: () => exports++, onImport: () => imports++);
      for (final key in ['database-backup-export', 'database-backup-import']) {
        final finder = find.byKey(ValueKey(key));
        expect(tester.widget<SettingsTile>(finder).enabled, !busy);
        await tester.ensureVisible(finder);
        await tester.tap(finder, warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      expect(exports, busy ? 0 : 1);
      expect(imports, busy ? 0 : 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final path in [
    r'C:\Users\reader\Downloads\Modu-Backup-2026-10-1-v3.zip',
    'content://documents/document/43',
  ]) {
    testWidgets('ZIP export confirmation copies a usable destination: $path',
        (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await open(tester);
      final destination = SettingsExportDestination(
          path: path, fileName: 'Modu-Backup-2026-10-1-v3.zip');
      showDialog<void>(
        context: tester.element(find.byType(DatabaseBackupSection)),
        builder: (_) => SettingsExportDialog(destination: destination),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SelectableText, destination.copyValue),
          findsOneWidget);
      await tester.tap(find.text(
          destination.isSystemDocument ? 'Copy file name' : 'Copy location'));
      await tester.pump();
      expect(copied, destination.copyValue);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  test('sync navigation and dialogs use database backup terminology', () {
    final source = File('lib/page/settings_page/sync.dart').readAsStringSync();
    final navigation = File('lib/page/settings_page/more_settings_page.dart')
        .readAsStringSync();
    expect(source, contains('DatabaseBackupSection('));
    expect(source, contains('onExport: () => exportData(context)'));
    expect(source, contains('onImport: importData'));
    expect(source, contains('数据库备份导出'));
    expect(source, contains('数据库备份导入'));
    expect(source, contains('SettingsExportDialog('));
    expect(source, contains('path: filePath, fileName: fileName'));
    expect(source, isNot(contains('.exportAndImport')));
    expect(navigation, contains("'数据库备份', 'Database backup'"));
    expect(navigation, isNot(contains('.exportAndImport')));
  });
}
