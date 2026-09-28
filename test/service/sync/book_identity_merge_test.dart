import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/immutable_sync_log.dart';
import 'row_sync_test.dart' show fixture, bookRow, noteRow, MemorySyncClient;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  Future<void> converge(Database a, Database b) async {
    for (var i = 0; i < 3; i++) {
      await RowSyncStore(a).merge(await RowSyncStore(b).snapshot());
      await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
    }
    expect(
        sameSyncRecords(
            await RowSyncStore(a).snapshot(), await RowSyncStore(b).snapshot()),
        isTrue);
  }

  for (final atomic in [true, false]) {
    test(
        'cloud-only duplicates publish repair without user edits, atomic=$atomic',
        () async {
      final a = await fixture();
      final b = await fixture(bookId: 77, install: false);
      final temp = await Directory.systemTemp.createTemp('modu-cloud-alias-');
      try {
        await b.update('tb_books', {'file_md5': null});
        await b.transaction((txn) => RowSyncStore.install(txn));
        final raw = mergeSyncRecords(
            await RowSyncStore(a).snapshot(), await RowSyncStore(b).snapshot(),
            reconcileBookIdentities: false);
        final file = File('${temp.path}/cloud.db');
        await RowSyncArchive.write(file.path, raw);
        final client = MemorySyncClient()..atomic = atomic;
        client.files[RowSyncEngine.remotePath] = await file.readAsBytes();
        client.revisions[RowSyncEngine.remotePath] = 1;
        final engine =
            RowSyncEngine(store: RowSyncStore(a), client: client, cache: temp);
        expect(await engine.synchronize(), RowSyncOutcome.published);
        final downloaded = File('${temp.path}/download.db');
        await client.downloadFile(RowSyncEngine.remotePath, downloaded.path);
        final database = await RowSyncArchive.read(downloaded.path);
        final journal =
            await ImmutableSyncLog(client, temp, temp, durableDirectory: temp)
                .read();
        // Without the new identity-normalizer, the transmitted tombstones
        // already retire the old book and its independent lifecycle record.
        final oldClientView =
            mergeSyncRecords(database, journal, reconcileBookIdentities: false);
        expect(
            oldClientView.where((r) => r.kind == 'book' && !r.deleted).length,
            1);
        final alias =
            oldClientView.firstWhere((r) => r.kind == 'book' && r.deleted);
        expect(
            oldClientView
                .singleWhere((r) => r.kind == 'life' && r.id == alias.id)
                .deleted,
            isTrue);
        expect(await engine.synchronize(), RowSyncOutcome.unchanged);
      } finally {
        await a.close();
        await b.close();
        await temp.delete(recursive: true);
      }
    });
  }

  test(
      'identity repair is commutative, idempotent and retains redirect evidence',
      () async {
    final a = await fixture();
    final b = await fixture(bookId: 77, install: false);
    try {
      await b.update('tb_books', {'file_md5': null});
      await b.transaction((txn) => RowSyncStore.install(txn));
      final x = await RowSyncStore(a).snapshot();
      final y = await RowSyncStore(b).snapshot();
      final joined = mergeSyncRecords(x, y);
      expect(sameSyncRecords(joined, mergeSyncRecords(y, x)), isTrue);
      expect(sameSyncRecords(joined, mergeSyncRecords(joined, joined)), isTrue);
      expect(sameSyncRecords(joined, mergeSyncRecords(joined, y)), isTrue);
      expect(joined.where((r) => r.kind == 'book' && !r.deleted).length, 1);
      expect(joined.where((r) => bookSyncAliasTarget(r) != null).length, 3);
      expect(
          joined
              .singleWhere((r) => r.kind == 'book' && r.deleted)
              .data['file_path'],
          'file/same-content.epub');
    } finally {
      await a.close();
      await b.close();
    }
  });

  test(
      'deleted independent copy does not delete a separately imported live book',
      () async {
    final a = await fixture();
    final b = await fixture(bookId: 77, install: false);
    try {
      await a.update('tb_books', {'is_deleted': 1});
      await b.update('tb_books', {'file_md5': null});
      await b.transaction((txn) => RowSyncStore.install(txn));
      await converge(a, b);
      expect((await a.query('tb_books', where: 'is_deleted=0')).length, 1);
      expect((await a.query('tb_books')).length, 2);
    } finally {
      await a.close();
      await b.close();
    }
  });

  test('invalid reference rolls back alias rebinding and duplicate retirement',
      () async {
    final a = await fixture(install: false);
    final b = await fixture(bookId: 77);
    try {
      await a.update('tb_books', {'file_md5': null});
      await a.transaction((txn) => RowSyncStore.install(txn));
      final before = await RowSyncStore(a).snapshot();
      final bad = RowSyncRecord('note', 'bad-reference', 1, 'x', false, {
        ...noteRow(1, 'bad'),
        'book_id': 'missing',
        'chapter': null,
        'color': null,
        'reader_note': null,
      });
      await expectLater(
          RowSyncStore(a).merge([...await RowSyncStore(b).snapshot(), bad]),
          throwsFormatException);
      expect(sameSyncRecords(before, await RowSyncStore(a).snapshot()), isTrue);
      expect(
          (await a.query('tb_books', where: 'is_deleted=0')).single['id'], 1);
      await a.insert('tb_notes', noteRow(1, 'tracking-still-active'));
      expect(
          (await RowSyncStore(a).snapshot())
              .where((r) => r.kind == 'note')
              .length,
          1);
    } finally {
      await a.close();
      await b.close();
    }
  });

  for (final backfill in [false, true]) {
    test(
        'path and MD5 identities merge, backfill=$backfill, references survive',
        () async {
      final a = await fixture(install: false);
      final b = await fixture(bookId: 77);
      try {
        await a.update('tb_books', {'file_md5': null});
        await a.transaction((txn) => RowSyncStore.install(txn));
        if (backfill) await a.update('tb_books', {'file_md5': 'same-content'});
        await a.insert('tb_notes', noteRow(1, 'desktop'));
        await b.insert('tb_notes', noteRow(77, 'phone'));
        await a.insert('tb_reading_time',
            {'book_id': 1, 'date': '2026-09-28', 'reading_time': 30});
        await b.insert('tb_reading_time',
            {'book_id': 77, 'date': '2026-09-28', 'reading_time': 40});
        await b.update('tb_books',
            {'last_read_position': 'chapter9', 'reading_percentage': .8});
        await b.insert('tb_groups',
            {'id': 8, 'name': 'Fiction', 'parent_id': 0, 'is_deleted': 0});
        await b.update('tb_books', {'group_id': 8});
        final tag = await a
            .insert('tb_styles', {'font_size': 1, 'font_family': 'History'});
        await a.insert('tb_styles',
            {'font_size': 2, 'line_height': 1, 'letter_spacing': tag});
        await converge(a, b);
        for (final db in [a, b]) {
          final book =
              (await db.query('tb_books', where: 'is_deleted=0')).single;
          expect(book['id'], db == a ? 1 : 77);
          expect(book['last_read_position'], 'chapter9');
          expect(
              (await db.query('tb_groups',
                      where: 'id=?', whereArgs: [book['group_id']]))
                  .single['name'],
              'Fiction');
          final notes = await db.query('tb_notes');
          expect(notes.map((n) => n['content']).toSet(), {'desktop', 'phone'});
          expect(notes.map((n) => n['book_id']).toSet(), {book['id']});
          expect(
              (await db.rawQuery(
                      'SELECT SUM(reading_time) AS total FROM tb_reading_time'))
                  .single['total'],
              70);
          expect(
              (await db.query('tb_styles', where: 'font_size=2'))
                  .single['line_height'],
              book['id']);
        }
      } finally {
        await a.close();
        await b.close();
      }
    });
  }

  for (final atomic in [true, false]) {
    test(
        'replacement vs independent import converges over sync, atomic=$atomic',
        () async {
      final a = await fixture();
      final b = await fixture(bookId: 77, install: false);
      final temp = await Directory.systemTemp.createTemp('modu-book-alias-');
      try {
        final replacement = {
          'file_md5': 'replacement',
          'file_path': 'file/replacement.epub'
        };
        await a.update('tb_books', replacement);
        await b.update('tb_books', replacement);
        await b.transaction((txn) => RowSyncStore.install(txn));
        final client = MemorySyncClient()..atomic = atomic;
        for (var i = 0; i < 3; i++) {
          for (final db in [a, b]) {
            await RowSyncEngine(
                    store: RowSyncStore(db), client: client, cache: temp)
                .synchronize();
          }
        }
        expect((await a.query('tb_books', where: 'is_deleted=0')).length, 1);
        expect((await b.query('tb_books', where: 'is_deleted=0')).length, 1);
        expect(
            sameSyncRecords(await RowSyncStore(a).snapshot(),
                await RowSyncStore(b).snapshot()),
            isTrue);
      } finally {
        await a.close();
        await b.close();
        await temp.delete(recursive: true);
      }
    });
  }

  test('already duplicated books collapse without losing either notes or files',
      () async {
    final a = await fixture(install: false);
    try {
      await a.insert('tb_books', bookRow(2, md5: 'other-identity'));
      await a.transaction((txn) => RowSyncStore.install(txn));
      await a.insert('tb_notes', noteRow(1, 'first'));
      await a.insert('tb_notes', noteRow(2, 'second'));
      await a.update('tb_books',
          {'file_md5': 'same-content', 'file_path': 'file/same-content.epub'});
      await RowSyncStore(a).merge([]);
      expect(
          (await a.query('tb_books', where: 'is_deleted=0')).single['id'], 1);
      expect((await a.query('tb_books')).length,
          2); // Redundant row is recoverable.
      expect((await a.query('tb_notes')).map((r) => r['book_id']).toSet(), {1});
      expect((await a.query('tb_notes')).length, 2);
      await RowSyncStore(a).merge([]);
      expect((await a.query('tb_books', where: 'is_deleted=0')).length, 1);
      // A stale page/import must not revive the retired local row. Lifecycle
      // tombstones have no local binding, so this also exercises physical
      // row checks instead of relying only on changed sync metadata.
      await a.update('tb_books', {'is_deleted': 0},
          where: 'id=?', whereArgs: [2]);
      await RowSyncStore(a).merge([]);
      expect(
          (await a.query('tb_books', where: 'is_deleted=0')).single['id'], 1);
      expect((await a.query('tb_notes')).length, 2);
    } finally {
      await a.close();
    }
  });

  test('same title/path with conflicting known hashes must not merge',
      () async {
    final a = await fixture();
    final b = await fixture(bookId: 77, install: false);
    try {
      await b.update('tb_books', {'file_md5': 'different-content'});
      await b.transaction((txn) => RowSyncStore.install(txn));
      await converge(a, b);
      expect((await a.query('tb_books', where: 'is_deleted=0')).length, 2);
    } finally {
      await a.close();
      await b.close();
    }
  });

  test('three-device alias chains converge in either merge order', () async {
    final a = await fixture();
    final b = await fixture(bookId: 77, install: false);
    final c = await fixture(bookId: 99, install: false);
    try {
      await b.update('tb_books', {'file_md5': null});
      await c.update('tb_books', {'file_md5': 'older-content'});
      await b.transaction((txn) => RowSyncStore.install(txn));
      await c.transaction((txn) => RowSyncStore.install(txn));
      // C retained its original identity after replacing with A's contents.
      await c.update('tb_books', {'file_md5': 'same-content'});
      final x = await RowSyncStore(a).snapshot();
      final y = await RowSyncStore(b).snapshot();
      final z = await RowSyncStore(c).snapshot();
      final left = mergeSyncRecords(mergeSyncRecords(x, y), z);
      final right = mergeSyncRecords(x, mergeSyncRecords(y, z));
      // Retired metadata is recovery evidence from the moment of merging;
      // its payload can differ by history. The live records must agree, and
      // exchanging both histories must converge including that evidence.
      expect(
          sameSyncRecords(left.where((r) => bookSyncAliasTarget(r) == null),
              right.where((r) => bookSyncAliasTarget(r) == null)),
          isTrue);
      expect(
          sameSyncRecords(
              mergeSyncRecords(left, right), mergeSyncRecords(right, left)),
          isTrue);
      expect(left.where((r) => r.kind == 'book' && !r.deleted).length, 1);
      for (final db in [a, b, c]) {
        await RowSyncStore(db).merge(db == b ? right : left);
        expect((await db.query('tb_books', where: 'is_deleted=0')).length, 1);
      }
      await converge(a, b);
      await converge(b, c);
      await converge(c, a);
    } finally {
      await a.close();
      await b.close();
      await c.close();
    }
  });

  test('durable alias absorbs stale device edits after a later replacement',
      () async {
    final a = await fixture();
    final b = await fixture(bookId: 77, install: false);
    try {
      await b.update('tb_books', {'file_md5': null});
      await b.transaction((txn) => RowSyncStore.install(txn));
      final offline = await RowSyncStore(b).snapshot();
      await converge(a, b);
      await a.update(
          'tb_books', {'file_md5': 'newer', 'file_path': 'file/newer.epub'});
      await RowSyncStore(a).merge(offline);
      final book = (await a.query('tb_books', where: 'is_deleted=0')).single;
      expect(book['file_md5'], 'newer');
      final id = offline.singleWhere((r) => r.kind == 'book').id;
      final note = RowSyncRecord(
          'note', 'offline-note', 9999999999999, 'offline', false, {
        ...noteRow(77, 'offline'),
        'book_id': id,
        'chapter': null,
        'color': null,
        'reader_note': null,
      });
      await RowSyncStore(a).merge([...offline, note]);
      expect((await a.query('tb_notes')).single['book_id'], book['id']);
      expect((await a.query('tb_books', where: 'is_deleted=0')).length, 1);
      await converge(a, b);
    } finally {
      await a.close();
      await b.close();
    }
  });
}
