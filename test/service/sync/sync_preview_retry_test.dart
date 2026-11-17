import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/service/sync/row_sync_engine.dart';
import 'package:modu_reader/service/sync/row_sync_record.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:modu_reader/service/sync/sync_preview.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'row_sync_test.dart' show MemorySyncClient, bookRow, fixture, noteRow;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database local, remote;
  late Directory temp;

  setUp(() async {
    local = await fixture(install: false);
    remote = await fixture(bookId: 77, install: false);
    await local.insert('tb_notes', noteRow(1, 'shared'));
    await remote.insert('tb_notes', noteRow(77, 'shared'));
    await remote.insert('tb_books', bookRow(88, md5: 'cloud-only'));
    await local.transaction((txn) => RowSyncStore.install(txn));
    await remote.transaction((txn) => RowSyncStore.install(txn));
    await local.insert('tb_notes', noteRow(1, 'local-only'));
    await remote.update('modu_sync_control',
        {'clock': DateTime.now().millisecondsSinceEpoch + 3600000});
    await remote.update('tb_notes', {'content': 'cloud-v1'});
    temp = await Directory.systemTemp.createTemp('modu-preview-retry-');
    await Directory('${temp.path}/cache').create();
  });
  tearDown(() async {
    await local.close();
    await remote.close();
    await temp.delete(recursive: true);
  });

  Future<void> replaceCloud(MemorySyncClient client,
      [List<RowSyncRecord>? records]) async {
    final file = File('${temp.path}/cloud.db');
    if (await file.exists()) await file.delete();
    await RowSyncArchive.write(
        file.path, records ?? await RowSyncStore(remote).snapshot());
    client.files[RowSyncEngine.remotePath] = await file.readAsBytes();
    client.revisions[RowSyncEngine.remotePath] =
        (client.revisions[RowSyncEngine.remotePath] ?? 0) + 1;
  }

  for (final change in [
    'same-key payload',
    'cloud-only deletion',
    'new cloud book'
  ]) {
    test('CAS retry reconfirms $change before any second publication',
        () async {
      final client = MemorySyncClient();
      await replaceCloud(client);
      final before = await RowSyncStore(local).snapshot();
      client.beforeWrite = (attempt) async {
        if (attempt != 1) return;
        switch (change) {
          case 'same-key payload':
            await remote.update('tb_notes', {'content': 'cloud-v2'});
          case 'cloud-only deletion':
            await remote.update('tb_books', {'is_deleted': 1},
                where: 'id=?', whereArgs: [88]);
          case 'new cloud book':
            await remote.insert(
                'tb_books', bookRow(99, md5: 'cloud-added-later'));
        }
        await replaceCloud(client);
      };
      var confirmations = 0;
      final seen = <SyncPreviewContext>[];
      final engine = RowSyncEngine(
          store: RowSyncStore(local),
          client: client,
          cache: Directory('${temp.path}/cache'),
          onPreview: (context) async {
            seen.add(context);
            confirmations++;
            return confirmations == 1
                ? const SyncPreviewDecision(SyncConflictResolution.uploadOnly)
                : const SyncPreviewDecision.cancel();
          });
      await expectLater(
          engine.synchronize(), throwsA(isA<SyncPreviewCancelled>()));
      expect(confirmations, 2);
      expect(client.writes, 1,
          reason: 'Cancellation precedes the second attempted PUT');
      expect(
          sameSyncRecords(before, await RowSyncStore(local).snapshot()), true);
      switch (change) {
        case 'same-key payload':
          expect(
              seen.last.remote
                  .singleWhere((r) => r.kind == 'note')
                  .data['content'],
              'cloud-v2');
        case 'cloud-only deletion':
          expect(
              seen.last.remote
                  .singleWhere(
                      (r) => r.kind == 'life' && r.id == 'md5:cloud-only')
                  .data['is_deleted'],
              1);
        case 'new cloud book':
          expect(
              seen.last.remote
                  .where((r) => r.kind == 'book')
                  .map((r) => r.data['file_md5']),
              contains('cloud-added-later'));
      }
    });
  }

  test(
      'a new local book deletion after confirmation requires fresh acknowledgement',
      () async {
    final client = MemorySyncClient();
    await replaceCloud(client);
    final cloudBefore = {
      for (final e in client.files.entries) e.key: List<int>.of(e.value)
    };
    var confirmations = 0, preparations = 0;
    SyncPreview? changed;
    final engine = RowSyncEngine(
        store: RowSyncStore(local),
        client: client,
        cache: Directory('${temp.path}/cache'),
        beforePublish: () async {
          preparations++;
          if (preparations == 1) {
            await local.update('tb_books', {'is_deleted': 1});
          }
        },
        onPreview: (context) async {
          confirmations++;
          changed = buildSyncPreview(
              context: context, resolution: SyncConflictResolution.uploadOnly);
          return confirmations == 1
              ? const SyncPreviewDecision(SyncConflictResolution.uploadOnly)
              : const SyncPreviewDecision.cancel();
        });
    await expectLater(
        engine.synchronize(), throwsA(isA<SyncPreviewCancelled>()));
    expect(confirmations, 2);
    expect(changed!.cloudRemovedBooks, hasLength(1));
    expect(client.files, cloudBefore);
    expect(client.writes, 0);
    expect((await local.query('tb_books')).single['is_deleted'], 1,
        reason:
            'The new local user deletion remains; cancellation only stops the sync');
  });

  test('CAS retry ignores clock revision and payload-key-order changes',
      () async {
    final client = MemorySyncClient();
    await replaceCloud(client);
    client.beforeWrite = (attempt) async {
      if (attempt != 1) return;
      final records = await RowSyncStore(remote).snapshot();
      await replaceCloud(client, [
        for (final r in records)
          RowSyncRecord(r.kind, r.id, r.clock + 100, 'restamped:${r.revision}',
              r.deleted, Map.fromEntries(r.data.entries.toList().reversed),
              narration: r.narration)
      ]);
    };
    var confirmations = 0;
    await RowSyncEngine(
        store: RowSyncStore(local),
        client: client,
        cache: Directory('${temp.path}/cache'),
        onPreview: (_) async {
          confirmations++;
          return const SyncPreviewDecision(SyncConflictResolution.uploadOnly);
        }).synchronize();
    expect(confirmations, 1);
    expect(client.writes, 2);
    final file = File('${temp.path}/final.db');
    await file.writeAsBytes(client.files[RowSyncEngine.remotePath]!);
    expect(
        (await RowSyncArchive.read(file.path))
            .where((r) => r.kind == 'note' && !r.deleted)
            .map((r) => r.data['cfi']),
        contains('local-only'));
  });
}
