import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/dao/reading_round.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/service/reading_round_service.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/reading_round_sync.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'sync/row_sync_test.dart' show bookRow, fixture;

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
    root = await Directory.systemTemp.createTemp('modu-round-regression-');
    previousPaths = PathProviderPlatform.instance;
    previousDocumentPath = documentPath;
    PathProviderPlatform.instance = _Paths(root.path);
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await initBasePath();
    db = await DBHelper().database;
    await db.insert('tb_books', {
      ...bookRow(1),
      'last_read_position': 'epubcfi(/6/8!/4/2/1:12)',
      'reading_percentage': 0.75,
    });
    await readingTimeDao.insertReadingSession(
        bookId: 1, readingTime: 120, startedAt: DateTime(2026, 10, 1));
  });

  tearDown(() async {
    await DBHelper.close();
    PathProviderPlatform.instance = previousPaths;
    documentPath = previousDocumentPath;
    await root.delete(recursive: true);
  });

  Future<Map<String, Object?>> snapshot() async {
    final result = <String, Object?>{};
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
    for (final table in tables) {
      final name = table['name'] as String;
      result[name] = await db.query(name);
    }
    return result;
  }

  test('fresh install and v9 upgrade preserve legacy history as round one',
      () async {
    // v10 = reading rounds; v11 = book review/notes. Keep this regression
    // test valid on both branches so a schema bump does not break the other PR.
    final version = await db.getVersion();
    expect(version, greaterThanOrEqualTo(10));
    expect(
        (await db.rawQuery('PRAGMA table_info(tb_reading_rounds)'))
            .map((row) => row['name']),
        contains('end_position'));
    // Reconstruct the v9 schema by removing exactly the v10/v11 additions.
    final bookColumns = (await db.rawQuery('PRAGMA table_info(tb_books)'))
        .map((row) => row['name'])
        .toSet();
    if (bookColumns.contains('review')) {
      for (final suffix in ['insert', 'update', 'delete']) {
        await db.execute('DROP TRIGGER IF EXISTS modu_review_$suffix');
      }
      await db.execute('ALTER TABLE tb_books DROP COLUMN review');
    }
    // If the sync v9 PR is already in main, its triggers reference `round`;
    // they must go before the column is dropped. No-op on v10 without them.
    for (final suffix in ['insert', 'update', 'delete']) {
      await db.execute('DROP TRIGGER IF EXISTS modu_time_$suffix');
      await db.execute('DROP TRIGGER IF EXISTS modu_round_$suffix');
    }
    await db.execute('DROP TABLE tb_reading_rounds');
    await db.execute('ALTER TABLE tb_books DROP COLUMN current_round');
    await db.execute('ALTER TABLE tb_reading_time DROP COLUMN round');
    await db.setVersion(9);
    await DBHelper.close();
    db = await DBHelper().database;
    expect(await db.getVersion(), version);
    expect((await bookDao.selectBookById(1)).currentRound, 1);
    expect((await db.query('tb_reading_time')).single['round'], 1);
    expect(
        await readingTimeDao.selectTotalReadingTimeByBookAndRound(1, 1), 120);
    expect(await db.query('tb_reading_rounds'), isEmpty);
    if (version >= 11) {
      expect(
          (await db.rawQuery('PRAGMA table_info(tb_books)'))
              .map((row) => row['name']),
          contains('review'));
    }
  });

  test('finish captures exact position and starts an empty second round',
      () async {
    final original = await bookDao.selectBookById(1);
    final next = await ReadingRoundService.finishCurrentRound(original);
    expect(next.currentRound, 2);
    expect(next.readingPercentage, 0);
    expect(next.lastReadPosition, '');
    final rounds = await readingRoundDao.selectRoundsByBookId(1);
    expect(rounds.map((r) => r.roundNumber), [1, 2]);
    expect(rounds.first.isFinished, isTrue);
    expect(rounds.first.totalReadingTime, 120);
    expect(rounds.first.endPosition, original.lastReadPosition);
    expect(rounds.first.endPercentage, 0.75);
    expect(rounds.last.isFinished, isFalse);
    expect(rounds.last.totalReadingTime, 0);
  });

  test('finish reset survives a round trip to an already synced device',
      () async {
    final remote = await fixture(bookId: 77);
    try {
      await RowSyncStore(remote).merge(await RowSyncStore(db).snapshot());
      await ReadingRoundService.finishCurrentRound(
          await bookDao.selectBookById(1));
      await RowSyncStore(remote).merge(await RowSyncStore(db).snapshot());
      await ReadingRoundSync.reconcile(remote);
      await RowSyncStore(db).merge(await RowSyncStore(remote).snapshot());
      await ReadingRoundSync.reconcile(db);
      final book = await bookDao.selectBookById(1);
      expect(book.currentRound, 2);
      expect(book.lastReadPosition, '');
      expect(book.readingPercentage, 0);
      final received = await remote.query('tb_books', where: 'id=77');
      expect(received.single['last_read_position'], '');
      expect(received.single['reading_percentage'], 0);
    } finally {
      await remote.close();
    }
  });

  test(
      'undo reopens previous round and reattributes new time without losing sessions',
      () async {
    final original = await bookDao.selectBookById(1);
    final next = await ReadingRoundService.finishCurrentRound(original);
    final firstStart =
        (await readingRoundDao.selectRoundsByBookId(1)).first.startTime;
    await readingTimeDao.insertReadingSession(
        bookId: 1, readingTime: 35, round: 2);
    final ids =
        (await db.query('tb_reading_time')).map((r) => r['id']).toList();
    final restored = await ReadingRoundService.undoLastRound(next);
    expect(restored.currentRound, 1);
    expect(restored.readingPercentage, original.readingPercentage);
    expect(restored.lastReadPosition, original.lastReadPosition);
    final round = (await readingRoundDao.selectRoundsByBookId(1)).single;
    expect(round.isFinished, isFalse);
    expect(round.startTime, firstStart);
    expect(round.endTime, isNull);
    expect(round.endPosition, isNull);
    expect(round.totalReadingTime, 155);
    final sessions = await db.query('tb_reading_time');
    expect(sessions.map((r) => r['id']), ids);
    expect(sessions.map((r) => r['round']), everyElement(1));
    expect(await readingTimeDao.selectTotalReadingTimeByBookAndRound(1, 2), 0);
  });

  test('repeated finish undo finish never duplicates round numbers', () async {
    final original = await bookDao.selectBookById(1);
    for (var i = 0; i < 3; i++) {
      // A stale caller must not override the database's current round.
      await ReadingRoundService.finishCurrentRound(original);
      await readingTimeDao.insertReadingSession(
          bookId: 1, readingTime: 10, round: 2);
      await ReadingRoundService.undoLastRound(original);
      expect(await readingRoundDao.selectRoundsByBookId(1), hasLength(1));
    }
    await ReadingRoundService.finishCurrentRound(original);
    final rounds = await readingRoundDao.selectRoundsByBookId(1);
    expect(rounds.map((r) => r.roundNumber), [1, 2]);
    expect(rounds.first.totalReadingTime, 150);
    expect(rounds.last.totalReadingTime, 0);
  });

  for (final undo in [false, true]) {
    test(
        '${undo ? 'undo' : 'finish'} failure rolls back all data including sync records',
        () async {
      final original = await bookDao.selectBookById(1);
      if (undo) {
        await ReadingRoundService.finishCurrentRound(original);
        await readingTimeDao.insertReadingSession(
            bookId: 1, readingTime: 35, round: 2);
      }
      final before = await snapshot();
      // Fail at the final write, after the round/time mutations have run.
      await db.execute('''CREATE TRIGGER fail_round_commit
        BEFORE UPDATE OF current_round ON tb_books
        BEGIN SELECT RAISE(ABORT, 'injected round commit failure'); END''');
      await expectLater(
        undo
            ? ReadingRoundService.undoLastRound(original)
            : ReadingRoundService.finishCurrentRound(original),
        throwsA(isA<DatabaseException>()),
      );
      expect(await snapshot(), before);
      await db.execute('DROP TRIGGER fail_round_commit');
      if (undo) {
        expect((await ReadingRoundService.undoLastRound(original)).currentRound,
            1);
      } else {
        expect(
            (await ReadingRoundService.finishCurrentRound(original))
                .currentRound,
            2);
      }
    });
  }

  test('round changes do not affect another book', () async {
    await db.insert('tb_books', bookRow(2, md5: 'other'));
    await readingTimeDao.insertReadingSession(bookId: 2, readingTime: 77);
    final other = await bookDao.selectBookById(2);
    await ReadingRoundService.finishCurrentRound(other);
    final beforeBook = await db.query('tb_books', where: 'id=2');
    final beforeTime = await db.query('tb_reading_time', where: 'book_id=2');
    final beforeRounds =
        await db.query('tb_reading_rounds', where: 'book_id=2');
    final first = await bookDao.selectBookById(1);
    await ReadingRoundService.finishCurrentRound(first);
    await ReadingRoundService.undoLastRound(first);
    expect(await db.query('tb_books', where: 'id=2'), beforeBook);
    expect(await db.query('tb_reading_time', where: 'book_id=2'), beforeTime);
    expect(
        await db.query('tb_reading_rounds', where: 'book_id=2'), beforeRounds);
  });

  test('undo at round one is a no-op', () async {
    final original = await bookDao.selectBookById(1);
    final before = await snapshot();
    await ReadingRoundService.undoLastRound(original);
    expect(await snapshot(), before);
  });
}
