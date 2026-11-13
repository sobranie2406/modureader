import 'dart:io';
import 'package:modu_reader/utils/get_path/storage_migration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory source;
  late Directory target;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-migration-test-');
    source = await Directory('${root.path}/source').create();
    target = Directory('${root.path}/target');
    for (final name in [
      'databases/app_database.db',
      'ai/history.json',
      'file/书.epub'
    ]) {
      await File('${source.path}/$name').create(recursive: true);
      await File('${source.path}/$name').writeAsString(name);
    }
  });
  tearDown(() => root.delete(recursive: true));
  test('copies all data, verifies it and preserves the original', () async {
    expect(
        await performStorageMigration(
            sourcePath: source.path, destinationPath: target.path),
        isTrue);
    for (final name in [
      'databases/app_database.db',
      'ai/history.json',
      'file/书.epub'
    ]) {
      expect(await File('${source.path}/$name').readAsString(), name);
      expect(await File('${target.path}/$name').readAsString(), name);
    }
  });
  test('rejects occupied and overlapping targets without deleting data',
      () async {
    for (final path in [source.path, '${source.path}/nested', root.path]) {
      expect(
          await performStorageMigration(
              sourcePath: source.path, destinationPath: path),
          isFalse);
    }
    expect(
        await File('${source.path}/file/书.epub').readAsString(), 'file/书.epub');
  });
  test('copy failure keeps the source and removes only this attempt outputs',
      () async {
    await Link('${source.path}/unsupported-link').create('${source.path}/file');
    expect(
        await performStorageMigration(
            sourcePath: source.path, destinationPath: target.path),
        isFalse);
    expect(await target.list().isEmpty, isTrue);
    expect(await File('${source.path}/file/书.epub').exists(), isTrue);
  }, skip: Platform.isWindows);
}
