import 'dart:io';

import 'package:modu_reader/service/book_import_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory cache;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-quiet-import-');
    cache = await Directory(p.join(root.path, 'cache')).create();
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<File> source(String name, String content) async {
    final file = File(p.join(root.path, name));
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }

  test(
      'dropped folders import nested books directly, skipping duplicates and retaining originals',
      () async {
    final first = await source('books/a/book.epub', 'first');
    final duplicate = await source('books/b/book.epub', 'first');
    final second = await source('books/b/book.pdf', 'second');
    await source('books/cover.png', 'image');
    final seen = <String>{};
    final imported = <String>[];
    final errors = <Object>[];
    final entries =
        await discoverBookImportFiles([p.join(root.path, 'books'), first.path]);
    final count = await importBookEntriesQuietly(
      entries,
      cache,
      isDuplicate: (file) async => seen.contains(await file.readAsString()),
      importFile: (file) async {
        final text = await file.readAsString();
        imported.add(text);
        seen.add(text);
        await file.delete(); // Real importer consumes staged files.
      },
      onError: (_, error, __) => errors.add(error),
    );
    expect(count, 2);
    expect(imported, ['first', 'second']);
    expect(errors, isEmpty);
    expect(await first.readAsString(), 'first');
    expect(await duplicate.readAsString(), 'first');
    expect(await second.readAsString(), 'second');
    expect(await cache.list().toList(), isEmpty);
  });

  test(
      'copy, duplicate-check and parser failures are logged; later books still import',
      () async {
    final vanished = await source('a.pdf', 'missing');
    final unreadable = await source('b.pdf', 'unreadable');
    final invalid = await source('c.pdf', 'invalid');
    final good = await source('d.pdf', 'good');
    final entries = await discoverBookImportFiles(
        [vanished.path, unreadable.path, invalid.path, good.path]);
    await vanished.delete();
    final errors = <String>[];
    final imported = <String>[];
    final count = await importBookEntriesQuietly(
      entries,
      cache,
      isDuplicate: (file) async {
        if (await file.readAsString() == 'unreadable') {
          throw const FileSystemException('cannot hash');
        }
        return false;
      },
      importFile: (file) async {
        if (await file.readAsString() == 'invalid') {
          throw const FormatException('invalid PDF');
        }
        imported.add(await file.readAsString());
      },
      onError: (entry, _, __) => errors.add(entry.name),
    );
    expect(count, 1);
    expect(errors, ['a.pdf', 'b.pdf', 'c.pdf']);
    expect(imported, ['good']);
    expect(await invalid.readAsString(), 'invalid');
    expect(await good.readAsString(), 'good');
    expect(await cache.list().toList(), isEmpty);
  });

  test('unsupported entries are ignored without invoking import callbacks',
      () async {
    final file = await source('cover.png', 'image');
    final count = await importBookEntriesQuietly(
      [
        BookImportEntry(id: file.path, name: 'cover.png', label: 'cover.png'),
      ],
      cache,
      isDuplicate: (_) async => throw StateError('must not check'),
      importFile: (_) async => throw StateError('must not import'),
      onError: (_, error, __) => fail('$error'),
    );
    expect(count, 0);
    expect(await file.readAsString(), 'image');
    expect(await cache.list().toList(), isEmpty);
  });
}
