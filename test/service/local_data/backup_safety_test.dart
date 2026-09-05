import 'dart:io';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:anx_reader/service/local_data/backup_safety.dart';
import 'package:anx_reader/service/sync/ai_settings_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-backup-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Archive fixtureArchive(String name) => Archive()
    ..addFile(ArchiveFile('databases/app_database.db', 1, [1]))
    ..addFile(ArchiveFile(name, 1, [1]));

  for (final name in [
    '../outside',
    '/tmp/outside',
    'file/../../outside',
    r'file\..\outside',
    'C:/outside',
    'unknown/file'
  ]) {
    test('rejects unsafe archive path $name before extraction', () {
      expect(() => validateBackupArchive(fixtureArchive(name)),
          throwsFormatException);
    });
  }
  test('rejects incomplete and symbolic-link archives', () {
    expect(() => validateBackupArchive(Archive()), throwsFormatException);
    final archive = fixtureArchive('file/book.epub');
    archive.last.isSymbolicLink = true;
    expect(() => validateBackupArchive(archive), throwsFormatException);
    expect(() => validateBackupArchive(fixtureArchive('file/book.epub')),
        returnsNormally);
  });
  test('settings failure rolls back every directory and preserves old bytes',
      () async {
    final incoming = Directory('${root.path}/incoming');
    final target = Directory('${root.path}/current');
    for (final name in ['file', 'databases']) {
      await Directory('${incoming.path}/$name').create(recursive: true);
      await Directory('${target.path}/$name').create(recursive: true);
      await File('${incoming.path}/$name/data').writeAsString('new-$name');
      await File('${target.path}/$name/data').writeAsString('old-$name');
    }
    final transaction = BackupDirectoryTransaction();
    await transaction.stage(incoming, {
      for (final name in ['file', 'databases'])
        name: Directory('${target.path}/$name')
    });
    await expectLater(transaction.commit(applySettings: () async {
      throw StateError('disk or settings failure');
    }), throwsStateError);
    for (final name in ['file', 'databases']) {
      expect(
          await File('${target.path}/$name/data').readAsString(), 'old-$name');
    }
  });
  test('successful replacement retains a recoverable previous directory',
      () async {
    final incoming = Directory('${root.path}/incoming/file');
    final target = Directory('${root.path}/current/file');
    await incoming.create(recursive: true);
    await target.create(recursive: true);
    await File('${incoming.path}/book').writeAsString('new');
    await File('${target.path}/book').writeAsString('old');
    final transaction = BackupDirectoryTransaction();
    await transaction.stage(incoming.parent, {'file': target});
    await transaction.commit(applySettings: () async {});
    expect(await File('${target.path}/book').readAsString(), 'new');
    expect(
        await File('${transaction.recoveryPaths.single}/book').readAsString(),
        'old');
  });
  test('validates SQLite integrity, required schema and path boundaries',
      () async {
    sqfliteFfiInit();
    final directory = Directory('${root.path}/databases');
    await directory.create();
    final dbPath = '${directory.path}/app_database.db';
    final db = await databaseFactoryFfi.openDatabase(dbPath);
    await db.execute(
        'CREATE TABLE tb_books(file_path TEXT, cover_path TEXT, is_deleted INTEGER)');
    for (final table in [
      'tb_notes',
      'tb_reading_time',
      'tb_themes',
      'tb_groups'
    ]) {
      await db.execute('CREATE TABLE $table(id INTEGER)');
    }
    await db.close();
    await validateBackupDatabase(root, factory: databaseFactoryFfi);
    final edit = await databaseFactoryFfi.openDatabase(dbPath);
    await edit.setVersion(999);
    await edit.close();
    await expectLater(
        validateBackupDatabase(root,
            factory: databaseFactoryFfi, maxSchemaVersion: 7),
        throwsFormatException);
    final missing = await databaseFactoryFfi.openDatabase(dbPath);
    await missing.setVersion(7);
    await missing.insert(
        'tb_books', {'file_path': 'file/missing.epub', 'is_deleted': 0});
    await missing.close();
    await expectLater(validateBackupDatabase(root, factory: databaseFactoryFfi),
        throwsFormatException);
    final unsafe = await databaseFactoryFfi.openDatabase(dbPath);
    await unsafe.delete('tb_books');
    await unsafe.insert('tb_books', {'file_path': 'file/../../outside'});
    await unsafe.close();
    await expectLater(validateBackupDatabase(root, factory: databaseFactoryFfi),
        throwsFormatException);
  });
  test('default portable backup omits credential-bearing containers', () {
    final source = <String, dynamic>{
      'aiProviders': 'secret',
      'webdavInfo': 'password',
      'onlineTtsConfig_custom': 'key',
      'translateServiceConfig_baidu': 'key',
      'vectorModelConfig': 'key',
      'syncAiSettingsEncryptionPassword': 'pw',
      'customApiKey': 'key',
      'themeMode': 'dark',
      'readAnySkillPrompts': 'prompt',
      'aiMaxTokens': 4096,
    };
    expect(withoutBackupCredentials(source), {
      'themeMode': 'dark',
      'readAnySkillPrompts': 'prompt',
      'aiMaxTokens': 4096
    });
    expect(source['aiProviders'], 'secret');
  });
  test(
      'encrypted preferences preserve typed values but contain no clear-text keys',
      () async {
    final backup = {
      '__prefsBackupVersion': 1,
      'aiProviders': {'type': 'string', 'value': 'fixture-secret-key'}
    };
    final cipher = AiSettingsSyncCipher();
    final encrypted = await cipher.encrypt(backup, 'fixture-long-password');
    expect(encrypted, isNot(contains('fixture-secret-key')));
    expect(encrypted, isNot(contains('fixture-long-password')));
    expect(await cipher.decrypt(encrypted, 'fixture-long-password'), backup);
    await expectLater(cipher.decrypt(encrypted, 'wrong-password'),
        throwsA(isA<AiSyncDecryptionException>()));
  });
  test('rejects invalid typed preferences before any writes', () {
    expect(
        () => validatePreferencesBackup(jsonDecode(
            '{"__prefsBackupVersion":1,"theme":{"type":"stringList","value":[1]}}')),
        throwsFormatException);
  });
}
