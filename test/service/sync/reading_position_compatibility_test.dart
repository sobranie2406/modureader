import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/utils/reading_progress.dart';
import 'row_sync_test.dart' show fixture, MemorySyncClient, bookRow, noteRow;

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  RowSyncRecord position(Object? location, Object? progress,
          {int clock = 10}) =>
      RowSyncRecord('position', 'md5:same-content', clock, 'original', false,
          {'last_read_position': location, 'reading_percentage': progress});

  test(
      'normalization is idempotent, bounded and preserves exact locations and operation metadata',
      () {
    for (final pair in <List<num?>>[
      [null, 0],
      [-0.01, 0],
      [0, 0],
      [.42, .42],
      [1, 1],
      [1.02, 1],
      [double.infinity, 0],
      [double.negativeInfinity, 0],
      [double.nan, 0],
    ]) {
      final original = position('epubcfi(/6/2!/4/2:0)', pair[0]);
      final normalized = normalizeSyncReadingPosition(original);
      RowSyncStore.validate(normalized);
      expect(normalized.data['reading_percentage'], pair[1]);
      expect(normalized.data['last_read_position'],
          original.data['last_read_position']);
      expect(normalized.id, original.id);
      expect(normalized.clock, original.clock);
      expect(normalized.revision, original.revision);
      expect(
          normalizeSyncReadingPosition(normalized).toMap(), normalized.toMap());
      expect(normalizeReadingProgress(pair[0]), pair[1]);
    }
  });

  test(
      'unknown unread positions cannot overwrite real reads; reading backwards still wins by time',
      () {
    for (final empty in [null, '']) {
      final unknown = position(empty, null, clock: 999);
      final read = position('chapter-last', .9, clock: 20);
      expect(mergeSyncRecords([unknown], [read]).single.toMap(), read.toMap());
      expect(mergeSyncRecords([read], [unknown]).single.toMap(), read.toMap());
    }
    final earlier = position('chapter-last', .9, clock: 20);
    final movedBack = position('chapter-first', 0.0, clock: 30);
    expect(mergeSyncRecords([earlier], [movedBack]).single.toMap(),
        movedBack.toMap());
    expect(mergeSyncRecords([movedBack], [earlier]).single.toMap(),
        movedBack.toMap());
  });

  test(
      'unknown positions, real reads and tombstones converge across three devices',
      () {
    final records = [
      position(null, null, clock: 999),
      position('chapter', .5, clock: 20),
      const RowSyncRecord(
          'position', 'md5:same-content', 30, 'deleted', true, {}),
    ];
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        if (i == j) continue;
        final k = 3 - i - j;
        final left = mergeSyncRecords(
            mergeSyncRecords([records[i]], [records[j]]), [records[k]]);
        final right = mergeSyncRecords(
            [records[i]], mergeSyncRecords([records[j]], [records[k]]));
        expect(left.single.toMap(), records[2].toMap());
        expect(right.single.toMap(), records[2].toMap());
      }
    }
  });

  test(
      'wrong types, missing keys, extra fields and unsafe paths still fail validation',
      () {
    for (final bad in [
      position(123, .5),
      position('chapter', '50%'),
      position('chapter', {}),
      const RowSyncRecord('position', 'p', 1, 'r', false, {}),
      const RowSyncRecord('position', 'p', 1, 'r', false, {
        'last_read_position': null,
        'reading_percentage': null,
        'unexpected': 'value'
      }),
    ]) {
      expect(() => RowSyncStore.validate(normalizeSyncReadingPosition(bad)),
          throwsFormatException);
    }
    final deleted = RowSyncRecord('position', 'p', 1, 'r', true, {});
    expect(identical(normalizeSyncReadingPosition(deleted), deleted), isTrue);
    final book = RowSyncRecord('book', 'p', 1, 'r', false, {
      ...bookRow(1)
        ..remove('id')
        ..remove('last_read_position')
        ..remove('reading_percentage')
        ..remove('is_deleted'),
      'group_id': 'root',
      'description': null,
      'rating': null,
      'file_path': '../private',
    });
    expect(() => RowSyncStore.validate(normalizeSyncReadingPosition(book)),
        throwsFormatException);
  });

  test(
      'existing version8 archives normalize positions at the read boundary without rewriting the source',
      () async {
    final db = await fixture();
    final temp = await Directory.systemTemp.createTemp('modu-v8-position-');
    try {
      final file = File('${temp.path}/archive.db');
      await RowSyncArchive.write(file.path, await RowSyncStore(db).snapshot());
      final archive = await databaseFactory.openDatabase(file.path,
          options: OpenDatabaseOptions(singleInstance: false));
      await archive.update(syncRecordsTable,
          {'payload': '{"last_read_position":null,"reading_percentage":null}'},
          where: 'kind=?', whereArgs: ['position']);
      await archive.close();
      final original = await file.readAsBytes();
      final records = await RowSyncArchive.read(file.path);
      expect(records.singleWhere((r) => r.kind == 'position').data,
          {'last_read_position': '', 'reading_percentage': 0.0});
      expect(await file.readAsBytes(), original);
    } finally {
      await db.close();
      await temp.delete(recursive: true);
    }
  });

  test('non-finite local progress is normalized before JSON snapshot encoding',
      () async {
    final db = await fixture();
    try {
      await db.update(
          'tb_books',
          {
            'last_read_position': 'keep-location',
            'reading_percentage': double.infinity
          },
          where: 'id=?',
          whereArgs: [1]);
      final record = (await RowSyncStore(db).snapshot())
          .singleWhere((r) => r.kind == 'position');
      expect(record.data,
          {'last_read_position': 'keep-location', 'reading_percentage': 0.0});
      RowSyncStore.validate(record);
    } finally {
      await db.close();
    }
  });

  test(
      'nullable unread rows and cached snapshots publish without blocking books or notes',
      () async {
    final a = await fixture();
    final b = await fixture(bookId: 77);
    final temp = await Directory.systemTemp.createTemp('modu-null-position-');
    try {
      await a.insert('tb_books', {
        ...bookRow(2, md5: 'unread'),
        'last_read_position': null,
        'reading_percentage': null
      });
      await a.insert('tb_notes', noteRow(1, 'local note'));
      final store = RowSyncStore(a);
      // The failed older client may already have cached the nullable payload.
      await store.snapshot();
      await a.update(
          syncRecordsTable,
          {
            'payload': '{"last_read_position":null,"reading_percentage":null}',
            'dirty': 0,
          },
          where: 'kind=? AND local_id=?',
          whereArgs: ['position', 2]);
      final before = (await a.query(syncRecordsTable,
              where: 'kind=? AND local_id=?', whereArgs: ['position', 2]))
          .single;
      final client = MemorySyncClient();
      final engine = RowSyncEngine(store: store, client: client, cache: temp);
      expect(await engine.synchronize(), RowSyncOutcome.published);
      final cloud = File('${temp.path}/cloud.db');
      await cloud.writeAsBytes(client.files[RowSyncEngine.remotePath]!);
      final records = await RowSyncArchive.read(cloud.path);
      final unread = records
          .singleWhere((r) => r.kind == 'position' && r.id == 'md5:unread');
      expect(
          unread.data, {'last_read_position': '', 'reading_percentage': 0.0});
      expect(unread.clock, before['clock']);
      expect(unread.revision, before['revision']);
      await RowSyncStore(b).merge(records);
      expect((await b.query('tb_books')).length, 2);
      expect((await b.query('tb_notes')).single['content'], 'local note');
      final writes = client.writes;
      expect(await engine.synchronize(), RowSyncOutcome.unchanged);
      expect(client.writes, writes);
    } finally {
      await a.close();
      await b.close();
      await temp.delete(recursive: true);
    }
  });

  test(
      'renamed modu legacy database migrates nullable and out-of-range positions without modifying database7',
      () async {
    final temp = await Directory.systemTemp.createTemp('modu-legacy-position-');
    final local = await fixture();
    try {
      final old = await fixture(install: false, path: '${temp.path}/legacy.db');
      await old.insert('tb_books', {
        ...bookRow(2, md5: 'unread'),
        'last_read_position': null,
        'reading_percentage': null
      });
      await old.insert('tb_books', {
        ...bookRow(3, md5: 'overflow'),
        'last_read_position': 'chapter-last',
        'reading_percentage': 1.02
      });
      await old.insert('tb_notes', noteRow(1, 'old note'));
      await old.close();
      final bytes = await File('${temp.path}/legacy.db').readAsBytes();
      final client = MemorySyncClient()..files['modu/database7.db'] = bytes;
      final engine = RowSyncEngine(
          store: RowSyncStore(local), client: client, cache: temp);
      expect(await engine.synchronize(), RowSyncOutcome.published);
      expect(client.files['modu/database7.db'], bytes);
      expect((await local.query('tb_books')).length, 3);
      final overflow = (await local
              .query('tb_books', where: 'file_md5=?', whereArgs: ['overflow']))
          .single;
      expect(overflow['last_read_position'], 'chapter-last');
      expect(overflow['reading_percentage'], 1.0);
      expect((await local.query('tb_notes')).single['content'], 'old note');
      expect(await engine.synchronize(), RowSyncOutcome.unchanged);
    } finally {
      await local.close();
      await temp.delete(recursive: true);
    }
  });
}
