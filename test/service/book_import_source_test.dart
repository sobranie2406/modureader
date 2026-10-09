import 'dart:io';

import 'package:anx_reader/service/book_import_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-import-test-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<File> book(String name, String contents) async {
    final file = File(p.join(root.path, name));
    await file.parent.create(recursive: true);
    return file.writeAsString(contents);
  }

  test(
      'folder scan includes supported nested books, deduplicates overlapping drops, skips links',
      () async {
    final first = await book('a/Novel.EPUB', 'first');
    await book('b/Novel.EPUB', 'second');
    await book('b/notes.markdown', 'notes');
    await book('b/novel.UMD', 'umd');
    await book('cover.jpg', 'not a book');
    await book('.hidden/book.pdf', 'hidden');
    if (!Platform.isWindows) {
      await Link(p.join(root.path, 'loop')).create(root.path);
      await Link(p.join(root.path, 'alias.epub')).create(first.path);
    }
    final entries = await discoverBookImportFiles([root.path, first.path]);
    expect(entries, hasLength(4));
    expect(entries.map((e) => e.name),
        containsAll(['Novel.EPUB', 'notes.markdown', 'novel.UMD']));
    expect(
        entries
            .where((e) => e.name == 'Novel.EPUB')
            .map((e) => e.label)
            .toSet(),
        hasLength(2));
  });

  test(
      'selected same-name books keep separate bytes; importer cleanup preserves sources',
      () async {
    final first = await book('a/Novel.txt', 'first');
    final second = await book('b/Novel.txt', 'second');
    final entries = await discoverBookImportFiles([first.path, second.path]);
    final staged = await stageBookImportFiles(entries, root);
    expect(staged[0].path, isNot(staged[1].path));
    expect(await staged[0].readAsString(), 'first');
    expect(await staged[1].readAsString(), 'second');
    for (final file in staged) {
      await file.delete();
    }
    expect(await first.readAsString(), 'first');
    expect(await second.readAsString(), 'second');
  });

  test('copy failure removes partial staging but retains original books',
      () async {
    final first = await book('book.pdf', 'original');
    final entries = await discoverBookImportFiles([first.path]);
    entries.add(BookImportEntry(
        id: p.join(root.path, 'missing.pdf'),
        name: 'missing.pdf',
        label: 'missing.pdf'));
    await expectLater(stageBookImportFiles(entries, root),
        throwsA(isA<FileSystemException>()));
    expect(await first.readAsString(), 'original');
    expect(await root.list().where((e) => e is Directory).toList(), isEmpty);
  });
}
