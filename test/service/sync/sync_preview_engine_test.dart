import 'dart:io';

import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/sync_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'row_sync_test.dart' show MemorySyncClient, fixture, noteRow;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('declining the preview writes nothing on either side', () async {
    final local = await fixture();
    final cloud = await fixture(bookId: 77);
    final temp = await Directory.systemTemp.createTemp('modu-preview-cancel-');
    try {
      await cloud.insert('tb_notes', noteRow(77, 'cloud-note'));
      final archive = File('${temp.path}/cloud.db');
      await RowSyncArchive.write(
          archive.path, await RowSyncStore(cloud).snapshot());
      final client = MemorySyncClient();
      client.files[RowSyncEngine.remotePath] = await archive.readAsBytes();
      client.revisions[RowSyncEngine.remotePath] = 1;
      final cloudBytes = [...client.files[RowSyncEngine.remotePath]!];
      final before = await RowSyncStore(local).snapshot();

      var previewCalls = 0;
      var publishCalls = 0;
      final engine = RowSyncEngine(
        store: RowSyncStore(local),
        client: client,
        cache: temp,
        beforePublish: () async => publishCalls++,
        onPreview: (context) async {
          previewCalls++;
          expect(context.local, isNotEmpty);
          expect(context.remote, isNotEmpty);
          expect(context.remoteMissing, isFalse);
          expect(context.remoteFileAt, isNotNull);
          return const SyncPreviewDecision.cancel();
        },
      );

      await expectLater(
          engine.synchronize(), throwsA(isA<SyncPreviewCancelled>()));
      expect(previewCalls, 1);
      expect(publishCalls, 0);
      expect(client.writes, 0);
      expect(client.files[RowSyncEngine.remotePath], cloudBytes);
      expect(sameSyncRecords(before, await RowSyncStore(local).snapshot()),
          isTrue);
      expect(await local.query('tb_notes'), isEmpty);
    } finally {
      await local.close();
      await cloud.close();
      await temp.delete(recursive: true);
    }
  });

  test('confirming the preview merges the cloud records', () async {
    final local = await fixture();
    final cloud = await fixture(bookId: 77);
    final temp = await Directory.systemTemp.createTemp('modu-preview-merge-');
    try {
      await cloud.insert('tb_notes', noteRow(77, 'cloud-note'));
      final archive = File('${temp.path}/cloud.db');
      await RowSyncArchive.write(
          archive.path, await RowSyncStore(cloud).snapshot());
      final client = MemorySyncClient();
      client.files[RowSyncEngine.remotePath] = await archive.readAsBytes();
      client.revisions[RowSyncEngine.remotePath] = 1;

      var previewCalls = 0;
      final engine = RowSyncEngine(
        store: RowSyncStore(local),
        client: client,
        cache: temp,
        onPreview: (_) async {
          previewCalls++;
          return const SyncPreviewDecision(SyncConflictResolution.newest);
        },
      );

      final outcome = await engine.synchronize();
      expect(outcome, isNot(RowSyncOutcome.publishedWithPendingChanges));
      expect(previewCalls, 1);
      final notes = await local.query('tb_notes');
      expect(notes, hasLength(1));
      expect(notes.single['cfi'], 'cloud-note');
    } finally {
      await local.close();
      await cloud.close();
      await temp.delete(recursive: true);
    }
  });

  test('preferLocal re-stamps the record so another device keeps the choice',
      () async {
    // Notes created before the sync schema was installed keep a deterministic
    // legacy identity, which is what makes the same note exist on both devices.
    final a = await fixture(install: false);
    final b = await fixture(bookId: 77, install: false);
    try {
      await a.insert('tb_notes', noteRow(1, 'X'));
      await b.insert('tb_notes', noteRow(77, 'X'));
      await a.transaction((txn) => RowSyncStore.install(txn));
      await b.transaction((txn) => RowSyncStore.install(txn));
      await a.update('tb_notes', {'content': 'local'},
          where: 'id = ?', whereArgs: [1]);
      await b.update('tb_notes', {'content': 'cloud'},
          where: 'id = ?', whereArgs: [1]);

      await RowSyncStore(a).merge(await RowSyncStore(b).snapshot(),
          resolution: SyncConflictResolution.preferLocal);
      expect((await a.query('tb_notes')).single['content'], 'local');

      // The cloud device must accept the choice instead of flipping it back.
      await RowSyncStore(b).merge(await RowSyncStore(a).snapshot());
      expect((await b.query('tb_notes')).single['content'], 'local');
    } finally {
      await a.close();
      await b.close();
    }
  });

  test('preferRemote overwrites the local row with the cloud content',
      () async {
    final a = await fixture(install: false);
    final b = await fixture(bookId: 77, install: false);
    try {
      await a.insert('tb_notes', noteRow(1, 'X'));
      await b.insert('tb_notes', noteRow(77, 'X'));
      await a.transaction((txn) => RowSyncStore.install(txn));
      await b.transaction((txn) => RowSyncStore.install(txn));
      await a.update('tb_notes', {'content': 'local'},
          where: 'id = ?', whereArgs: [1]);
      await b.update('tb_notes', {'content': 'cloud'},
          where: 'id = ?', whereArgs: [1]);

      await RowSyncStore(a).merge(await RowSyncStore(b).snapshot(),
          resolution: SyncConflictResolution.preferRemote);
      expect((await a.query('tb_notes')).single['content'], 'cloud');
    } finally {
      await a.close();
      await b.close();
    }
  });
}
