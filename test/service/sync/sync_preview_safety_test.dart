import 'dart:io';

import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/sync_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'row_sync_test.dart' show MemorySyncClient, fixture, noteRow;
import 'immutable_sync_log_test.dart' show ConcurrentLogClient;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database a;
  late Database b;
  late Directory temp;

  setUp(() async {
    a = await fixture(install: false);
    b = await fixture(bookId: 77, install: false);
    await a.insert('tb_notes', noteRow(1, 'shared'));
    await b.insert('tb_notes', noteRow(77, 'shared'));
    await a.transaction((txn) => RowSyncStore.install(txn));
    await b.transaction((txn) => RowSyncStore.install(txn));
    temp = await Directory.systemTemp.createTemp('pr71-review-');
  });

  tearDown(() async {
    await a.close();
    await b.close();
    await temp.delete(recursive: true);
  });

  test('cancel must not publish a previously failed pending batch', () async {
    final client = MemorySyncClient()..atomic = false;
    client.beforeLogWrite = () async => throw StateError('offline');
    await expectLater(
      RowSyncEngine(store: RowSyncStore(a), client: client, cache: temp)
          .synchronize(),
      throwsStateError,
    );
    expect(client.files, isEmpty);
    client.beforeLogWrite = null;
    await expectLater(
      RowSyncEngine(
        store: RowSyncStore(a),
        client: client,
        cache: temp,
        onPreview: (_) async => const SyncPreviewDecision.cancel(),
      ).synchronize(),
      throwsA(isA<SyncPreviewCancelled>()),
    );
    expect(client.files.keys, isEmpty,
        reason: 'The cancelled attempt must leave cloud data untouched');
  });

  test('preferLocal must survive a remote clock ahead of the device', () async {
    await a.update('tb_notes', {'content': 'chosen local'});
    final future = DateTime.now().millisecondsSinceEpoch + 3600000;
    await b.update('modu_sync_control', {'clock': future});
    await b.update('tb_notes', {'content': 'remote ahead'});
    await RowSyncStore(a).merge(await RowSyncStore(b).snapshot(),
        resolution: SyncConflictResolution.preferLocal);
    expect((await a.query('tb_notes')).single['content'], 'chosen local');
    await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
    expect((await b.query('tb_notes')).single['content'], 'chosen local');
  });

  test(
      'partial pending uploads remain unchanged on cancel and recover on confirm',
      () async {
    final client = ConcurrentLogClient()
      ..atomic = false
      ..concurrent = false
      ..corrupt = true;
    await expectLater(
        RowSyncEngine(store: RowSyncStore(a), client: client, cache: temp)
            .synchronize(),
        throwsFormatException);
    final before = {
      for (final entry in client.files.entries)
        entry.key: List<int>.of(entry.value)
    };
    var confirmed = false;
    client.corrupt = false;
    client.beforeLogWrite = () async {
      expect(confirmed, isTrue);
    };
    await expectLater(
        RowSyncEngine(
          store: RowSyncStore(a),
          client: client,
          cache: temp,
          onPreview: (_) async => const SyncPreviewDecision.cancel(),
        ).synchronize(),
        throwsA(isA<SyncPreviewCancelled>()));
    expect(client.files, before);
    await RowSyncEngine(
      store: RowSyncStore(a),
      client: client,
      cache: temp,
      onPreview: (_) async {
        confirmed = true;
        return const SyncPreviewDecision(SyncConflictResolution.newest);
      },
    ).synchronize();
    expect(client.files, isNot(before));
    await RowSyncEngine(store: RowSyncStore(b), client: client, cache: temp)
        .synchronize();
    expect(
        sameSyncRecords(
            await RowSyncStore(a).snapshot(), await RowSyncStore(b).snapshot()),
        isTrue);
  });

  test(
      'preview includes durable pending records absent from the current database',
      () async {
    await a.insert('tb_notes', noteRow(1, 'only-in-pending'));
    final client = MemorySyncClient()..atomic = false;
    client.beforeLogWrite = () async => throw StateError('offline');
    await expectLater(
        RowSyncEngine(store: RowSyncStore(a), client: client, cache: temp)
            .synchronize(),
        throwsStateError);
    client.beforeLogWrite = null;
    await RowSyncEngine(
      store: RowSyncStore(b),
      client: client,
      cache: temp,
      onPreview: (context) async {
        expect(buildSyncPreview(context: context).noteDelta, 1);
        return const SyncPreviewDecision(SyncConflictResolution.newest);
      },
    ).synchronize();
    expect((await b.query('tb_notes')).map((row) => row['content']),
        contains('only-in-pending'));
  });

  test('disabled preview keeps asset verification ahead of pending publication',
      () async {
    final client = MemorySyncClient()..atomic = false;
    client.beforeLogWrite = () async => throw StateError('offline');
    await expectLater(
        RowSyncEngine(store: RowSyncStore(a), client: client, cache: temp)
            .synchronize(),
        throwsStateError);
    client.beforeLogWrite = null;
    await expectLater(
        RowSyncEngine(
          store: RowSyncStore(a),
          client: client,
          cache: temp,
          beforePublish: () async => throw StateError('asset failure'),
        ).synchronize(),
        throwsStateError);
    expect(client.files, isEmpty);
  });

  test('explicitly keeping an empty position survives a later normal merge',
      () async {
    await a.update(
        'tb_books', {'last_read_position': '', 'reading_percentage': 0.0});
    await b.update('tb_books',
        {'last_read_position': 'chapter8', 'reading_percentage': 0.8});
    await RowSyncStore(a).merge(await RowSyncStore(b).snapshot(),
        resolution: SyncConflictResolution.preferLocal);
    await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
    expect((await b.query('tb_books')).single['reading_percentage'], 0.0);
  });

  for (final atomic in [true, false]) {
    test('forced cloud choice converges through atomic=$atomic transport',
        () async {
      final client = MemorySyncClient()..atomic = atomic;
      final cloudCache = await Directory('${temp.path}/cloud').create();
      await RowSyncEngine(
              store: RowSyncStore(b), client: client, cache: cloudCache)
          .synchronize();
      await a.update('tb_notes', {'content': 'discarded local'});
      final localCache = await Directory('${temp.path}/local').create();
      await RowSyncEngine(
        store: RowSyncStore(a),
        client: client,
        cache: localCache,
        onPreview: (_) async =>
            const SyncPreviewDecision(SyncConflictResolution.preferRemote),
      ).synchronize();
      await RowSyncEngine(
              store: RowSyncStore(b), client: client, cache: cloudCache)
          .synchronize();
      expect((await a.query('tb_notes')).single['content'], 'shared');
      expect(
          sameSyncRecords(await RowSyncStore(a).snapshot(),
              await RowSyncStore(b).snapshot()),
          isTrue);
    });
  }

  test('preferLocal preserves irreversible note deletion on every device',
      () async {
    await b.delete('tb_notes');
    await RowSyncStore(a).merge(await RowSyncStore(b).snapshot(),
        resolution: SyncConflictResolution.preferLocal);
    expect(await a.query('tb_notes'), isEmpty);
    await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
    await RowSyncStore(a).merge(await RowSyncStore(b).snapshot());
    expect(await a.query('tb_notes'), isEmpty,
        reason: 'The original deletion rule must remain convergent');
  });

  test('preferRemote must back up before replacing a newer local note',
      () async {
    await a.update('tb_notes', {'content': 'unsynced local edit'});
    final archive = File('${temp.path}/remote.db');
    await RowSyncArchive.write(archive.path, await RowSyncStore(b).snapshot());
    final client = MemorySyncClient();
    client.files[RowSyncEngine.remotePath] = await archive.readAsBytes();
    var backups = 0;
    await RowSyncEngine(
      store: RowSyncStore(a),
      client: client,
      cache: temp,
      beforeMerge: () async {
        backups++;
      },
      onPreview: (_) async =>
          const SyncPreviewDecision(SyncConflictResolution.preferRemote),
    ).synchronize();
    expect((await a.query('tb_notes')).single['content'], 'shared');
    expect(backups, 1,
        reason: 'The original backup safeguard must cover forced merges');
  });

  test(
      'preferRemote must survive another device retaining the newer local copy',
      () async {
    await a.update('tb_notes', {'content': 'previously shared edit'});
    final thirdDevice = await fixture(bookId: 99);
    try {
      await RowSyncStore(thirdDevice).merge(await RowSyncStore(a).snapshot());
      await RowSyncStore(a).merge(await RowSyncStore(b).snapshot(),
          resolution: SyncConflictResolution.preferRemote);
      expect((await a.query('tb_notes')).single['content'], 'shared');
      await RowSyncStore(thirdDevice).merge(await RowSyncStore(a).snapshot());
      expect((await thirdDevice.query('tb_notes')).single['content'], 'shared');
    } finally {
      await thirdDevice.close();
    }
  });
}
