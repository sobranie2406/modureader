import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/book_local_sources.dart';
import 'package:anx_reader/service/book_source_actions.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';

void main() {
  late Directory dir;
  late File original;
  late Book book;
  late String previousPath;
  setUp(() async {
    previousPath = documentPath;
    dir = await Directory.systemTemp.createTemp('modu-source-actions-');
    documentPath = '${dir.path}/library';
    await Directory(documentPath).create();
    original =
        await File('${dir.path}/original.epub').writeAsString('original bytes');
    book = Book.mock().copyWith(
        filePath: 'file/remote-key.epub',
        md5: md5.convert(await original.readAsBytes()).toString(),
        review: 'keep review',
        groupId: 3,
        lastReadPosition: 'chapter2:10');
    await BookSources.initialize(Directory(documentPath));
    await BookSources.store!
        .save(book.md5, book.filePath, kind: 'linked', locator: original.path);
  });
  tearDown(() async {
    documentPath = previousPath;
    await BookSources.initialize(Directory('${dir.path}/reset'));
    await dir.delete(recursive: true);
  });
  test('copy changes only device source, survives restart and keeps original',
      () async {
    final before = book.toMap();
    await copyLinkedBookToLibrary(book);
    expect(book.isLinked, isFalse);
    expect(book.toMap(), before);
    expect(await File(book.fileFullPath).readAsString(), 'original bytes');
    expect(await original.readAsString(), 'original bytes');
    await BookSources.initialize(Directory(documentPath));
    expect(book.isLinked, isFalse);
    expect(await File(book.fileFullPath).readAsString(), 'original bytes');
  });
  test('changed original cannot replace an existing book identity', () async {
    await original.writeAsString('another book');
    await expectLater(
        copyLinkedBookToLibrary(book), throwsA(isA<FileSystemException>()));
    expect(book.isLinked, isTrue);
    expect(await Directory('$documentPath/file').list().toList(), isEmpty);
    expect(await original.readAsString(), 'another book');
  });
  test(
      'device removal preserves data and external bytes; internal removal keeps its label',
      () async {
    final before = book.toMap();
    await removeBookFromDevice(book);
    expect(book.isRemovedLocally, isTrue);
    expect(book.isLinked, isTrue);
    expect(await File(book.fileFullPath).exists(), isFalse);
    expect(await original.exists(), isTrue);
    expect(book.toMap(), before);
    await BookSources.store!
        .save(book.md5, book.filePath, kind: 'linked', locator: original.path);
    await copyLinkedBookToLibrary(book);
    final owned = File(book.fileFullPath);
    await removeBookFromDevice(book);
    expect(book.isLinked, isFalse);
    expect(book.isRemovedLocally, isTrue);
    expect(await owned.exists(), isFalse);
    expect(await original.exists(), isTrue);
    expect(book.toMap(), before);
  });
}
