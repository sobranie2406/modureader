import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:anx_reader/service/sync/ai_settings_sync.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'row_sync_test.dart' show fixture, MemorySyncClient;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  const password = 'test-sync-passphrase';
  final config = jsonEncode({
    'url': 'https://library.example.test/books/',
    'username': 'reader',
    'password': 'library-test-secret',
    'allowHttp': false
  });
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => db.close());
  Future<RemoteLibrarySettingsSyncService> service() async =>
      RemoteLibrarySettingsSyncService(
          databaseProvider: () async => db,
          preferences: await SharedPreferences.getInstance());

  test('shared switch off never exports or restores library credentials',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LibraryConnectionStore.key, config);
    final sync = await service();
    expect(await sync.prepareLocalDatabase(enabled: false, password: null),
        isFalse);
    expect(
        await sync.restoreFromDownloadedDatabase(
            enabled: false, password: null),
        isFalse);
    expect(
        await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE name='tb_sync_secrets'"),
        isEmpty);
  });

  test(
      'separate encrypted record coexists with AI settings and restores on a fresh device',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LibraryConnectionStore.key, config);
    final sync = await service();
    await AiSettingsSyncService(
            databaseProvider: () async => db, preferences: prefs)
        .prepareLocalDatabase(enabled: true, password: password);
    expect(await sync.prepareLocalDatabase(enabled: true, password: password),
        isTrue);
    final rows = await db.query(aiSettingsSyncTable);
    expect(rows.length, 2);
    expect(jsonEncode(rows), isNot(contains('library-test-secret')));
    expect(jsonEncode(rows), isNot(contains('library.example.test')));
    expect(await sync.prepareLocalDatabase(enabled: true, password: password),
        isFalse);
    SharedPreferences.setMockInitialValues({});
    final fresh = await service();
    expect(await fresh.prepareLocalDatabase(enabled: true, password: password),
        isFalse,
        reason:
            'A never-configured client must not erase remote configuration');
    expect(await db.query(aiSettingsSyncTable), rows);
    expect(
        await fresh.restoreFromDownloadedDatabase(
            enabled: true, password: password),
        isTrue);
    expect(
        (await LibraryConnectionStore.load())!.password, 'library-test-secret');
  });

  test(
      'wrong encryption password changes neither saved connection nor ciphertext',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LibraryConnectionStore.key, config);
    final sync = await service();
    await sync.prepareLocalDatabase(enabled: true, password: password);
    final before = await db.query(aiSettingsSyncTable);
    await prefs.setString(LibraryConnectionStore.key, '');
    await expectLater(
        sync.restoreFromDownloadedDatabase(enabled: true, password: 'wrong'),
        throwsA(isA<AiSyncDecryptionException>()));
    expect(prefs.getString(LibraryConnectionStore.key), '');
    await expectLater(
        sync.prepareLocalDatabase(enabled: true, password: 'wrong'),
        throwsA(isA<AiSyncDecryptionException>()));
    expect(await db.query(aiSettingsSyncTable), before);
  });

  test(
      'explicit clear propagates while old/missing records preserve the local connection',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LibraryConnectionStore.key, config);
    final sync = await service();
    expect(
        await sync.restoreFromDownloadedDatabase(
            enabled: true, password: password),
        isFalse);
    expect(prefs.getString(LibraryConnectionStore.key), config);
    await sync.prepareLocalDatabase(enabled: true, password: password);
    await LibraryConnectionStore.clear();
    await sync.prepareLocalDatabase(enabled: true, password: password);
    SharedPreferences.setMockInitialValues(
        {LibraryConnectionStore.key: config});
    final other = await service();
    await other.restoreFromDownloadedDatabase(
        enabled: true, password: password);
    expect(await LibraryConnectionStore.load(), isNull);
  });

  test(
      'invalid authenticated connection is rejected before local settings change',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(LibraryConnectionStore.key, config);
    final sync = await service();
    await expectLater(
        sync.applyPreferences({
          LibraryConnectionStore.key:
              jsonEncode({'url': 'https://user:secret@example.test/'})
        }),
        throwsFormatException);
    expect(prefs.getString(LibraryConnectionStore.key), config);
  });

  for (final atomic in [true, false]) {
    test(
        'actual row-sync pipeline carries encrypted library config and deletion between devices (atomic=$atomic)',
        () async {
      final a = await fixture();
      final b = await fixture();
      final cache = await Directory.systemTemp.createTemp('modu-library-sync-');
      try {
        SharedPreferences.setMockInitialValues(
            {LibraryConnectionStore.key: config});
        final prefsA = await SharedPreferences.getInstance();
        SharedPreferences.setMockInitialValues({});
        final prefsB = await SharedPreferences.getInstance();
        final syncA = RemoteLibrarySettingsSyncService(
            databaseProvider: () async => a, preferences: prefsA);
        final syncB = RemoteLibrarySettingsSyncService(
            databaseProvider: () async => b, preferences: prefsB);
        final server = MemorySyncClient()..atomic = atomic;
        final engineA =
            RowSyncEngine(store: RowSyncStore(a), client: server, cache: cache);
        final engineB =
            RowSyncEngine(store: RowSyncStore(b), client: server, cache: cache);
        await syncA.prepareLocalDatabase(enabled: true, password: password);
        await engineA.synchronize();
        expect(
            server.files.values
                .map((bytes) => utf8.decode(bytes, allowMalformed: true))
                .join(),
            isNot(contains('library-test-secret')));
        await syncB.prepareLocalDatabase(enabled: true, password: password);
        await engineB.synchronize();
        await syncB.restoreFromDownloadedDatabase(
            enabled: true, password: password);
        expect(prefsB.getString(LibraryConnectionStore.key), config);
        await prefsA.setString(LibraryConnectionStore.key, '');
        await syncA.prepareLocalDatabase(enabled: true, password: password);
        await engineA.synchronize();
        expect(
            await syncB.prepareLocalDatabase(enabled: true, password: password),
            isFalse);
        await engineB.synchronize();
        await syncB.restoreFromDownloadedDatabase(
            enabled: true, password: password);
        expect(prefsB.getString(LibraryConnectionStore.key), '');
      } finally {
        await a.close();
        await b.close();
        await cache.delete(recursive: true);
      }
    });
  }
}
