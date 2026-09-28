import 'package:anx_reader/page/settings_page/subpage/anx_backup_import_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final chinese in [true, false]) {
    testWidgets(
        'backup-only instructions and no automatic database scanning ($chinese)',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
        locale: Locale(chinese ? 'zh' : 'en'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const AnxBackupImportPage(),
      )));
      expect(
          find.text(
              chinese ? '导入 ANX Reader 的备份文件' : 'Import ANX Reader backup'),
          findsOneWidget);
      expect(find.textContaining(chinese ? '不要解压' : 'do not extract'),
          findsOneWidget);
      final limits = find.textContaining(chinese ? 'API 密钥' : 'API keys');
      await tester.ensureVisible(limits);
      expect(limits, findsOneWidget);
      expect(
          find.textContaining(chinese ? '版本为 7' : 'version 7'), findsOneWidget);
      final picker =
          find.text(chinese ? '选择 ANX 备份 ZIP' : 'Select ANX backup ZIP');
      await tester.scrollUntilVisible(picker, 350);
      expect(picker, findsOneWidget);
      expect(find.text('自动查找'), findsNothing);
      expect(find.text(chinese ? '开始导入' : 'Start import'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
