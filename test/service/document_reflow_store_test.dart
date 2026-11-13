import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:modu_reader/service/ocr/document_text_geometry.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:modu_reader/service/notes/reading_link.dart';
import 'package:modu_reader/models/book.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  setUp(() async =>
      directory = await Directory.systemTemp.createTemp('modu-reflow-test-'));
  tearDown(() async => directory.delete(recursive: true));
  test('cached OCR upgrades without recognition and old note revisions survive',
      () async {
    final store = DocumentReflowStore('book', directory: directory);
    final old = DocumentReflowPage(
        page: 0, ocr: true, layoutVersion: 3, rawText: '同一段第一句。\n同一段第二句。');
    final anchor = old.anchor(0, 2);
    await store.save(old, 'ocr');
    final upgraded = (await store.read(0, 'ocr'))!;
    expect(upgraded.layoutVersion, 4);
    expect(upgraded.text, '同一段第一句。同一段第二句。');
    final original = (await store.readAnchor(anchor))!;
    expect(original.text, '同一段第一句。\n\n同一段第二句。');
    expect(original.revision, old.revision);
    expect((await store.read(0, 'ocr'))!.revision, upgraded.revision);
  });
  test(
      'saved pages survive reopening and profile changes, isolate books and preserve note revisions',
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
    expect((await store.read(3, 'ocr-v5'))!.text, old.text);
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
    await expectLater(store.read(0, 'text'), throwsFormatException);
    await expectLater(store.save(page, 'text'), throwsFormatException);
    await expectLater(
        store.readAnchor(DocumentReflowAnchor(0, false, page.revision, 0, 3)),
        throwsFormatException);
    expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .single
            .readAsStringSync(),
        '{broken');
  });

  test(
      'one book file keeps numeric source-page order and exports edited Unicode text',
      () async {
    final store = DocumentReflowStore('book', directory: directory);
    for (final number in [10, 0, 3]) {
      await store.save(
          DocumentReflowPage(page: number, ocr: true, rawText: '原文$number'),
          'model-a');
    }
    final original = (await store.read(0, ''))!;
    await store.saveEdit(original, '校对繁體𠀀\n第二行');
    final reopened = DocumentReflowStore('book', directory: directory);
    expect((await reopened.read(0, 'new-model-and-crop'))!.editedText,
        '校对繁體𠀀\n第二行');
    expect((await reopened.readAnchor(original.anchor(0, 2)))!.text, '原文0');
    expect(
        await reopened.exportTxt(),
        '第1页\n────────────────────\n校对繁體𠀀\n第二行\n────────────────────\n\n'
        '第4页\n────────────────────\n原文3\n────────────────────\n\n'
        '第11页\n────────────────────\n原文10\n────────────────────');
    final before = await reopened.syncSnapshot();
    expect(
        await reopened.exportText(format: DocumentTextExportFormat.markdown),
        '## 第1页\n\n校对繁體𠀀\n第二行\n\n---\n\n'
        '## 第4页\n\n原文3\n\n---\n\n'
        '## 第11页\n\n原文10\n');
    expect(await reopened.syncSnapshot(), before,
        reason: 'Neither export format changes cached pages or revisions');
    final files =
        directory.listSync(recursive: true).whereType<File>().toList();
    expect(files.length, 1);
    expect(files.single.path, endsWith('/book.json'));
  });

  test('empty saved text exports nothing in either format', () async {
    final store = DocumentReflowStore('empty', directory: directory);
    for (final format in DocumentTextExportFormat.values) {
      expect(await store.exportText(format: format), isEmpty);
    }
  });

  test('concurrent page saves and stale edits cannot overwrite unrelated work',
      () async {
    await Future.wait(List.generate(
        8,
        (i) => DocumentReflowStore('book', directory: directory).save(
            DocumentReflowPage(page: i, ocr: true, rawText: 'Page $i'), '')));
    final store = DocumentReflowStore('book', directory: directory);
    for (var i = 0; i < 8; i++) {
      expect((await store.read(i, ''))!.text, 'Page $i');
    }
    final old = (await store.read(0, ''))!;
    await store.saveEdit(old, 'corrected');
    await expectLater(store.saveEdit(old, 'stale'), throwsStateError);
    expect((await store.read(0, ''))!.text, 'corrected');
  });

  test(
      'recognizing a corrected page replaces only its current version and keeps all note versions',
      () async {
    final store = DocumentReflowStore('book', directory: directory);
    final original =
        DocumentReflowPage(page: 0, ocr: true, rawText: 'Original');
    await store.save(original, '');
    final edited = await store.saveEdit(original, 'Corrected');
    await store.save(
        DocumentReflowPage(page: 1, ocr: true, rawText: 'Other'), '');
    await store.save(
        DocumentReflowPage(page: 0, ocr: true, rawText: 'Recognized again'),
        '');
    expect((await store.read(0, ''))!.editedText, isNull);
    expect((await store.read(1, ''))!.text, 'Other');
    expect((await store.readAnchor(original.anchor(0, 2)))!.text, 'Original');
    expect((await store.readAnchor(edited.anchor(0, 2)))!.text, 'Corrected');
  });

  test(
      'editing preserves unchanged image regions and never invents a position for replacement text',
      () async {
    const a = DocumentImageRect(.1, .1, .5, .1),
        b = DocumentImageRect(.1, .3, .5, .1);
    final original = DocumentReflowPage(
        page: 0,
        ocr: true,
        rawText: 'ABCD',
        rawRegions: const [
          DocumentTextRegion(0, 2, a),
          DocumentTextRegion(2, 4, b)
        ]);
    final store = DocumentReflowStore('book', directory: directory);
    await store.save(original, '');
    final edited = await store.saveEdit(original, 'XYZCD');
    expect(edited.anchor(0, 3).rects, isEmpty);
    expect(edited.anchor(3, 5).rects.single.toJson(), b.toJson());
    expect(
        (await store.readAnchor(original.anchor(0, 2)))!
            .anchor(0, 2)
            .rects
            .single
            .toJson(),
        a.toJson());
    expect(DocumentReflowPage.decode(edited.toJson())!.text, 'XYZCD');
  });

  test(
      'legacy page files migrate without OCR, and historical anchors remain readable',
      () async {
    final root = Directory(
        '${directory.path}/document-reflow-v1/${sha256.convert(utf8.encode('legacy'))}');
    await root.create(recursive: true);
    final old = DocumentReflowPage(page: 4, ocr: true, rawText: 'old words');
    final current =
        DocumentReflowPage(page: 4, ocr: true, rawText: 'new words');
    final oldFile = File('${root.path}/4-${old.revision}.json');
    await oldFile.writeAsString(jsonEncode(old.toJson()));
    await oldFile.setLastModified(DateTime(2020));
    await File('${root.path}/4-${'a' * 64}.json')
        .writeAsString(jsonEncode(current.toJson()));
    final store = DocumentReflowStore('legacy', directory: directory);
    expect((await store.read(4, 'changed-model'))!.text, 'new words');
    expect((await store.readAnchor(old.anchor(0, 3)))!.text, 'old words');
    expect(await File('${root.path}/book.json').exists(), true);
    expect(await oldFile.exists(),
        true); // Recovery source is not deleted during migration.
  });
}
