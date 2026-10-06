import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'row_sync_test.dart' show fixture, bookRow, MemorySyncClient;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  for (final legacy in [false, true]) {
    for (final length in [0, 16384]) {
      test(
          '${legacy ? 'legacy' : 'current'} archive truncated to $length '
          'bytes cannot overwrite the cloud or clear the library', () async {
        final temp = await Directory.systemTemp.createTemp('modu-truncated-');
        final local = await fixture();
        try {
          final path = '${temp.path}/source.db';
          if (legacy) {
            final source = await fixture(install: false, path: path);
            for (var id = 2; id < 100; id++) {
              await source.insert('tb_books', bookRow(id, md5: 'test-$id'));
            }
            await source.close();
          } else {
            for (var id = 2; id < 100; id++) {
              await local.insert('tb_books', bookRow(id, md5: 'test-$id'));
            }
            await RowSyncArchive.write(
                path, await RowSyncStore(local).snapshot());
          }
          final complete = await File(path).readAsBytes();
          expect(complete.length, greaterThan(length));
          final truncated = complete.sublist(0, length);
          final remote = 'modu/database${legacy ? 7 : 8}.db';
          final client = MemorySyncClient()..files[remote] = truncated;
          final before = await RowSyncStore(local).snapshot();
          await expectLater(
              RowSyncEngine(
                      store: RowSyncStore(local), client: client, cache: temp)
                  .synchronize(),
              throwsA(anything));
          expect(client.writes, 0);
          expect(client.files.keys, [remote]);
          expect(client.files[remote], truncated);
          expect(sameSyncRecords(before, await RowSyncStore(local).snapshot()),
              isTrue);
        } finally {
          await local.close();
          await temp.delete(recursive: true);
        }
      });
    }
  }

  // Explicit local-copy opt-in. This test has no real network client and never
  // opens the application's live library. Paths, payloads and titles stay out
  // of test output; legacy migration is performed on a disposable second copy.
  final manifestPath = Platform.environment['MODU_CLOUD_SNAPSHOT_MANIFEST'];
  test(
      'authorized cloud copies migrate, replay and serialize without data loss',
      () async {
    final manifest =
        jsonDecode(await File(manifestPath!).readAsString()) as Map;
    final temp = await Directory.systemTemp.createTemp('modu-cloud-copy-');
    final target = await fixture(install: false);
    try {
      await target.delete('tb_books');
      await target.transaction((txn) => RowSyncStore.install(txn));
      final store = RowSyncStore(target);
      var tested = 0;
      var combined = <RowSyncRecord>[];
      for (final entry in manifest['files'] as List) {
        final source = File(entry['local'] as String);
        final original = await source.readAsBytes();
        final disposable = await source.copy('${temp.path}/input-$tested.db');
        late List<RowSyncRecord> records;
        try {
          records = await RowSyncArchive.read(disposable.path,
              legacy: entry['version'] == 7);
          if (entry['version'] == 8) {
            combined = mergeSyncRecords(combined, records,
                reconcileBookIdentities: false);
          }
          var merged = records;
          // A sampled incremental log is not a complete snapshot: references
          // can live in unsampled batches. Production merges all batches before
          // materializing them. Only full database archives can be replayed
          // independently here; sampled batches still get parser/roundtrip checks.
          if (!(entry['remote'] as String).contains('/record-log-v1/')) {
            await store.merge(records);
            merged = await store.snapshot();
            await store.merge(records);
            expect(sameSyncRecords(merged, await store.snapshot()), isTrue,
                reason:
                    'Replaying the same verified archive must be idempotent');
          }
          final roundtrip = '${temp.path}/roundtrip-$tested.db';
          await RowSyncArchive.write(roundtrip, merged);
          expect(sameSyncRecords(merged, await RowSyncArchive.read(roundtrip)),
              isTrue);
        } catch (error, stack) {
          fail(
              'Cloud-copy compatibility failure: archive=$tested version=${entry['version']} ${error.runtimeType}; private details omitted\n$stack');
        }
        expect(
            base64Encode(await source.readAsBytes()) == base64Encode(original),
            isTrue,
            reason: 'The downloaded original must stay unchanged');
        tested++;
      }
      expect(tested, greaterThan(0));
      if (manifest['complete'] == true) {
        final fresh = await fixture(install: false);
        try {
          await fresh.delete('tb_books');
          await fresh.transaction((txn) => RowSyncStore.install(txn));
          final freshStore = RowSyncStore(fresh);
          await freshStore.merge(mergeSyncRecords(combined, []));
          final once = await freshStore.snapshot();
          await freshStore.merge(mergeSyncRecords(combined, []));
          expect(sameSyncRecords(once, await freshStore.snapshot()), isTrue);
          print('Complete cloud checkpoint + journal replay: passed');
        } catch (error, stack) {
          fail(
              'Complete cloud-copy replay failed: ${error.runtimeType}; private details omitted\n$stack');
        } finally {
          await fresh.close();
        }
      }
      print('Cloud-copy archives verified: $tested; remote writes: 0');
    } finally {
      await target.close();
      await temp.delete(recursive: true);
    }
  }, skip: manifestPath == null);
}
