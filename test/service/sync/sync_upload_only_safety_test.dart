import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/service/sync/row_sync_engine.dart';
import 'package:modu_reader/service/sync/row_sync_record.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:modu_reader/service/sync/sync_preview.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'row_sync_test.dart' show MemorySyncClient, bookRow, fixture, noteRow;

class _Client extends MemorySyncClient {
  @override
  Future<void> remove(String path) async {
    files.remove(path);
  }
}

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
    await local.transaction((txn) => RowSyncStore.install(txn));
    await remote.transaction((txn) => RowSyncStore.install(txn));
    temp = await Directory.systemTemp.createTemp('modu-upload-safety-');
    await Directory('${temp.path}/cache').create();
    await Directory('${temp.path}/restore-cache').create();
  });
  tearDown(() async {
    await local.close();
    await remote.close();
    await temp.delete(recursive: true);
  });

  Future<void> seed(_Client client) async {
    final file = File('${temp.path}/seed.db');
    await RowSyncArchive.write(
        file.path, await RowSyncStore(remote).snapshot());
    client.files[RowSyncEngine.remotePath] = await file.readAsBytes();
    client.revisions[RowSyncEngine.remotePath] = 1;
  }

  Future<List<RowSyncRecord>> published(_Client client) async {
    var records = <RowSyncRecord>[];
    var index = 0;
    for (final entry in client.files.entries.where((e) =>
        e.key == RowSyncEngine.remotePath ||
        e.key.contains('/record-log-v1/'))) {
      final file = File('${temp.path}/published-${index++}.db');
      await file.writeAsBytes(entry.value);
      records = mergeSyncRecords(records, await RowSyncArchive.read(file.path));
    }
    return records;
  }

  for (final atomic in [true, false]) {
    for (final deleted in [false, true]) {
      test(
          'upload-only preserves newer cloud note/deletion; atomic=$atomic deleted=$deleted',
          () async {
        await local.insert('tb_notes', noteRow(1, 'local-only'));
        await remote.insert('tb_notes', noteRow(77, 'cloud-only'));
        await remote.insert('tb_books', bookRow(88, md5: 'cloud-only-book'));
        await remote.update('modu_sync_control',
            {'clock': DateTime.now().millisecondsSinceEpoch + 3600000});
        if (deleted) {
          await remote
              .delete('tb_notes', where: 'cfi=?', whereArgs: ['shared']);
        } else {
          await remote.update('tb_notes', {'content': 'newer cloud text'},
              where: 'cfi=?', whereArgs: ['shared']);
        }
        await remote.update('tb_books',
            {'last_read_position': 'cloud-page', 'reading_percentage': .8},
            where: 'id=?', whereArgs: [77]);
        final client = _Client()..atomic = atomic;
        await seed(client);
        final before = await RowSyncStore(local).snapshot();
        SyncPreview? preview;
        final outcome = await RowSyncEngine(
            store: RowSyncStore(local),
            client: client,
            cache: Directory('${temp.path}/cache'),
            onPreview: (context) async {
              preview = buildSyncPreview(
                  context: context,
                  resolution: SyncConflictResolution.uploadOnly);
              return const SyncPreviewDecision(
                  SyncConflictResolution.uploadOnly);
            }).synchronize();

        expect(outcome, RowSyncOutcome.published);
        expect(sameSyncRecords(before, await RowSyncStore(local).snapshot()),
            true);
        expect(preview!.hasDownloadChanges, false);
        expect(preview!.uploadNoteAfter, deleted ? 2 : 3);
        expect(preview!.uploadNoteDelta, 1);
        expect(preview!.uploadedProgressChangedBooks, isEmpty,
            reason:
                'Older local progress does not overwrite the newer cloud position');
        final cloud = await published(client);
        final sharedId = before
            .singleWhere((r) => r.kind == 'note' && r.data['cfi'] == 'shared')
            .id;
        final shared =
            cloud.singleWhere((r) => r.kind == 'note' && r.id == sharedId);
        expect(shared.deleted, deleted);
        if (!deleted) expect(shared.data['content'], 'newer cloud text');
        expect(
            cloud
                .where((r) => r.kind == 'note' && !r.deleted)
                .map((r) => r.data['cfi']),
            containsAll(['local-only', 'cloud-only']));
        expect(
            cloud
                .where((r) => r.kind == 'book' && !r.deleted)
                .map((r) => r.data['file_md5']),
            contains('cloud-only-book'));
        expect(
            cloud
                .singleWhere(
                    (r) => r.kind == 'position' && r.id == 'md5:same-content')
                .data['reading_percentage'],
            .8);
      });
    }

    test(
        'upload-only respects newer cloud restore in preview and transport; atomic=$atomic',
        () async {
      await local.update('tb_books', {'is_deleted': 1});
      await remote.update('modu_sync_control',
          {'clock': DateTime.now().millisecondsSinceEpoch + 3600000});
      await remote.update('tb_books', {'is_deleted': 1});
      await remote.update('tb_books', {'is_deleted': 0});
      await local.insert('tb_notes', noteRow(1, 'local-extra'));
      final client = _Client()..atomic = atomic;
      await seed(client);
      final before = await RowSyncStore(local).snapshot();
      SyncPreview? preview;
      await RowSyncEngine(
          store: RowSyncStore(local),
          client: client,
          cache: Directory('${temp.path}/restore-cache'),
          onPreview: (context) async {
            preview = buildSyncPreview(
                context: context,
                resolution: SyncConflictResolution.uploadOnly);
            return const SyncPreviewDecision(SyncConflictResolution.uploadOnly);
          }).synchronize();
      expect(
          sameSyncRecords(before, await RowSyncStore(local).snapshot()), true);
      expect(preview!.cloudRemovedBooks, isEmpty);
      expect(preview!.hasDownloadChanges, false);
      expect(
          (await published(client))
              .singleWhere(
                  (r) => r.kind == 'life' && r.id == 'md5:same-content')
              .data['is_deleted'],
          0);
    });
  }
}
