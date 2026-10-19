import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/dao/reading_round.dart';
import 'package:anx_reader/models/reading_round.dart';
import 'package:anx_reader/service/sync/reading_round_sync.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'row_sync_test.dart' show MemorySyncClient, fixture;

Map<String, Object?> roundRow(
  int bookId,
  int number, {
  String status = ReadingRound.statusReading,
  double start = 0,
  double end = 0,
  String? endPosition,
  String? endTime,
}) {
  final now = DateTime.now().toIso8601String();
  return {
    'book_id': bookId,
    'round_number': number,
    'status': status,
    'start_time': now,
    'end_time': endTime,
    'start_percentage': start,
    'end_percentage': end,
    'end_position': endPosition,
    'total_reading_time': 0,
    'create_time': now,
    'update_time': now,
  };
}

Map<String, Object?> timeRow(int bookId, int seconds,
        {int round = 1, String date = '2026-10-01'}) =>
    {'book_id': bookId, 'date': date, 'reading_time': seconds, 'round': round};

RowSyncRecord roundRecord(int clock, String status,
        {double end = 0, String? endTime, String? endPosition}) =>
    RowSyncRecord(
      'round',
      'book-x:r1',
      clock,
      'rev-$clock',
      false,
      {
        'book_id': 'book-x',
        'round_number': 1,
        'status': status,
        'start_time': '2026-10-01T00:00:00',
        'end_time': endTime,
        'start_percentage': 0,
        'end_percentage': end,
        'end_position': endPosition,
      },
    );

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<void> converge(Database a, Database b) async {
    final sa = RowSyncStore(a);
    final sb = RowSyncStore(b);
    for (var i = 0; i < 3; i++) {
      await sa.merge(await sb.snapshot());
      await sb.merge(await sa.snapshot());
      await ReadingRoundSync.reconcile(a);
      await ReadingRoundSync.reconcile(b);
    }
  }

  Future<RowSyncOutcome> syncDevice(
    Database db,
    MemorySyncClient client,
    Directory cache, {
    Directory? durable,
  }) {
    return RowSyncEngine(
      store: RowSyncStore(db),
      client: client,
      cache: cache,
      durableDirectory: durable,
      afterMerge: () => ReadingRoundSync.reconcile(db),
    ).synchronize();
  }

  test('v8 archive records gain round=1 and are republished as v9', () async {
    final temp = await Directory.systemTemp.createTemp('round-v8-');
    try {
      final path = '${temp.path}/v8.db';
      final db = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(singleInstance: false));
      await db
          .execute('CREATE TABLE modu_sync_manifest (format INTEGER NOT NULL)');
      await db.insert('modu_sync_manifest', {'format': 1});
      await db.execute(
          'CREATE TABLE modu_sync_records (kind TEXT NOT NULL, sync_id TEXT NOT NULL, '
          'clock INTEGER NOT NULL, revision TEXT NOT NULL, deleted INTEGER NOT NULL, '
          'payload TEXT NOT NULL, narration TEXT, PRIMARY KEY(kind,sync_id))');
      await db.insert('modu_sync_records', {
        'kind': 'time',
        'sync_id': 'legacy:one',
        'clock': 1,
        'revision': 'legacy',
        'deleted': 0,
        'payload': jsonEncode({
          'book_id': 'book/x',
          'date': '2026-10-01',
          'reading_time': 60,
        }),
      });
      await db.setVersion(8);
      await db.close();

      final records = await RowSyncArchive.read(path);
      expect(records, hasLength(1));
      expect(records.single.data['round'], 1);
      expect(await RowSyncArchive.versionOf(path), 8);

      final upgraded = '${temp.path}/v9.db';
      await RowSyncArchive.write(upgraded, records);
      expect(await RowSyncArchive.versionOf(upgraded), 9);
      expect((await RowSyncArchive.read(upgraded)).single.data['round'], 1);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('round conflicts resolve by operation clock', () {
    final reading = roundRecord(100, ReadingRound.statusReading);
    final finished = roundRecord(200, ReadingRound.statusFinished,
        end: .98, endTime: '2026-10-02T00:00:00', endPosition: 'cfi-98');
    final laterCancel = roundRecord(300, ReadingRound.statusCancelled);
    final laterFinish = roundRecord(400, ReadingRound.statusFinished,
        end: 1, endTime: '2026-10-03T00:00:00', endPosition: 'cfi-end');

    expect(mergeSyncRecords([reading], [finished]).single.data['status'],
        ReadingRound.statusFinished);
    expect(mergeSyncRecords([finished], [laterCancel]).single.data['status'],
        ReadingRound.statusCancelled);
    expect(mergeSyncRecords([laterCancel], [laterFinish]).single.data['status'],
        ReadingRound.statusFinished);
    expect(
        mergeSyncRecords([finished], [laterFinish]).single.data['end_position'],
        'cfi-end');
  });

  test('two devices finishing the same round converge to one row', () async {
    final a = await fixture();
    final b = await fixture(bookId: 77);
    try {
      await a.insert(ReadingRoundDao.table, roundRow(1, 1));
      await b.insert(ReadingRoundDao.table, roundRow(77, 1));
      await a.update(
          ReadingRoundDao.table,
          {
            'status': ReadingRound.statusFinished,
            'end_percentage': .98,
            'end_time': '2026-10-02T00:00:00',
          },
          where: 'book_id = ? AND round_number = ?',
          whereArgs: [1, 1]);
      // Separate databases can tick in the same millisecond. Make B's later
      // operation explicit rather than depending on wall-clock execution speed.
      final first = (await RowSyncStore(a).snapshot())
          .singleWhere((r) => r.kind == 'round');
      await b.rawUpdate(
          'UPDATE modu_sync_control SET clock=MAX(clock,?)', [first.clock]);
      await b.update(
          ReadingRoundDao.table,
          {
            'status': ReadingRound.statusFinished,
            'end_percentage': 1.0,
            'end_time': '2026-10-03T00:00:00',
          },
          where: 'book_id = ? AND round_number = ?',
          whereArgs: [77, 1]);
      await converge(a, b);
      for (final db in [a, b]) {
        final rows = await db.query(ReadingRoundDao.table);
        expect(rows, hasLength(1));
        expect(rows.single['round_number'], 1);
        expect(rows.single['status'], ReadingRound.statusFinished);
        expect(rows.single['end_percentage'], 1.0);
      }
    } finally {
      await a.close();
      await b.close();
    }
  });

  test('same-clock round conflicts converge by revision, not finish percentage',
      () {
    final data = roundRecord(100, ReadingRound.statusFinished, end: 1).data;
    final a = RowSyncRecord('round', 'book-x:r1', 100, 'a', false, data);
    final b = RowSyncRecord('round', 'book-x:r1', 100, 'z', false,
        {...data, 'end_percentage': .98});
    final ab = mergeSyncRecords([a], [b]);
    final ba = mergeSyncRecords([b], [a]);
    expect(sameSyncRecords(ab, ba), isTrue);
    expect(ab.single.data['end_percentage'], .98);
  });

  test('undo (cancel) versus continue reading re-attributes the time',
      () async {
    final a = await fixture();
    final b = await fixture(bookId: 77);
    try {
      // Both devices have round 1 finished and round 2 in progress.
      await a.insert(ReadingRoundDao.table,
          roundRow(1, 1, status: ReadingRound.statusFinished, end: .98));
      await a.insert(ReadingRoundDao.table, roundRow(1, 2));
      await b.insert(ReadingRoundDao.table,
          roundRow(77, 1, status: ReadingRound.statusFinished, end: .98));
      await b.insert(ReadingRoundDao.table, roundRow(77, 2));
      await a.insert('tb_reading_time', timeRow(1, 60, round: 1));
      await b.insert('tb_reading_time', timeRow(77, 30, round: 2));
      await a.update('tb_books', {'current_round': 2}, where: 'id = 1');
      await b.update('tb_books', {'current_round': 2}, where: 'id = 77');
      await converge(a, b);

      // A undoes round 2; B is offline and keeps reading round 2.
      await a.update(
          ReadingRoundDao.table,
          {
            'status': ReadingRound.statusCancelled,
            'end_time': '2026-10-05T00:00:00',
          },
          where: 'book_id = ? AND round_number = ?',
          whereArgs: [1, 2]);
      await a.update(
          ReadingRoundDao.table, {'status': ReadingRound.statusReading},
          where: 'book_id = ? AND round_number = ?', whereArgs: [1, 1]);
      await a.update('tb_books', {'current_round': 1}, where: 'id = 1');
      await b.insert('tb_reading_time', timeRow(77, 40, round: 2));

      await converge(a, b);
      for (final db in [a, b]) {
        final rows =
            await db.query(ReadingRoundDao.table, orderBy: 'round_number');
        expect(rows.first['status'], ReadingRound.statusReading);
        expect(rows[1]['status'], ReadingRound.statusCancelled);
        final times = await db.query('tb_reading_time');
        expect(times.map((row) => row['round']).toSet(), {1});
        expect(
            times.fold<int>(
                0, (sum, row) => sum + (row['reading_time'] as int)),
            60 + 30 + 40);
        final book = await db.query('tb_books', where: 'is_deleted = 0');
        expect(book.single['current_round'], 1);
      }
    } finally {
      await a.close();
      await b.close();
    }
  });

  test('reconcile derives current_round and per-round totals', () async {
    final db = await fixture();
    try {
      await db.insert(ReadingRoundDao.table,
          roundRow(1, 1, status: ReadingRound.statusFinished, end: .9));
      await db.insert(ReadingRoundDao.table,
          roundRow(1, 2, status: ReadingRound.statusCancelled));
      await db.insert(ReadingRoundDao.table, roundRow(1, 3));
      await db.insert('tb_reading_time', timeRow(1, 60, round: 1));
      await db.insert('tb_reading_time', timeRow(1, 30, round: 2));
      await db.insert('tb_reading_time', timeRow(1, 20, round: 3));
      await db.update('tb_books', {'current_round': 3}, where: 'id = 1');

      await ReadingRoundSync.reconcile(db);

      final times = await db.query('tb_reading_time', orderBy: 'id');
      expect(times.map((row) => row['round']), [1, 1, 3]);
      final rounds =
          await db.query(ReadingRoundDao.table, orderBy: 'round_number');
      expect(rounds.map((row) => row['round_number']), [1, 2, 3]);
      expect(rounds[0]['total_reading_time'], 90);
      expect(rounds[2]['total_reading_time'], 20);
      final book = await db.query('tb_books', where: 'id = 1');
      expect(book.single['current_round'], 3);
    } finally {
      await db.close();
    }
  });

  test('ensureRounds backfills round identities and time payloads', () async {
    final db = await fixture();
    try {
      // Simulate a database created before v9 round sync existed.
      for (final suffix in ['insert', 'update', 'delete']) {
        await db.execute('DROP TRIGGER IF EXISTS modu_round_$suffix');
      }
      await db.delete('modu_sync_records', where: "kind = 'round'");
      await db.insert(ReadingRoundDao.table, roundRow(1, 1));
      await db.insert('tb_reading_time', timeRow(1, 45, round: 1));

      await RowSyncStore.ensureRounds(db);

      final rounds =
          await db.query('modu_sync_records', where: "kind = 'round'");
      expect(rounds, hasLength(1));
      expect(rounds.single['sync_id'], endsWith(':r1'));
      expect(rounds.single['dirty'], 1);
      final time =
          (await db.query('modu_sync_records', where: "kind = 'time'")).single;
      final payload =
          jsonDecode(time['payload'] as String) as Map<String, dynamic>;
      expect(payload['round'], 1);
      final trigger = await db.rawQuery(
          "SELECT sql FROM sqlite_master WHERE type='trigger' AND name='modu_time_update'");
      expect(trigger.single['sql'], contains('NEW.round'));
    } finally {
      await db.close();
    }
  });

  test('future archive version fails before any write or asset upload',
      () async {
    final temp = await Directory.systemTemp.createTemp('round-future-');
    final seed = await fixture();
    final local = await fixture(bookId: 77);
    try {
      final path = '${temp.path}/future.db';
      await RowSyncArchive.write(path, await RowSyncStore(seed).snapshot());
      final raw = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(singleInstance: false));
      await raw.setVersion(10);
      await raw.close();
      final client = MemorySyncClient()
        ..files['modu/database8.db'] = await File(path).readAsBytes();
      var assetsTouched = false;

      await expectLater(
        RowSyncEngine(
          store: RowSyncStore(seed),
          client: client,
          cache: temp,
          beforePublish: () async => assetsTouched = true,
        ).synchronize(),
        throwsA(isA<FormatException>()),
      );
      expect(client.writes, 0);
      expect(assetsTouched, isFalse);
      expect((await local.query('tb_books')), isNotEmpty);
    } finally {
      await seed.close();
      await local.close();
      await temp.delete(recursive: true);
    }
  });

  test('v8 cloud migrates to v9 and keeps a byte-exact backup', () async {
    final temp = await Directory.systemTemp.createTemp('round-migrate-');
    final seed = await fixture();
    final local = await fixture(bookId: 77);
    final durable = await Directory('${temp.path}/durable').create();
    try {
      await seed.insert('tb_reading_time', timeRow(1, 60, round: 1));
      final records = await RowSyncStore(seed).snapshot();
      final cloud = '${temp.path}/cloud.db';
      await RowSyncArchive.write(cloud, records);
      // Turn the archive into a v8 one: no round records and no time.round.
      final raw = await databaseFactoryFfi.openDatabase(cloud,
          options: OpenDatabaseOptions(singleInstance: false));
      await raw.delete('modu_sync_records', where: "kind = 'round'");
      for (final row
          in await raw.query('modu_sync_records', where: "kind = 'time'")) {
        final payload = jsonDecode(row['payload'] as String)
            as Map<String, dynamic>
          ..remove('round');
        await raw.update('modu_sync_records', {'payload': jsonEncode(payload)},
            where: 'sync_id = ?', whereArgs: [row['sync_id']]);
      }
      await raw.setVersion(8);
      await raw.close();

      final client = MemorySyncClient()
        ..files['modu/database8.db'] = await File(cloud).readAsBytes();
      await local.insert(ReadingRoundDao.table, roundRow(77, 1));
      await syncDevice(local, client, temp, durable: durable);

      final upgraded = '${temp.path}/upgraded.db';
      await File(upgraded).writeAsBytes(client.files['modu/database8.db']!);
      expect(await RowSyncArchive.versionOf(upgraded), 9);
      final migrated = await RowSyncArchive.read(upgraded);
      expect(migrated.map((record) => record.kind), contains('round'));
      final time = migrated.singleWhere((record) => record.kind == 'time');
      expect(time.data['round'], 1);
      final backups = await durable
          .list()
          .where((entry) => entry.path.contains('sync-v8-backup-'))
          .toList();
      expect(backups, isNotEmpty);
    } finally {
      await seed.close();
      await local.close();
      await temp.delete(recursive: true);
    }
  });

  test('rounds and round attribution survive a two-device sync', () async {
    final a = await fixture();
    final b = await fixture(bookId: 77);
    final tempA = await Directory.systemTemp.createTemp('round-a-');
    final tempB = await Directory.systemTemp.createTemp('round-b-');
    try {
      final client = MemorySyncClient();
      await a.insert(ReadingRoundDao.table, roundRow(1, 1));
      await a.insert('tb_reading_time', timeRow(1, 60, round: 1));
      await syncDevice(a, client, tempA);
      await syncDevice(b, client, tempB);

      // A finishes round 1 and starts round 2.
      await a.update(
          ReadingRoundDao.table,
          {
            'status': ReadingRound.statusFinished,
            'end_percentage': .98,
            'end_time': '2026-10-02T00:00:00',
          },
          where: 'book_id = ? AND round_number = ?',
          whereArgs: [1, 1]);
      await a.insert(ReadingRoundDao.table, roundRow(1, 2));
      await a.update('tb_books', {'current_round': 2}, where: 'id = 1');
      await syncDevice(a, client, tempA);
      await syncDevice(b, client, tempB);

      final bBook = await b.query('tb_books', where: 'id = 77');
      expect(bBook.single['current_round'], 2);

      // B continues reading; the session must be attributed to round 2.
      await b.insert('tb_reading_time', timeRow(77, 30, round: 2));
      await syncDevice(b, client, tempB);
      await syncDevice(a, client, tempA);

      final round2 = await a
          .rawQuery('SELECT SUM(reading_time) AS total FROM tb_reading_time '
              'WHERE book_id = 1 AND round = 2');
      expect(round2.single['total'], 30);
      final aBook = await a.query('tb_books', where: 'id = 1');
      expect(aBook.single['current_round'], 2);
    } finally {
      await a.close();
      await b.close();
      await tempA.delete(recursive: true);
      await tempB.delete(recursive: true);
    }
  });
}
