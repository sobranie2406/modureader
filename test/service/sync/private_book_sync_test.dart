import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/service/sync/immutable_sync_log.dart';
import 'package:modu_reader/service/sync/private_book_sync.dart';
import 'package:modu_reader/service/sync/row_sync_engine.dart';
import 'package:modu_reader/service/sync/row_sync_record.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:modu_reader/service/sync/sync_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'row_sync_test.dart' show fixture, bookRow, noteRow, MemorySyncClient;
import 'log_compaction_test.dart' show CompactClient;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final library = PrivateLibrary.instance;
  late Database db;
  late RowSyncStore store;
  late Directory cache;
  late MemorySyncClient client;
  final secret = Book.mock()
      .copyWith(id: 2, md5: 'private', filePath: 'file/private.epub');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    library.setPluginActive(true);
    await library.unlock();
    db = await fixture();
    await db
        .insert('tb_books', {...bookRow(2, md5: 'private'), 'title': 'SECRET'});
    await db.insert('tb_notes', noteRow(1, 'public-note'));
    await db.insert('tb_notes', noteRow(2, 'SECRET-note'));
    store = RowSyncStore(db);
    cache = await Directory.systemTemp.createTemp('modu-private-row-');
    client = MemorySyncClient();
  });
  tearDown(() async {
    library.setPluginActive(false);
    await db.close();
    await cache.delete(recursive: true);
  });

  Future<void> protect() async {
    await library.setBooksPrivate([secret], true);
    library.lock();
  }

  Future<List<RowSyncRecord>> uploaded() async {
    final result = <RowSyncRecord>[];
    var index = 0;
    for (final bytes in client.files.values) {
      final file = File('${cache.path}/inspect-${index++}.db');
      await file.writeAsBytes(bytes);
      result.addAll(await RowSyncArchive.read(file.path));
    }
    return result;
  }

  RowSyncEngine engine(
          {SyncPreviewHook? onPreview,
          Future<void> Function()? beforePublish}) =>
      RowSyncEngine(
          store: store,
          client: client,
          cache: cache,
          onPreview: onPreview,
          beforePublish: beforePublish);

  test('no marks leaves the raw transport view unchanged', () async {
    final records = await store.snapshot();
    expect(
        sameSyncRecords(
            PrivateBookSyncFilter(records).allowedRecords(records), records),
        true);
    await engine().synchronize();
    expect((await uploaded()).where((r) => r.kind == 'book'), hasLength(2));
  });

  test('local private source and every associated kind stay off the wire',
      () async {
    await db.insert('tb_reading_time',
        {'book_id': 2, 'date': '2026-11-01', 'reading_time': 80, 'round': 1});
    await db.insert('tb_reading_rounds', {
      'book_id': 2,
      'round_number': 1,
      'status': 'reading',
      'start_percentage': 0,
      'end_percentage': 0,
      'total_reading_time': 80
    });
    await protect();
    await engine().synchronize();
    final wire = await uploaded();
    expect(wire.where((r) => r.kind == 'book').single.id, 'md5:same-content');
    expect(jsonEncode(wire.map((r) => r.toMap()).toList()),
        isNot(contains('SECRET')));
    expect(wire.any((r) => r.data['book_id'] == 'md5:private'), false);
    expect((await db.query('tb_notes')).length, 2);
    expect(
        (await store.snapshot()).where((r) => r.kind == 'book'), hasLength(2));
    expect(client.files.containsKey(RowSyncEngine.remotePath), false);
  });

  test('unlocked, disabled and missing plugin do not enable private transport',
      () async {
    await protect();
    await library.unlock();
    await library.setEnabled(false);
    library.setPluginActive(false);
    expect(library.canRead(secret), true);
    expect(library.canSyncBook(secret), false);
    await engine().synchronize();
    expect(jsonEncode((await uploaded()).map((r) => r.toMap()).toList()),
        isNot(contains('SECRET')));
  });

  test('cloud private tombstones and edits cannot replace local private rows',
      () async {
    final before = await store.snapshot();
    await protect();
    final remote = before
        .map((r) => r.id == 'md5:private' || r.data['book_id'] == 'md5:private'
            ? RowSyncRecord(
                r.kind, r.id, r.clock + 999999, 'remote-delete', true, r.data)
            : r)
        .toList();
    await store.merge(remote,
        protectPrivateBooks: true,
        resolution: SyncConflictResolution.preferRemote);
    expect((await db.query('tb_books', where: 'id=2')).single['is_deleted'], 0);
    expect((await db.query('tb_notes', where: 'book_id=2')).single['content'],
        'SECRET-note');
    final after = await store.snapshot();
    final privacy = PrivateBookSyncFilter([...before, ...remote]);
    expect(
        sameSyncRecords(
            privacy.protectedRecords(before), privacy.protectedRecords(after)),
        true);
  });

  test('existing cloud private copies remain unchanged while public edits sync',
      () async {
    final remote = File('${cache.path}/remote.db');
    await RowSyncArchive.write(remote.path, await store.snapshot());
    final original = await remote.readAsBytes();
    client.files[RowSyncEngine.remotePath] = original;
    await protect();
    await db.update('tb_books', {'title': 'SECRET changed'}, where: 'id=2');
    await db.insert('tb_notes', noteRow(1, 'new-public-note'));
    await engine().synchronize();
    expect(client.files[RowSyncEngine.remotePath], original);
    expect(client.writes, 0);
    final batches =
        client.files.entries.where((e) => e.key != RowSyncEngine.remotePath);
    expect(batches, isNotEmpty);
    for (final entry in batches) {
      final file = File('${cache.path}/journal.db');
      await file.writeAsBytes(entry.value);
      final records = await RowSyncArchive.read(file.path);
      expect(
          records.any((r) =>
              r.id == 'md5:private' || r.data['book_id'] == 'md5:private'),
          false);
      expect(jsonEncode(records.map((r) => r.toMap()).toList()),
          isNot(contains('SECRET')));
    }
  });

  test('pending retry rebuilds public rows and never resends the private batch',
      () async {
    final staging = await cache.createTemp('pending-');
    final log =
        ImmutableSyncLog(client, staging, cache, durableDirectory: cache);
    client.beforeLogWrite = () async => throw StateError('interrupted');
    await expectLater(log.publish(await store.snapshot()), throwsStateError);
    final original = await log.readPendingFiles();
    expect(original.length, 1);
    await protect();
    client.beforeLogWrite = null;
    await engine().synchronize();
    expect(await log.readPendingFiles(), isEmpty);
    expect(client.files.keys.any((key) => key.endsWith(original.keys.single)),
        false);
    expect(jsonEncode((await uploaded()).map((r) => r.toMap()).toList()),
        isNot(contains('SECRET')));
  });

  test(
      'preview omits private values and cancellation leaves all data untouched',
      () async {
    await protect();
    final before = await store.snapshot();
    await expectLater(
        engine(onPreview: (context) async {
          expect(jsonEncode(context.local.map((r) => r.toMap()).toList()),
              isNot(contains('SECRET')));
          return const SyncPreviewDecision.cancel();
        }).synchronize(),
        throwsA(isA<SyncPreviewCancelled>()));
    expect(client.files, isEmpty);
    expect(sameSyncRecords(before, await store.snapshot()), true);
  });

  test('new privacy marks during preparation are applied before publishing',
      () async {
    var calls = 0;
    await engine(beforePublish: () async {
      if (++calls == 2) await protect();
    }).synchronize();
    expect(jsonEncode((await uploaded()).map((r) => r.toMap()).toList()),
        isNot(contains('SECRET')));
  });

  test('book aliases, orphan deletes and private-only groups/tags are excluded',
      () async {
    await protect();
    const records = [
      RowSyncRecord('book', 'md5:private', 1, 'a', false, {
        'file_md5': 'private',
        'file_path': 'file/private.epub',
        'group_id': 'g'
      }),
      RowSyncRecord('group', 'g', 1, 'a', false,
          {'parent_id': 'root', 'name': 'SECRET group'}),
      RowSyncRecord('tag_link', 'link', 1, 'a', false,
          {'line_height': 'md5:private', 'letter_spacing': 't'}),
      RowSyncRecord('tag', 't', 1, 'a', false, {'font_family': 'SECRET tag'}),
      RowSyncRecord('note', 'orphan-deleted', 1, 'a', true, {}),
      RowSyncRecord('position', 'md5:private', 1, 'a', false, {}),
      RowSyncRecord('review', 'md5:private', 1, 'a', false, {}),
      RowSyncRecord(
          'note', 'public', 1, 'a', false, {'book_id': 'md5:same-content'}),
    ];
    expect(PrivateBookSyncFilter(records).allowedRecords(records).single.id,
        'public');
  });

  test('alias closure protects both old and new identities without rebinding',
      () async {
    final local = await store.snapshot();
    await protect();
    final target = 'md5:aaa';
    final aliasRevision =
        'modu-book-alias-v1:${base64Url.encode(utf8.encode(target))}';
    final remote = [
      for (final r in local.where((r) => r.id == 'md5:private'))
        RowSyncRecord(r.kind, r.id, r.clock + 100, aliasRevision, true, r.data),
      for (final r in local.where((r) => r.id == 'md5:private'))
        RowSyncRecord(r.kind, target, r.clock + 101, 'new', r.deleted, r.data),
      RowSyncRecord('note', 'new-secret', 9999999999999, 'new', false, {
        ...local.firstWhere((r) => r.kind == 'note').data,
        'book_id': target,
        'content': 'PRIVATE remote'
      })
    ];
    await store.merge(remote, protectPrivateBooks: true);
    expect((await db.query('tb_books')).length, 2);
    expect((await db.query('tb_books', where: 'id=2')).single['is_deleted'], 0);
    expect((await db.query('tb_notes')).length, 2);
  });

  test('a pending note-only batch is private even without its book record',
      () async {
    final records = (await store.snapshot())
        .where((r) => r.kind == 'note' && r.data['book_id'] == 'md5:private')
        .toList();
    final staging = await cache.createTemp('note-pending-');
    final log =
        ImmutableSyncLog(client, staging, cache, durableDirectory: cache);
    client.beforeLogWrite = () async => throw StateError('interrupted');
    await expectLater(log.publish(records), throwsStateError);
    await protect();
    client.beforeLogWrite = null;
    await engine().synchronize();
    expect(await log.readPendingFiles(), isEmpty);
    expect(jsonEncode((await uploaded()).map((r) => r.toMap()).toList()),
        isNot(contains('SECRET')));
  });

  test(
      'damaged private state blocks all book transport without changing local rows',
      () async {
    SharedPreferences.setMockInitialValues(
        {PrivateLibrary.storageKey: '{broken'});
    await Prefs().initPrefs();
    expect(library.corrupt, true);
    await engine().synchronize();
    expect(client.files, isEmpty);
    expect((await db.query('tb_books')).length, 2);
    expect((await db.query('tb_notes')).length, 2);
  });

  test('private deleted rows are not allocated again by a public merge',
      () async {
    await store.snapshot();
    await protect();
    await db.delete('tb_notes', where: 'book_id=2');
    await db.delete('tb_books', where: 'id=2');
    final before = await store.snapshot();
    await store.merge([], protectPrivateBooks: true);
    expect((await db.query('tb_books')).length, 1);
    expect(sameSyncRecords(before, await store.snapshot()), true);
    await engine().synchronize();
    expect(jsonEncode((await uploaded()).map((r) => r.toMap()).toList()),
        isNot(contains('private')));
  });

  test('file replacement keeps its stable private sync identity excluded',
      () async {
    await protect();
    await db.update(
        'tb_books',
        {
          'file_md5': 'new-content',
          'file_path': 'file/new-content.epub',
          'title': 'SECRET replacement'
        },
        where: 'id=2');
    expect(
        library.canSyncBook(secret.copyWith(
            md5: 'new-content', filePath: 'file/new-content.epub')),
        false);
    await engine().synchronize();
    final text = jsonEncode((await uploaded()).map((r) => r.toMap()).toList());
    expect(text, isNot(contains('new-content')));
    expect(text, isNot(contains('SECRET')));
    await library.unlock();
    await library.setBooksPrivate([
      secret.copyWith(md5: 'new-content', filePath: 'file/new-content.epub')
    ], false);
    await engine().synchronize();
    expect(jsonEncode((await uploaded()).map((r) => r.toMap()).toList()),
        contains('SECRET replacement'));
  });

  test('privacy enabled after journal scan prevents cloud reclamation',
      () async {
    final transfer = CompactClient();
    final writer =
        ImmutableSyncLog(transfer, cache, cache, durableDirectory: cache);
    await writer.publish(await store.snapshot());
    final original = Map<String, List<int>>.from(transfer.files);
    var filtering = false;
    final guarded = ImmutableSyncLog(transfer, cache, cache,
        durableDirectory: cache,
        filteringNeeded: () => filtering,
        filterPending: (records) async => records);
    await guarded.read();
    filtering = true;
    expect(await guarded.reclaimReadBatches(), 0);
    expect(transfer.files, original);
    expect(transfer.removed, isEmpty);
  });

  test(
      'first sync after replacement protects books marked before metadata existed',
      () async {
    final fresh = await fixture(install: false);
    addTearDown(fresh.close);
    await fresh
        .insert('tb_books', {...bookRow(2, md5: 'private'), 'title': 'SECRET'});
    await fresh.insert('tb_notes', noteRow(2, 'SECRET new note'));
    await protect();
    await fresh.update(
        'tb_books',
        {
          'file_md5': 'first-replacement',
          'file_path': 'file/first-replacement.epub'
        },
        where: 'id=2');
    await fresh.transaction((txn) => RowSyncStore.install(txn));
    final freshStore = RowSyncStore(fresh);
    final snapshot = await freshStore.snapshot();
    final privateBook = snapshot
        .firstWhere((r) => r.id == 'md5:first-replacement' && r.kind == 'book');
    expect(privateBook.localId, 2);
    expect(privateBook.toMap().containsKey('local_id'), false);
    expect(PrivateBookSyncFilter(snapshot).allows(privateBook), false);
    await RowSyncEngine(store: freshStore, client: client, cache: cache)
        .synchronize();
    final records = await uploaded();
    expect(jsonEncode(records.map((r) => r.toMap()).toList()),
        isNot(contains('SECRET')));
    expect(jsonEncode(records.map((r) => r.toMap()).toList()),
        isNot(contains('first-replacement')));
    expect(records.any((r) => r.localId != null), false);
  });

  test('privacy enabled during compaction preserves every previous cloud batch',
      () async {
    final transfer = CompactClient();
    final writer =
        ImmutableSyncLog(transfer, cache, cache, durableDirectory: cache);
    final position =
        (await store.snapshot()).firstWhere((r) => r.kind == 'position');
    for (var i = 0; i < ImmutableSyncLog.compactAfterBatches; i++) {
      await writer.publish([
        RowSyncRecord(position.kind, position.id, position.clock + i,
            'position-$i', false, position.data)
      ]);
    }
    final original = Map<String, List<int>>.from(transfer.files);
    var filtering = false;
    final guarded = ImmutableSyncLog(transfer, cache, cache,
        durableDirectory: cache,
        filteringNeeded: () => filtering,
        filterPending: (records) async => records);
    await guarded.read();
    transfer.onUpload = (_) async => filtering = true;
    expect(await guarded.compactIfNeeded(), 0);
    for (final entry in original.entries) {
      expect(transfer.files[entry.key], entry.value);
    }
    expect(transfer.removed, isEmpty);
  });
}
