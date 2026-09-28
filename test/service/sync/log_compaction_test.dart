import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/service/sync/immutable_sync_log.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'row_sync_test.dart' show MemorySyncClient, fixture, noteRow;

class CompactClient extends MemorySyncClient {
  final removed = <String>[];
  final downloaded = <String>[];
  int plainPuts = 0;
  bool corruptUpload = false;
  bool denyDelete = false;
  Future<void> Function(String)? onDownload;
  Future<void> Function(String)? onUpload;
  Future<void> Function(String)? onList;

  DioException error(String path, int status) {
    final request = RequestOptions(path: path);
    return DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: status));
  }

  @override
  Future<void> remove(String path) async {
    if (denyDelete) throw error(path, 403);
    removed.add(path);
    if (files.remove(path) == null) throw error(path, 404);
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath,
      {void Function(int, int)? onProgress}) async {
    await onDownload?.call(remotePath);
    downloaded.add(remotePath);
    if (!files.containsKey(remotePath)) throw error(remotePath, 404);
    await super.downloadFile(remotePath, localPath);
  }

  @override
  Future<void> uploadFile(String localPath, String remotePath,
      {bool replace = true,
      void Function(int, int)? onProgress,
      CancelToken? cancelToken}) async {
    plainPuts++;
    await super.uploadFile(localPath, remotePath);
    await onUpload?.call(remotePath);
    if (corruptUpload) files[remotePath] = [1, 2, 3];
  }

  @override
  Future<List<RemoteFile>> readDir(String path) async {
    await onList?.call(path);
    return super.readDir(path);
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory temp;
  late Database db;
  late RowSyncStore store;
  late CompactClient client;
  var sequence = 0;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('modu-compaction-');
    db = await fixture();
    store = RowSyncStore(db);
    client = CompactClient()..atomic = false;
    sequence = 0;
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<String> seed(List<RowSyncRecord> records) async {
    final file = File('${temp.path}/seed-${sequence++}.db');
    await RowSyncArchive.write(file.path, records);
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    final path = 'modu/record-log-v1/${digest[0]}/$digest.db';
    client.files[path] = bytes;
    return path;
  }

  Future<List<RowSyncRecord>> seedHistory(int count) async {
    var records = await store.snapshot();
    await seed(records);
    final initial = records.firstWhere((r) => r.kind == 'position');
    for (var i = 1; i < count; i++) {
      final next = RowSyncRecord(
          'position', initial.id, initial.clock + i, 'revision-$i', false, {
        ...initial.data,
        'last_read_position': 'chapter-$i',
        'reading_percentage': 0.5
      });
      await seed([next]);
      records = mergeSyncRecords(records, [next]);
    }
    return records;
  }

  Future<ImmutableSyncLog> log() async {
    final own = await Directory('${temp.path}/client-${sequence++}').create();
    return ImmutableSyncLog(client, own, own, durableDirectory: own);
  }

  Future<RowSyncOutcome> sync() =>
      RowSyncEngine(store: store, client: client, cache: temp).synchronize();

  test(
      '700 compatibility batches compact to one; next sync downloads no history',
      () async {
    final expected = await seedHistory(700);
    final before = client.files.keys.toSet();
    await sync();
    expect(client.files, hasLength(1));
    expect(client.files.containsKey(RowSyncEngine.remotePath), false);
    expect(client.removed.toSet(), before);
    expect(client.writes, 0);
    expect(sameSyncRecords(await (await log()).read(), expected), true);
    // The first pass may need the new checkpoint, never the 700 retired inputs.
    client.downloaded.clear();
    await sync();
    expect(client.downloaded.where(before.contains), isEmpty);
    final puts = client.plainPuts;
    client.downloaded.clear();
    await sync();
    expect(client.downloaded, isEmpty);
    expect(client.plainPuts, puts);
  });

  test(
      'reliable CAS folds even a small unchanged log into database8, no new log',
      () async {
    final expected = await seedHistory(3);
    await store.merge(expected); // No pending local edits.
    client.atomic = true;
    await sync();
    expect(client.files.keys, [RowSyncEngine.remotePath]);
    expect(client.plainPuts, 0);
    expect(client.writes, 1);
    final file = File('${temp.path}/primary.db');
    await file.writeAsBytes(client.files[RowSyncEngine.remotePath]!);
    expect(
        sameSyncRecords(await RowSyncArchive.read(file.path), expected), true);
    await sync();
    expect(client.writes, 1);
  });

  test('offline edits cannot resurrect compacted note tombstones', () async {
    await db.insert('tb_notes', noteRow(1, 'old-note'));
    final offline = await store.snapshot();
    await seed(offline);
    await db.delete('tb_notes');
    final expected = await seedHistory(64);
    await sync();
    final compacted = await (await log()).read();
    expect(compacted.where((r) => r.kind == 'note').single.deleted, true);
    expect(
        sameSyncRecords(mergeSyncRecords(compacted, offline), expected), true);
  });

  test('new concurrent batches are never in the deletion set', () async {
    await seedHistory(64);
    final reader = await log();
    final old = await reader.read();
    await db.insert('tb_notes', noteRow(1, 'arrived-during-upload'));
    final newer =
        (await store.snapshot()).where((r) => r.kind == 'note').toList();
    String? newcomer;
    client.onUpload = (_) async {
      client.onUpload = null;
      newcomer = await seed(newer);
    };
    await reader.compactIfNeeded();
    expect(client.files.containsKey(newcomer), true);
    expect(client.removed, isNot(contains(newcomer)));
    expect(
        sameSyncRecords(
            await (await log()).read(), mergeSyncRecords(old, newer)),
        true);
  });

  test('failed checkpoint verification deletes no old batch', () async {
    await seedHistory(64);
    final inputs = client.files.keys.toSet();
    final reader = await log();
    await reader.read();
    client.corruptUpload = true;
    await expectLater(reader.compactIfNeeded(), throwsFormatException);
    expect(client.removed, isEmpty);
    expect(client.files.keys.toSet().containsAll(inputs), true);
    client.corruptUpload = false;
    await reader.resumePending();
    await reader.read();
    await reader.compactIfNeeded();
    expect(client.files, hasLength(1));
  });

  test('DELETE denied is nonfatal and can be retried after restart', () async {
    await seedHistory(64);
    client.denyDelete = true;
    await sync();
    expect(client.files.length, greaterThanOrEqualTo(64));
    client.denyDelete = false;
    await sync();
    expect(client.files, hasLength(1));
  });

  test('changed primary checkpoint is not proof for deleting log inputs',
      () async {
    await seedHistory(3);
    final before = client.files.keys.toSet();
    client.atomic = true;
    client.onDownload = (path) async {
      if (path == RowSyncEngine.remotePath && client.writes > 0) {
        client.files[path] = [1, 2, 3];
      }
    };
    await sync();
    expect(client.removed, isEmpty);
    expect(client.files.keys.toSet().containsAll(before), true);
  });

  test('identical compactors never delete their common successor', () async {
    final expected = await seedHistory(64);
    final first = await log();
    final second = await log();
    await first.read();
    await second.read();
    await first.compactIfNeeded();
    await second.compactIfNeeded();
    expect(client.files, hasLength(1));
    expect(sameSyncRecords(await (await log()).read(), expected), true);
  });

  test('CAS conflict retries before reclaiming; sidecars and other data remain',
      () async {
    await seedHistory(3);
    client.files['modu/record-log-v1/.DS_Store'] = [7];
    client.files['modu/file/keep.epub'] = [8];
    client.files['modu/database7.db'] = [9];
    client.atomic = true;
    client.beforeWrite = (attempt) async {
      expect(client.removed, isEmpty);
      if (attempt == 1) throw client.error(RowSyncEngine.remotePath, 412);
    };
    await sync();
    expect(client.writes, 2);
    expect(client.files['modu/record-log-v1/.DS_Store'], [7]);
    expect(client.files['modu/file/keep.epub'], [8]);
    expect(client.files['modu/database7.db'], [9]);
    expect(client.removed, hasLength(3));
  });

  test('reader re-lists when compaction removes a batch before its download',
      () async {
    final expected = await seedHistory(64);
    final compactor = await log();
    await compactor.read();
    client.onDownload = (_) async {
      client.onDownload = null;
      await compactor.compactIfNeeded();
    };
    final received = await (await log()).read();
    expect(sameSyncRecords(received, expected), true);
  });

  test('listing race cannot miss checkpoint and deleted inputs simultaneously',
      () async {
    final expected = await seedHistory(64);
    final compactor = await log();
    await compactor.read();
    var rootListings = 0;
    // Publish after the initial root listing, potentially into a shard already
    // visited; the final complete name-set check must force a fresh read.
    var shardsListed = 0;
    client.onList = (path) async {
      if (path == 'modu/record-log-v1') rootListings++;
      if (path.startsWith('modu/record-log-v1/') && ++shardsListed == 2) {
        client.onList = null;
        await compactor.compactIfNeeded();
      }
    };
    expect(sameSyncRecords(await (await log()).read(), expected), true);
    expect(rootListings, greaterThanOrEqualTo(1));
  });

  test(
      'two compactors with overlapping snapshots preserve both sets of records',
      () async {
    final expected = await seedHistory(64);
    final first = await log();
    final second = await log();
    await first.read();
    await db.insert('tb_notes', noteRow(1, 'second-device'));
    final note =
        (await store.snapshot()).where((r) => r.kind == 'note').toList();
    await seed(note);
    await second.read();
    final bothUploading = Completer<void>();
    var uploads = 0;
    client.onUpload = (_) async {
      if (++uploads == 2) bothUploading.complete();
      await bothUploading.future;
    };
    await Future.wait([first.compactIfNeeded(), second.compactIfNeeded()]);
    expect(
        sameSyncRecords(
            await (await log()).read(), mergeSyncRecords(expected, note)),
        true);
  });
}
