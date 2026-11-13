import 'dart:io';

import 'package:modu_reader/service/sync/harmony_database_snapshot.dart';
import 'package:modu_reader/service/sync/row_sync_engine.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'row_sync_test.dart' show fixture, MemorySyncClient;

class _NativeBackup extends Fake implements Database {
  _NativeBackup(this.backup);
  final Future<void> Function(String) backup;
  final List<String> commands = [];
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    commands.add(sql);
    expect(sql, 'MODU_BACKUP_DATABASE');
    expect(arguments, hasLength(1));
    await backup(arguments!.single as String);
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory root;
  late Database source;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-snapshot-test-');
    source = await fixture(path: '${root.path}/live.db');
    await source.rawQuery('PRAGMA journal_mode=WAL');
    await source.execute('PRAGMA wal_autocheckpoint=0');
    await source
        .insert('tb_notes', {'book_id': 1, 'content': 'committed in WAL'});
  });
  tearDown(() async {
    await source.close();
    await root.delete(recursive: true);
  });

  test('native request returns a standalone snapshot with recent data',
      () async {
    // SQLite simulates the native online backup at this test boundary; no
    // assertion here substitutes for running RdbStore.backup on HarmonyOS.
    final native = _NativeBackup((path) =>
        source.execute("VACUUM INTO '${path.replaceAll("'", "''")}'"));
    final path = await createHarmonyDatabaseSnapshot(native, root);
    expect(native.commands, ['MODU_BACKUP_DATABASE']);
    final copy = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    try {
      expect(
          (await copy.rawQuery('PRAGMA integrity_check')).single.values.single,
          'ok');
      expect(
          (await copy.query('tb_notes')).single['content'], 'committed in WAL');
      expect(await copy.getVersion(), await source.getVersion());
    } finally {
      await copy.close();
    }
    expect(source.isOpen, isTrue);
    expect(root.listSync().whereType<Directory>(), isEmpty);
  });

  for (final outcome in [
    'throw',
    'missing',
    'bad_header',
    'truncated',
    'wal'
  ]) {
    test('$outcome native snapshot fails closed and removes only staging',
        () async {
      final native = _NativeBackup((path) async {
        if (outcome == 'throw') throw StateError('backup failed');
        if (outcome == 'missing') return;
        if (outcome == 'bad_header') {
          await File(path).writeAsString('not sqlite');
          return;
        }
        await source.execute("VACUUM INTO '${path.replaceAll("'", "''")}'");
        if (outcome == 'truncated') {
          final file = await File(path).open(mode: FileMode.append);
          await file.truncate(100);
          await file.close();
        } else {
          await File('$path-wal').writeAsString('pending data');
        }
      });
      await expectLater(
          createHarmonyDatabaseSnapshot(native, root), throwsA(anything));
      expect(
          root.listSync().where(
              (entry) => p.basename(entry.path).startsWith('modu-snapshot-')),
          isEmpty);
      expect((await source.query('tb_notes')).single['content'],
          'committed in WAL');
    });
  }

  test('failed backup prevents local merge and cloud publication', () async {
    final remote = await fixture();
    final client = MemorySyncClient();
    final cache = await Directory('${root.path}/sync').create();
    try {
      await remote.update('tb_books', {'title': 'Remote edit'});
      await RowSyncEngine(
              store: RowSyncStore(remote), client: client, cache: cache)
          .synchronize();
      final beforeCloud = Map.of(client.files);
      final beforeLocal = await source.query('tb_books');
      final beforeNotes = await source.query('tb_notes');
      var backups = 0;
      await expectLater(
          RowSyncEngine(
            store: RowSyncStore(source),
            client: client,
            cache: cache,
            beforeMerge: () async {
              backups++;
              await createHarmonyDatabaseSnapshot(_NativeBackup((_) async {
                throw StateError('native backup failed');
              }), root);
            },
          ).synchronize(),
          throwsStateError);
      expect(backups, 1);
      expect(await source.query('tb_books'), beforeLocal);
      expect(await source.query('tb_notes'), beforeNotes);
      expect(client.files, beforeCloud);
    } finally {
      await remote.close();
    }
  });

  test('existing platform snapshot implementation is behind OHOS early return',
      () {
    final source = File('lib/dao/database.dart').readAsStringSync();
    final method = source.substring(
        source.indexOf('static Future<String> prepareUploadSnapshot()'));
    expect(
        method,
        contains(
            'if (AnxPlatform.isOhos) {\n        return await createHarmonyDatabaseSnapshot(db, cacheDir);\n      }'));
    expect(method.indexOf('createHarmonyDatabaseSnapshot'),
        lessThan(method.indexOf('VACUUM INTO')));
  });
}
