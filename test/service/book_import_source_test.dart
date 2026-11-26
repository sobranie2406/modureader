import 'dart:io';

import 'package:modu_reader/service/book_import_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF imports keep filenames instead of unreliable embedded titles', () {
    for (final title in ['P3', '天', 'æµ‹è¯•', '正常的内部标题', 'Unknown', '']) {
      expect(importedBookTitle('/cache/倪海厦人纪系列之针灸.PDF', title), '倪海厦人纪系列之针灸');
    }
    expect(importedBookTitle('/cache/书名.修订版.pdf', 'P3'), '书名.修订版');
  });

  test('other book formats retain metadata titles and filename fallbacks', () {
    for (final extension in ['epub', 'mobi', 'azw3', 'fb2']) {
      final file = '/cache/文件名.$extension';
      expect(importedBookTitle(file, '书内标题'), '书内标题');
      for (final missing in ['Unknown', '', '  ']) {
        expect(importedBookTitle(file, missing), '文件名');
      }
    }
  });

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
    final second = await book('b/deeper/Novel.EPUB', 'second');
    await book('b/notes.markdown', 'notes');
    await book('b/novel.UMD', 'umd');
    await book('root.pdf', 'root book');
    await book('cover.jpg', 'not a book');
    await book('.hidden/book.pdf', 'hidden');
    if (!Platform.isWindows) {
      await Link(p.join(root.path, 'loop')).create(root.path);
      await Link(p.join(root.path, 'alias.epub')).create(first.path);
    }
    final entries = await discoverBookImportFiles([root.path, first.path]);
    expect(entries, hasLength(5));
    expect(entries.map((e) => e.name),
        containsAll(['Novel.EPUB', 'notes.markdown', 'novel.UMD']));
    expect(
        entries
            .where((e) => e.name == 'Novel.EPUB')
            .map((e) => e.label)
            .toSet(),
        hasLength(2));
    expect(
        entries
            .singleWhere(
                (entry) => entry.id == first.resolveSymbolicLinksSync())
            .collectionName,
        'a');
    expect(
        entries
            .singleWhere(
                (entry) => entry.id == second.resolveSymbolicLinksSync())
            .collectionName,
        'b');
    expect(
        entries.singleWhere((entry) => entry.name == 'root.pdf').collectionName,
        isNull);
  });

  test('native selection reads collection metadata independently of labels',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        MobileBookFolder.channel,
        (_) async => [
              {
                'id': 'a',
                'name': 'book.pdf',
                'label': 'book.pdf',
                'collectionName': '史书',
              },
              {'id': 'b', 'name': 'root.pdf', 'label': 'root.pdf'},
            ]);
    addTearDown(() =>
        messenger.setMockMethodCallHandler(MobileBookFolder.channel, null));

    final entries = (await MobileBookFolder.pick())!;
    expect(entries.map((entry) => entry.collectionName), ['史书', null]);
  });

  test(
      'selected same-name books keep separate bytes; importer cleanup preserves sources',
      () async {
    final first = await book('a/Novel.txt', 'first');
    final second = await book('b/Novel.txt', 'second');
    final entries = await discoverBookImportFiles([first.path, second.path]);
    expect(entries.map((entry) => entry.collectionName), everyElement(isNull));
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
