import 'dart:io';

import 'package:modu_reader/service/sync/row_sync_engine.dart';
import 'package:modu_reader/service/sync/row_sync_record.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/src/factory.dart';

import 'row_sync_test.dart' show fixture;

// Model the pinned OHOS plugin's directory restriction, using real SQLite for
// all archive queries, validation, transactions and legacy migration.
class DatabaseDirectoryFactory implements SqfliteDatabaseFactory {
  DatabaseDirectoryFactory(this.root);
  final String root;
  final opened = <String>[];

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) {
    if (!p.isWithin(root, path)) throw StateError('outside database root');
    opened.add(path);
    return databaseFactoryFfi.openDatabase(path, options: options);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  sqfliteFfiInit();
  late Directory temp, root, cache;
  late DatabaseDirectoryFactory factory;
  late Database live;
  late List<RowSyncRecord> records;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('modu-harmony-archive-test-');
    root = await Directory('${temp.path}/database').create();
    cache = await Directory('${temp.path}/cache').create();
    factory = DatabaseDirectoryFactory(root.path);
    databaseFactoryOrNull = factory;
    live = await fixture(path: '${root.path}/app_database.db');
    records = await RowSyncStore(live).snapshot();
  });
  tearDown(() async {
    expect(
        sameSyncRecords(records, await RowSyncStore(live).snapshot()), isTrue,
        reason: 'archive operations must not change the live library');
    await live.close();
    databaseFactoryOrNull = databaseFactoryFfi;
    await temp.delete(recursive: true);
  });

  Future<void> expectClean() async {
    expect(
        await root
            .list()
            .where((e) => p.basename(e.path).startsWith('modu-sync-archive-'))
            .toList(),
        isEmpty);
  }

  test('cache path fails directly; staged archive is portable and complete',
      () async {
    final output = '${cache.path}/upload.db';
    await expectLater(RowSyncArchive.write(output, records), throwsStateError);
    await RowSyncArchive.write(output, records, databaseDirectory: root);
    final original = await File(output).readAsBytes();
    expect(
        sameSyncRecords(records,
            await RowSyncArchive.read(output, databaseDirectory: root)),
        isTrue);
    expect(await File(output).readAsBytes(), original);
    // Other platforms read the exact copied file without staging or sidecars.
    databaseFactoryOrNull = databaseFactoryFfi;
    expect(sameSyncRecords(records, await RowSyncArchive.read(output)), isTrue);
    expect(await File('$output-wal').exists(), isFalse);
    await expectClean();
  });

  test('same-named concurrent downloads use different native handle names',
      () async {
    final a = await Directory('${cache.path}/a').create();
    final b = await Directory('${cache.path}/b').create();
    final paths = ['${a.path}/download.db', '${b.path}/download.db'];
    final changed = records
        .map((r) => RowSyncRecord(
            r.kind, r.id, r.clock + 1, 'second', r.deleted, r.data))
        .toList();
    await Future.wait([
      RowSyncArchive.write(paths[0], records, databaseDirectory: root),
      RowSyncArchive.write(paths[1], changed, databaseDirectory: root),
    ]);
    factory.opened.clear();
    final restored = await Future.wait(paths
        .map((path) => RowSyncArchive.read(path, databaseDirectory: root)));
    expect(sameSyncRecords(records, restored[0]), isTrue);
    expect(sameSyncRecords(changed, restored[1]), isTrue);
    expect(factory.opened.map(p.basename).toSet().length, 2);
    await expectClean();
  });

  test('legacy migration operates only on a disposable copy', () async {
    final input = '${cache.path}/database7.db';
    final old = await fixture(install: false, path: input);
    await old.close();
    final before = await File(input).readAsBytes();
    final migrated =
        await RowSyncArchive.read(input, legacy: true, databaseDirectory: root);
    expect(migrated.where((r) => r.kind == 'book').length, 1);
    expect(await File(input).readAsBytes(), before);
    await expectClean();
  });

  test('corrupt and oversized archives fail closed and leave input intact',
      () async {
    final input = File('${cache.path}/invalid.db');
    await input.writeAsString('not a database');
    await expectLater(RowSyncArchive.read(input.path, databaseDirectory: root),
        throwsA(isA<DatabaseException>()));
    expect(await input.readAsString(), 'not a database');
    await expectClean();
    final handle = await input.open(mode: FileMode.write);
    await handle.truncate(64 * 1024 * 1024 + 1);
    await handle.close();
    factory.opened.clear();
    await expectLater(RowSyncArchive.read(input.path, databaseDirectory: root),
        throwsFormatException);
    expect(factory.opened, isEmpty);
    await expectClean();
  });

  test('failed write never replaces destination and cleans staging', () async {
    final output = File('${cache.path}/upload.db');
    await output.writeAsString('previous transport');
    await expectLater(
        RowSyncArchive.write(output.path,
            [const RowSyncRecord('invalid', '', -1, '', false, {})],
            databaseDirectory: root),
        throwsFormatException);
    expect(await output.readAsString(), 'previous transport');
    await expectClean();
  });
}
