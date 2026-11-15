import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/main.dart' show navigatorKey;
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:modu_reader/widgets/bookshelf/book_bottom_sheet.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../service/plugins/plugin_test_utils.dart';

void main() {
  testWidgets('reviewed plugin alone registers and removes the book hide menu',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    PackageInfo.setMockInitialValues(
        appName: 'Modu',
        packageName: 'com.modu.reader',
        version: '1.3.10',
        buildNumber: '10179',
        buildSignature: 'test');
    final temp = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('plugin-book-menu')))!;
    final oldPath = documentPath;
    documentPath = temp.path;
    final book = Book.mock()
        .copyWith(id: 42, title: 'Public book', filePath: 'file/visible.epub');
    await tester.runAsync(() async {
      await File(book.fileFullPath).parent.create(recursive: true);
      await File(book.fileFullPath).writeAsString('book');
    });
    final host = PluginHost.instance;
    addTearDown(() async {
      host.dispose();
      documentPath = oldPath;
      await temp.delete(recursive: true);
    });
    await tester.runAsync(host.initialize);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh'),
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: const [
              L10n.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            home:
                Scaffold(body: BookBottomSheet(book: book, menuOnly: true)))));
    await tester.runAsync(() => BookKnowledgeIndexService().hasIndex(book));
    await tester.pumpAndSettle();

    Future<void> open() async {
      await tester.tap(find.byTooltip('书籍操作'));
      await tester.pumpAndSettle();
    }

    Future<void> close() async {
      await tester.tapAt(const Offset(0, 0));
      await tester.pumpAndSettle();
    }

    Future<void> disable() async {
      late Future<void> done;
      await tester.runAsync(() async {
        done = host.disable('com.modu.private-books');
        done.ignore();
      });
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '解锁'));
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '停用'));
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.runAsync(() => done);
    }

    await open();
    expect(find.text('隐藏'), findsNothing);
    await close();
    await tester.runAsync(() async {
      final proof =
          await File('test/fixtures/plugins/catalog-private-books-1.1.signed.json')
              .readAsString();
      await host.trust.acceptCatalog(proof);
      final files = {
        for (final file
            in Directory('test/fixtures/plugins/private-books-1.1.0')
                .listSync()
                .whereType<File>())
          file.uri.pathSegments.last: await file.readAsString()
      };
      await host.install(await writePluginZip(temp, files));
    });
    await tester.pumpAndSettle();
    await open();
    expect(find.text('隐藏'), findsOneWidget);
    await tester.tap(find.text('隐藏'));
    await tester.pumpAndSettle();
    expect(find.text('解锁私密书库'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(PrivateLibrary.instance.isPrivate(book), false);
    await disable();
    await tester.pumpAndSettle();
    await open();
    expect(find.text('隐藏'), findsNothing);
    await close();
    await tester.runAsync(() => host.enable('com.modu.private-books'));
    await tester.pumpAndSettle();
    await open();
    expect(find.text('隐藏'), findsOneWidget);
    await disable();
    await tester.tap(find.text('隐藏'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(PrivateLibrary.instance.isPrivate(book), false);
  });
}
