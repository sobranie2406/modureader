import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'sync/row_sync_test.dart' show fixture, bookRow, noteRow;

class _BookDao extends BookDao {
  _BookDao(this.db);
  final Database db;
  @override
  Future<R> transaction<R>(Future<R> Function(Transaction) action) =>
      db.transaction(action);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late _BookDao dao;
  setUp(() async {
    db = await fixture();
    dao = _BookDao(db);
    await db.insert('tb_books', bookRow(2, md5: 'book-two'));
    await db.insert('tb_books', bookRow(3, md5: 'book-three'));
  });
  tearDown(() => db.close());

  test(
      'creates named folder, deduplicates IDs and preserves all other book data',
      () async {
    await db.insert('tb_notes', noteRow(1, 'note'));
    final before = await db.query('tb_books', orderBy: 'id');
    final notes = await db.query('tb_notes');
    final folder =
        await dao.moveBooksToFolder([1, 2, 1], newFolderName: '  古籍  ');
    expect(
        (await db.query('tb_groups', where: 'id=?', whereArgs: [folder]))
            .single['name'],
        '古籍');
    final after = await db.query('tb_books', orderBy: 'id');
    for (var i = 0; i < 3; i++) {
      final expected = Map<String, Object?>.of(before[i]);
      final actual = Map<String, Object?>.of(after[i]);
      if (i < 2) {
        expect(actual.remove('group_id'), folder);
        expected.remove('group_id');
        actual.remove('update_time');
        expected.remove('update_time');
      }
      expect(actual, expected);
    }
    expect(await db.query('tb_notes'), notes);
  });

  test('moves from different folders into existing folder, supports one book',
      () async {
    final first = await dao.moveBooksToFolder([1], newFolderName: '第一夹');
    final second = await dao.moveBooksToFolder([2], newFolderName: '第二夹');
    await dao.moveBooksToFolder([1, 3], groupId: second);
    expect((await db.query('tb_books')).every((b) => b['group_id'] == second),
        isTrue);
    expect(await db.query('tb_groups', where: 'id=?', whereArgs: [first]),
        isNotEmpty);
    // An emptied folder can still be selected as a destination later.
    await dao.moveBooksToFolder([3], groupId: first);
    expect(
        (await db.query('tb_books', where: 'id=3')).single['group_id'], first);
  });

  test('already in target is a no-op, not a new sync update', () async {
    final folder = await dao.moveBooksToFolder([1], newFolderName: '夹');
    final before = await db.query(syncRecordsTable);
    final books = await db.query('tb_books');
    await dao.moveBooksToFolder([1], groupId: folder);
    expect(await db.query(syncRecordsTable), before);
    expect(await db.query('tb_books'), books);
  });

  test('missing or deleted book aborts the entire operation without new folder',
      () async {
    await db.update('tb_books', {'is_deleted': 1}, where: 'id=2');
    for (final invalidId in [2, 999]) {
      await expectLater(
          dao.moveBooksToFolder([1, invalidId], newFolderName: '不能留下空夹'),
          throwsStateError);
      expect((await db.query('tb_books', where: 'id=1')).single['group_id'], 0);
      expect((await db.query('tb_groups')).length, 1);
    }
  });

  test('deleted or missing destination does not move any books', () async {
    final id = await dao.moveBooksToFolder([3], newFolderName: '已删除');
    await db.update('tb_groups', {'is_deleted': 1},
        where: 'id=?', whereArgs: [id]);
    for (final target in [id, 999]) {
      await expectLater(
          dao.moveBooksToFolder([1, 2], groupId: target), throwsStateError);
      expect((await db.query('tb_books', where: 'id=1')).single['group_id'], 0);
    }
  });

  test('failure in second move rolls back first move and folder insertion',
      () async {
    await db.execute(
        "CREATE TRIGGER fail_move BEFORE UPDATE OF group_id ON tb_books WHEN NEW.id=2 BEGIN SELECT RAISE(ABORT, 'fixture'); END");
    await expectLater(dao.moveBooksToFolder([1, 2], newFolderName: '事务'),
        throwsA(isA<DatabaseException>()));
    expect(
        (await db.query('tb_books')).every((b) => b['group_id'] == 0), isTrue);
    expect((await db.query('tb_groups')).length, 1);
  });

  test('validates selection and destination before writing', () async {
    await expectLater(
        dao.moveBooksToFolder([], newFolderName: '夹'), throwsArgumentError);
    await expectLater(
        dao.moveBooksToFolder([1], newFolderName: '  '), throwsArgumentError);
    await expectLater(
        dao.moveBooksToFolder([1], groupId: 0), throwsArgumentError);
    await expectLater(
        dao.moveBooksToFolder([1], groupId: 1, newFolderName: '夹'),
        throwsArgumentError);
    await expectLater(dao.moveBooksToFolder([1]), throwsArgumentError);
  });

  test('folder membership participates in existing cross-device row sync',
      () async {
    final remote = await fixture(bookId: 77);
    try {
      await dao.moveBooksToFolder([1, 2], newFolderName: '同步夹');
      await RowSyncStore(remote).merge(await RowSyncStore(db).snapshot());
      final books = await remote.query('tb_books',
          where: 'file_md5 IN (?, ?)', whereArgs: ['same-content', 'book-two']);
      expect(books.length, 2);
      expect(books.map((b) => b['group_id']).toSet().length, 1);
      final group = (await remote.query('tb_groups',
              where: 'id=?', whereArgs: [books.first['group_id']]))
          .single;
      expect(group['name'], '同步夹');
      expect(books.first['last_read_position'], 'start');
    } finally {
      await remote.close();
    }
  });
}
