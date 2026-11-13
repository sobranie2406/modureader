import 'dart:io';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/dao/book.dart';
import 'package:modu_reader/dao/database.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sync/row_sync_test.dart' show bookRow;

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
  late Directory root;
  late PathProviderPlatform previousPaths;
  late String previousDocumentPath;
  late Database db;

  setUp(() async {
    await DBHelper.close();
    root = await Directory.systemTemp.createTemp('modu-book-review-test-');
    previousPaths = PathProviderPlatform.instance;
    previousDocumentPath = documentPath;
    PathProviderPlatform.instance = _Paths(root.path);
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await initBasePath();
    db = await DBHelper().database;
    await db.insert('tb_books', bookRow(1));
  });

  tearDown(() async {
    await DBHelper.close();
    PathProviderPlatform.instance = previousPaths;
    documentPath = previousDocumentPath;
    await root.delete(recursive: true);
  });

  test('review round trip and empty value deletes it', () async {
    expect(await bookDao.selectReview(1), '');

    await bookDao.updateReview(1, '# 读后感\n- **很好**\n> 引用');
    expect(await bookDao.selectReview(1), '# 读后感\n- **很好**\n> 引用');

    await bookDao.updateReview(1, '');
    expect(await bookDao.selectReview(1), '');

    await bookDao.updateReview(1, null);
    expect(await bookDao.selectReview(1), '');
  });

  test(
      'adopting WeRead metadata never replaces personal review, rating or progress',
      () async {
    await bookDao.updateReview(1, '我的书评');
    await db.update(
        'tb_books',
        {
          'rating': 4.5,
          'current_round': 3,
          'last_read_position': 'local-cfi',
          'reading_percentage': 0.8,
        },
        where: 'id = 1');
    await bookDao.updateExternalMetadata(1, description: '外部简介');
    var current = await bookDao.selectBookById(1);
    expect(current.description, '外部简介');
    expect(current.review, '我的书评');
    expect(current.rating, 4.5);
    expect(current.currentRound, 3);
    expect(current.lastReadPosition, 'local-cfi');
    expect(current.readingPercentage, 0.8);
    await bookDao.updateExternalMetadata(1, coverPath: 'cover/confirmed.png');
    current = await bookDao.selectBookById(1);
    expect(current.coverPath, 'cover/confirmed.png');
    expect(current.description, '外部简介');
    expect(current.review, '我的书评');
    expect(current.rating, 4.5);
  });

  test('a stale Book instance cannot clobber a saved review', () async {
    final stale = await bookDao.selectBookById(1);
    await bookDao.updateReview(1, 'keep me');

    // Same code path as saving progress / replacing a book file.
    stale.title = 'Changed title';
    await bookDao.updateBook(stale);

    expect(await bookDao.selectReview(1), 'keep me');
    expect((await bookDao.selectBookById(1)).review, 'keep me');
    expect((await bookDao.selectBookById(1)).title, 'Changed title');
  });

  test('Book.fromDb exposes review without writing it back', () async {
    await bookDao.updateReview(1, 'markdown');
    final book = await bookDao.selectBookById(1);
    expect(book.review, 'markdown');
    expect(book.toMap().containsKey('review'), isFalse);
  });
}
