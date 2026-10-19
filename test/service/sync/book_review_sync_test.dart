import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'row_sync_test.dart' show fixture, bookRow, MemorySyncClient;

Future<Database> reviewFixture(
    {int bookId = 1, bool pathIdentity = false}) async {
  final db = await fixture(bookId: bookId, install: false);
  await db.execute('ALTER TABLE tb_books ADD COLUMN review TEXT');
  if (pathIdentity) await db.update('tb_books', {'file_md5': null});
  await db.transaction(RowSyncStore.install);
  return db;
}

Future<String> review(Database db) async =>
    (await db.query('tb_books', where: 'is_deleted=0')).single['review']
        as String? ??
    '';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  for (final atomic in [true, false]) {
    test(
        'review save, edit and clear round trip through transport (atomic=$atomic)',
        () async {
      final a = await reviewFixture();
      final b = await reviewFixture(bookId: 77);
      final cache = await Directory.systemTemp.createTemp('review-sync-');
      final client = MemorySyncClient()..atomic = atomic;
      Future<void> sync(Database db) =>
          RowSyncEngine(store: RowSyncStore(db), client: client, cache: cache)
              .synchronize();
      try {
        expect(
            (await RowSyncStore(b).snapshot()).where((r) => r.kind == 'review'),
            isEmpty);
        await a.update('tb_books', {'review': '# 书评\n中文 **Markdown** 😀'});
        await sync(a);
        await sync(b);
        expect(await review(b), '# 书评\n中文 **Markdown** 😀');
        await b.update('tb_books', {'review': 'Edited on another platform'});
        await sync(b);
        await sync(a);
        expect(await review(a), 'Edited on another platform');
        await a.update('tb_books', {'review': ''});
        await sync(a);
        await sync(b);
        await sync(a);
        expect(await review(b), '');
        expect(await b.query('tb_books'), hasLength(1));
        expect(
            sameSyncRecords(await RowSyncStore(a).snapshot(),
                await RowSyncStore(b).snapshot()),
            isTrue);
      } finally {
        await a.close();
        await b.close();
        await cache.delete(recursive: true);
      }
    });
  }

  test('unrelated metadata and position edits never overwrite a review',
      () async {
    final a = await reviewFixture();
    final b = await reviewFixture(bookId: 77);
    try {
      await a.update('tb_books', {'review': 'keep this'});
      await b.update('tb_books', {
        'title': 'New title',
        'last_read_position': 'chapter-2',
        'reading_percentage': .5
      });
      await RowSyncStore(a).merge(await RowSyncStore(b).snapshot());
      await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
      expect(await review(a), 'keep this');
      expect(await review(b), 'keep this');
      final before = (await RowSyncStore(b).snapshot())
          .singleWhere((r) => r.kind == 'review');
      await b.update('tb_books',
          {'review': 'keep this', 'update_time': '2026-10-19T12:00:00Z'});
      final after = (await RowSyncStore(b).snapshot())
          .singleWhere((r) => r.kind == 'review');
      expect(after.toMap(), before.toMap());
      await b.update('tb_books', {'review': null});
      await RowSyncStore(a).merge(await RowSyncStore(b).snapshot());
      expect(await review(a), '');
    } finally {
      await a.close();
      await b.close();
    }
  });

  test('existing local reviews are backfilled once; blank books are not edits',
      () async {
    final db = await fixture();
    try {
      await db.execute('ALTER TABLE tb_books ADD COLUMN review TEXT');
      await db.update('tb_books',
          {'review': 'pre-upgrade', 'update_time': '2026-10-18T10:00:00Z'});
      await db.insert('tb_books', bookRow(2, md5: 'second'));
      await db.transaction(RowSyncStore.ensureReviews);
      final before = await RowSyncStore(db).snapshot();
      expect(before.where((r) => r.kind == 'review'), hasLength(1));
      expect(
          before.singleWhere((r) => r.kind == 'review').clock,
          greaterThan(before
              .singleWhere(
                  (r) => r.kind == 'book' && r.id == 'md5:same-content')
              .clock));
      await db.transaction(RowSyncStore.ensureReviews);
      expect(
          sameSyncRecords(before, await RowSyncStore(db).snapshot()), isTrue);
      await db.insert(
          'tb_books', {...bookRow(3, md5: 'third'), 'review': 'imported'});
      expect(
          (await RowSyncStore(db).snapshot()).where((r) => r.kind == 'review'),
          hasLength(2));
    } finally {
      await db.close();
    }
  });

  test(
      'same-book aliases retain reviews and allow subsequent edits and clearing',
      () async {
    final a = await reviewFixture();
    final b = await reviewFixture(bookId: 77, pathIdentity: true);
    try {
      await b.update('tb_books', {'review': 'written before checksum'});
      for (var i = 0; i < 3; i++) {
        await RowSyncStore(a).merge(await RowSyncStore(b).snapshot());
        await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
      }
      expect(await review(a), 'written before checksum');
      expect(await review(b), 'written before checksum');
      await b.update('tb_books', {'review': 'after canonicalization'},
          where: 'is_deleted=0');
      await RowSyncStore(a).merge(await RowSyncStore(b).snapshot());
      expect(await review(a), 'after canonicalization');
      await a.update('tb_books', {'review': ''}, where: 'is_deleted=0');
      await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
      expect(await review(b), '');
      expect(await b.query('tb_books', where: 'is_deleted=0'), hasLength(1));
    } finally {
      await a.close();
      await b.close();
    }
  });

  test('concurrent review edits converge; empty explicit edits can win',
      () async {
    final db = await reviewFixture();
    try {
      final base = await RowSyncStore(db).snapshot();
      final book = base.singleWhere((r) => r.kind == 'book');
      final text = RowSyncRecord('review', book.id, book.clock + 1, 'a', false,
          {'review': 'offline edit'});
      final clear = RowSyncRecord(
          'review', book.id, book.clock + 1, 'z', false, {'review': ''});
      expect(
          sameSyncRecords(mergeSyncRecords([...base, text], [clear]),
              mergeSyncRecords([...base, clear], [text])),
          isTrue);
      await RowSyncStore(db).merge([...base, text, clear]);
      expect(await review(db), '');
      // A review tombstone must never physically delete the book row.
      await RowSyncStore(db).merge([
        RowSyncRecord('review', book.id, clear.clock + 1, 'deleted', true, {})
      ]);
      expect(await db.query('tb_books'), hasLength(1));
      await db.update('tb_books', {'review': 'write again'});
      expect(
          (await RowSyncStore(db).snapshot())
              .singleWhere((r) => r.kind == 'review')
              .deleted,
          isFalse);
    } finally {
      await db.close();
    }
  });

  test('invalid review payload fails without changing the library', () async {
    final db = await reviewFixture();
    try {
      await db.update('tb_books', {'review': 'protected'});
      final before = await RowSyncStore(db).snapshot();
      final book = before.singleWhere((r) => r.kind == 'book');
      await expectLater(
          RowSyncStore(db).merge([
            RowSyncRecord(
                'review', book.id, book.clock + 1, 'bad', false, {'review': 7})
          ]),
          throwsFormatException);
      expect(await review(db), 'protected');
    } finally {
      await db.close();
    }
  });

  test('upgrading a v8 archive with no review preserves the local review',
      () async {
    final old = await fixture();
    final current = await reviewFixture();
    final cache = await Directory.systemTemp.createTemp('review-v8-');
    try {
      await current.update('tb_books', {'review': 'local before upgrade'});
      final archive = '${cache.path}/database8.db';
      await RowSyncArchive.write(archive, await RowSyncStore(old).snapshot());
      final transport = await databaseFactoryFfi.openDatabase(archive);
      await transport.setVersion(8);
      await transport.close();
      await RowSyncStore(current).merge(await RowSyncArchive.read(archive));
      expect(await review(current), 'local before upgrade');
    } finally {
      await old.close();
      await current.close();
      await cache.delete(recursive: true);
    }
  });
}
