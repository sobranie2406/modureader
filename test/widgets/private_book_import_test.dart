import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/dao/book.dart';
import 'package:modu_reader/dao/database.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/main.dart' show navigatorKey;
import 'package:modu_reader/service/book.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/service/sync/private_book_sync.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../service/sync/row_sync_test.dart' show bookRow, noteRow;

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final library = PrivateLibrary.instance;
  late Directory root;
  late PathProviderPlatform oldPaths;
  late String oldDocumentPath;
  setUp(() async {
    await DBHelper.close();
    root = await Directory.systemTemp.createTemp('modu-private-import-');
    oldPaths = PathProviderPlatform.instance;
    oldDocumentPath = documentPath;
    PathProviderPlatform.instance = _Paths(root.path);
  });
  tearDown(() async {
    library.importPolicy = null;
    library.setPluginActive(false);
    await DBHelper.close();
    PathProviderPlatform.instance = oldPaths;
    documentPath = oldDocumentPath;
    await root.delete(recursive: true);
  });

  for (final marker in ['m:old-source', 'f:file/old-source.epub']) {
    testWidgets('replacing a legacy $marker private book retains its identity',
        (tester) async {
      var policyCalls = 0;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({
          'vectorModelEnabled': false,
          'privateLibrary_v1': jsonEncode({
            'books': [marker]
          }),
        });
        await Prefs().initPrefs();
        await initBasePath();
        library.setPluginActive(true);
        library.importPolicy = (_) async {
          policyCalls++;
          return false;
        };
        final db = await DBHelper().database;
        await db.insert('tb_books', {
          ...bookRow(42, md5: 'old-source'),
          'last_read_position': 'saved-position',
          'reading_percentage': .4,
        });
        await db.insert('tb_notes', noteRow(42, 'saved-note'));
        final old = await bookDao.selectBookById(42);
        expect(library.isPrivate(old), true);
        expect(library.syncExcludedLocalBookIds, isEmpty);
        await File(old.fileFullPath).writeAsString('original bytes');
      });
      await tester.pumpWidget(MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(body: Text('Library'))));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final source = await File('${root.path}/converted.epub')
            .writeAsString('converted bytes');
        await saveBook(
            source, 'Imported', 'Imported author', '', 'replacement-hash', '',
            sourceMd5: 'old-source');
        final replacement = await bookDao.selectBookById(42);
        expect(replacement.md5, 'replacement-hash');
        expect(replacement.filePath, isNot('file/old-source.epub'));
        expect(replacement.lastReadPosition, 'saved-position');
        expect(replacement.readingPercentage, .4);
        expect(policyCalls, 0);
        expect(library.isPrivate(replacement), true);
        expect(library.canRead(replacement), false);
        expect(library.canSyncBook(replacement), false);
        expect(library.syncExcludedLocalBookIds, contains(42));
        expect(await source.readAsString(), 'converted bytes');
        final db = await DBHelper().database;
        expect((await db.query('tb_notes')).single['content'], 'saved-note');
        final records = await RowSyncStore(db).snapshot();
        final outgoing = PrivateBookSyncFilter(records).allowedRecords(records);
        expect(outgoing.where((row) => row.kind == 'book'), isEmpty);
        expect(outgoing.where((row) => row.kind == 'note'), isEmpty);
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
