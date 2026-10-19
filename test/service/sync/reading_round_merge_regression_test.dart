import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:anx_reader/models/reading_round.dart';
import 'package:anx_reader/service/sync/reading_round_sync.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'row_sync_test.dart' show fixture;
import 'reading_round_sync_test.dart' show roundRow;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('received rounds can be read by the production model', () async {
    final a = await fixture();
    final b = await fixture(bookId: 77);
    try {
      await a.insert('tb_reading_rounds', roundRow(1, 1));
      await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
      final rows = await b.query('tb_reading_rounds');
      expect(() => rows.map(ReadingRound.fromDb).toList(), returnsNormally);
      expect(rows.single['create_time'], isNotNull);
      expect(rows.single['update_time'], isNotNull);
    } finally {
      await a.close();
      await b.close();
    }
  });

  test('starting round two keeps the reset position on both devices', () async {
    final a = await fixture();
    final b = await fixture(bookId: 77);
    try {
      await a.update('tb_books', {
        'last_read_position': 'chapter-final',
        'reading_percentage': .98,
      });
      await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
      // The same transaction writes performed by finishCurrentRound.
      await a.transaction((txn) async {
        await txn.insert('tb_reading_rounds',
            roundRow(1, 1, status: ReadingRound.statusFinished, end: .98));
        await txn.insert('tb_reading_rounds', roundRow(1, 2));
        await txn.update('tb_books', {
          'current_round': 2,
          'last_read_position': '',
          'reading_percentage': 0.0,
        });
        await RowSyncStore.markPositionReset(txn, 1);
      });
      await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
      await ReadingRoundSync.reconcile(b);
      await RowSyncStore(a).merge(await RowSyncStore(b).snapshot());
      await ReadingRoundSync.reconcile(a);
      for (final db in [a, b]) {
        final book = (await db.query('tb_books')).single;
        expect(book['current_round'], 2);
        expect(book['last_read_position'], '');
        expect(book['reading_percentage'], 0);
      }
      await b.update('tb_books', {
        'last_read_position': 'new-round-chapter',
        'reading_percentage': .1,
      });
      await RowSyncStore(a).merge(await RowSyncStore(b).snapshot());
      expect((await a.query('tb_books')).single['last_read_position'],
          'new-round-chapter');
    } finally {
      await a.close();
      await b.close();
    }
  });

  test('canonical book identity leaves one row per reading round', () async {
    final a = await fixture();
    final b = await fixture(bookId: 77, install: false);
    try {
      await b.update('tb_books', {'file_md5': null});
      await b.transaction((txn) => RowSyncStore.install(txn));
      await a.insert('tb_reading_rounds', roundRow(1, 1));
      await b.insert('tb_reading_rounds', roundRow(77, 1));
      await RowSyncStore(a).merge(await RowSyncStore(b).snapshot());
      final liveBook =
          (await a.query('tb_books', where: 'is_deleted=0')).single;
      final rows = await a.query('tb_reading_rounds',
          where: 'book_id=? AND round_number=1', whereArgs: [liveBook['id']]);
      expect(rows, hasLength(1));
      for (var i = 0; i < 3; i++) {
        await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
        await RowSyncStore(a).merge(await RowSyncStore(b).snapshot());
      }
      for (final db in [a, b]) {
        expect(await db.query('tb_reading_rounds'), hasLength(1));
        final records = await RowSyncStore(db).snapshot();
        final book = records.singleWhere((r) => r.kind == 'book' && !r.deleted);
        expect(
            records.singleWhere((r) => r.kind == 'round').id, '${book.id}:r1');
        final received = await db.query('tb_reading_rounds');
        expect(
            () => received.map(ReadingRound.fromDb).toList(), returnsNormally);
      }
      expect(
          sameSyncRecords(await RowSyncStore(a).snapshot(),
              await RowSyncStore(b).snapshot()),
          isTrue);
    } finally {
      await a.close();
      await b.close();
    }
  });
}
