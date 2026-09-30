import 'dart:async';
import 'dart:io';

import 'package:anx_reader/page/android_storage_startup.dart';
import 'package:anx_reader/l10n/app_language.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> renderStartup(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  });
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() async {
    for (final locale in appLocales) {
      await L10n.delegate.load(locale);
    }
  });
  testWidgets('shows progress, safe failure and permits retry', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = [
      const Locale('zh', 'CN')
    ];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    var attempts = 0;
    final ready = Completer<void>();
    await tester.pumpWidget(AndroidStorageStartup(start: () async {
      attempts++;
      if (attempts == 1) {
        throw const FileSystemException('disk full', '/private/path');
      }
      await ready.future;
    }));
    await renderStartup(tester);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('/private/path'), findsNothing);
    expect(find.textContaining('可用空间'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    ready.complete();
    await tester.pump();
  });

  for (final locale in appLocales) {
    testWidgets('$locale storage startup follows system without reading prefs',
        (tester) async {
      tester.binding.platformDispatcher.localesTestValue = [locale];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      final pending = Completer<void>();
      await tester
          .pumpWidget(AndroidStorageStartup(start: () => pending.future));
      await renderStartup(tester);
      final context = tester.element(find.byType(Column));
      expect(
          find.text(ModuStrings.text(
              context,
              '正在准备应用数据…\n首次迁移到 Android/data 可能需要一些时间。',
              'Preparing app data…\nThe first migration to Android/data may take some time.')),
          findsOneWidget);
      pending.completeError(StateError('private fixture details'));
      await tester.pump();
      expect(
          find.text(ModuStrings.text(context, '重试', 'Retry')), findsOneWidget);
      expect(find.textContaining('private fixture'), findsNothing);
      expect(Localizations.localeOf(context), locale);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
