import 'dart:async';
import 'dart:io';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/book_review_editor_page.dart';
import 'package:anx_reader/providers/sync_database_revision.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/book_review/book_review_card.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../service/sync/row_sync_test.dart' show bookRow;

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUpAll(() async {
    await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('open review card refreshes after remote edits and clearing',
      (tester) async {
    final previousPaths = PathProviderPlatform.instance;
    final previousDocumentPath = documentPath;
    late Directory root;
    late Database db;
    final container = ProviderContainer();
    await tester.runAsync(() async {
      await DBHelper.close();
      root = await Directory.systemTemp.createTemp('pr48-card-');
      PathProviderPlatform.instance = _Paths(root.path);
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      await initBasePath();
      db = await DBHelper().database;
      await db.insert('tb_books', bookRow(1));
      await bookDao.updateReview(1, 'Local review');
      expect(
          (await RowSyncStore(db).snapshot())
              .singleWhere((r) => r.kind == 'review')
              .data['review'],
          'Local review');
    });
    try {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(
              body: BookReviewCard(bookId: 1, bookTitle: 'Test')),
        ),
      ));
      Future<void> settleDb() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)));
        }
        await tester.pump();
      }

      await settleDb();
      expect(tester.widget<StyledMarkdown>(find.byType(StyledMarkdown)).data,
          'Local review');
      for (final text in ['Remote review', '']) {
        await tester.runAsync(() async {
          final before = (await RowSyncStore(db).snapshot())
              .singleWhere((r) => r.kind == 'review');
          await RowSyncStore(db).merge([
            RowSyncRecord('review', before.id, before.clock + 1, 'remote',
                false, {'review': text})
          ]);
        });
        container.read(syncDatabaseRevisionProvider.notifier).state++;
        await tester.pump();
        await settleDb();
        if (text.isEmpty) {
          expect(find.byType(StyledMarkdown), findsNothing);
        } else {
          expect(
              tester.widget<StyledMarkdown>(find.byType(StyledMarkdown)).data,
              text);
        }
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.runAsync(() async {
        await DBHelper.close();
        PathProviderPlatform.instance = previousPaths;
        documentPath = previousDocumentPath;
        await root.delete(recursive: true);
      });
    }
  });

  testWidgets('edits during pending save are not silently discarded',
      (tester) async {
    final previousPaths = PathProviderPlatform.instance;
    final previousDocumentPath = documentPath;
    late Directory root;
    late Database db;
    await tester.runAsync(() async {
      await DBHelper.close();
      root = await Directory.systemTemp.createTemp('pr48-review-');
      PathProviderPlatform.instance = _Paths(root.path);
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      await initBasePath();
      db = await DBHelper().database;
      await db.insert('tb_books', bookRow(1));
    });
    final navigator = GlobalKey<NavigatorState>();
    String? returned;
    late Completer<void> release;
    await tester.runAsync(() async {
      release = Completer<void>();
    });
    Future<void>? lock;
    try {
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: Text('home')),
      ));
      await tester.pumpAndSettle();
      navigator.currentState!
          .push<String>(MaterialPageRoute(
            builder: (_) => const BookReviewEditorPage(
                bookId: 1, bookTitle: 'Test', initialReview: ''),
          ))
          .then((value) => returned = value);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'before save');
      await tester.pump();
      await tester.runAsync(() async {
        final entered = Completer<void>();
        lock = db.transaction((txn) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
      });
      await tester.tap(find.byIcon(Icons.check));
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.readOnly, isTrue);
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BookReviewEditorPage), findsOneWidget);
      await tester.runAsync(() async {
        release.complete();
        await lock;
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      final stored = await tester.runAsync(() => bookDao.selectReview(1));
      expect(find.byType(BookReviewEditorPage), findsNothing);
      expect(returned, 'before save');
      expect(stored, returned,
          reason: 'Closed editor must not claim unsaved text was saved');
    } finally {
      if (!release.isCompleted) release.complete();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await lock;
        await DBHelper.close();
        PathProviderPlatform.instance = previousPaths;
        documentPath = previousDocumentPath;
        await root.delete(recursive: true);
      });
    }
  });
}
