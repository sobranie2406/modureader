import 'dart:io';
import 'package:anx_reader/service/ocr/document_reflow_store.dart';
import 'package:anx_reader/service/notes/reading_link.dart';
import 'package:anx_reader/models/book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  setUp(() async =>
      directory = await Directory.systemTemp.createTemp('modu-reflow-test-'));
  tearDown(() async => directory.delete(recursive: true));
  test(
      'cache survives reopening, isolates books/pages/model profiles and preserves note revisions',
      () async {
    final store = DocumentReflowStore('book-a', directory: directory);
    final old =
        DocumentReflowPage(page: 3, ocr: true, rawText: '第一行\n第二行。\n\n第二段');
    final anchor = DocumentReflowAnchor(3, true, old.revision, 0, 3);
    await store.save(old, 'ocr-v4');
    expect(
        (await DocumentReflowStore('book-a', directory: directory)
                .read(3, 'ocr-v4'))!
            .text,
        old.text);
    expect(await store.read(3, 'ocr-v5'), isNull);
    expect(await store.read(2, 'ocr-v4'), isNull);
    expect(
        await DocumentReflowStore('book-b', directory: directory)
            .read(3, 'ocr-v4'),
        isNull);
    await store.save(
        DocumentReflowPage(page: 3, ocr: true, rawText: '新的识别结果'), 'ocr-v4');
    expect((await store.read(3, 'ocr-v4'))!.text, '新的识别结果');
    expect((await store.readAnchor(anchor))!.text, old.text);
  });
  test(
      'anchors are strict, bounded, distinct from CFI and supported in exported reading links',
      () {
    final page = DocumentReflowPage(page: 1, ocr: false, rawText: '中文 text 🌱');
    final anchor = DocumentReflowAnchor(1, false, page.revision, 0, 2);
    expect(DocumentReflowAnchor.parse(anchor.encode())!.matches(page), true);
    for (final bad in [
      'epubcfi(/6/2)',
      '${anchor.encode()}:extra',
      anchor.encode().replaceFirst(':1:0:', ':-1:0:'),
      DocumentReflowAnchor(1, false, page.revision, 4, 2).encode(),
      DocumentReflowAnchor(1, false, '../oops', 0, 2).encode()
    ]) {
      expect(DocumentReflowAnchor.parse(bad), isNull);
    }
    final link = ReadingLink.forBook(Book.mock(), anchor.encode());
    expect(link, isNotNull);
    expect(ReadingLink.parse(link!).cfi, anchor.encode());
    expect(DocumentReflowAnchor(1, false, page.revision, 0, 999).matches(page),
        false);
  });
  test(
      'damaged cache and mismatching revisions are not used as annotation positions',
      () async {
    final store = DocumentReflowStore('book', directory: directory);
    final page =
        DocumentReflowPage(page: 0, ocr: false, rawText: 'Original text');
    expect(DocumentReflowPage.decode({...page.toJson(), 'rawText': 'Changed'}),
        isNull);
    await store.save(page, 'text');
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      await file.writeAsString('{broken');
    }
    expect(await store.read(0, 'text'), isNull);
    expect(
        await store
            .readAnchor(DocumentReflowAnchor(0, false, page.revision, 0, 3)),
        isNull);
  });
}
