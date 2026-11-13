import 'dart:convert';
import 'dart:io';
import 'package:modu_reader/models/book_note.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:modu_reader/service/ocr/document_text_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const first = DocumentImageRect(.1, .2, .3, .05);
  const second = DocumentImageRect(.6, .3, .2, .08);
  test('accepts integral Apple bridge offsets and preserves UTF16 anchors', () {
    for (final offsets in [
      [1, 3],
      [1.0, 3.0],
      [1, 3.0]
    ]) {
      final result = DocumentTextResult.decode({
        'text': '甲🌱乙',
        'regions': [
          {'start': offsets[0], 'end': offsets[1], 'rect': first.toJson()}
        ]
      });
      expect(result.regions.single.start, 1);
      expect(result.regions.single.end, 3);
      expect(result.toJson()['regions'], [
        {'start': 1, 'end': 3, 'rect': first.toJson()}
      ]);
      expect(DocumentTextResult.decode(result.toJson()).text, '甲🌱乙');
    }
  });
  test('rejects malformed bridge offsets without rounding or coercion', () {
    for (final invalid in <Object?>[
      null,
      true,
      '1',
      -1,
      .5,
      double.nan,
      double.infinity,
      double.negativeInfinity,
      1e100,
      5,
    ]) {
      for (final field in ['start', 'end']) {
        expect(
            () => DocumentTextResult.decode({
                  'text': '甲🌱乙',
                  'regions': [
                    {
                      'start': 0,
                      'end': 4,
                      'rect': first.toJson(),
                      field: invalid
                    }
                  ]
                }),
            throwsFormatException,
            reason: '$field=$invalid');
      }
    }
    for (final offsets in [
      [2.0, 2.0],
      [3.0, 1.0]
    ]) {
      expect(
          DocumentTextRegion.decode(
              {'start': offsets[0], 'end': offsets[1], 'rect': first.toJson()},
              4),
          isNull);
    }
  });
  test(
      'reflow maps joined lines, indent, hyphenation and UTF16 without guessing characters',
      () {
    final page = DocumentReflowPage(
        page: 4,
        ocr: true,
        rawText: '  朱熹\n異體🌱。\n\ninter-\nnational',
        layoutVersion: 2,
        rawRegions: const [
          DocumentTextRegion(2, 4, first),
          DocumentTextRegion(5, 10, second),
          DocumentTextRegion(12, 18, first),
          DocumentTextRegion(19, 27, second)
        ]);
    expect(page.text, '朱熹異體🌱。\n\ninternational');
    expect(page.anchor(1, 2).rects.single.toJson(), first.toJson());
    expect(page.anchor(2, 6).rects.single.toJson(), second.toJson());
    final international = page.text.indexOf('international');
    expect(page.regions[2].start, international);
    expect(page.regions[2].end, international + 5);
    expect(page.regions[3].start, international + 5);
  });
  test('OCR image coordinates are translated back through the source crop', () {
    final result =
        DocumentTextResult('朱熹', const [DocumentTextRegion(0, 2, first)])
            .within(const DocumentImageRect(.5, .1, .4, .8));
    final rect = result.regions.single.rect;
    expect(rect.x, closeTo(.54, 1e-9));
    expect(rect.y, closeTo(.26, 1e-9));
    expect(rect.width, closeTo(.12, 1e-9));
    expect(rect.height, closeTo(.04, 1e-9));
  });
  test(
      'page and image coordinates travel with the note through database/sync serialization',
      () {
    final page = DocumentReflowPage(
        page: 7,
        ocr: true,
        rawText: '朱熹異體',
        rawRegions: const [DocumentTextRegion(0, 4, first)]);
    final anchor = page.anchor(0, 2);
    final note = BookNote(
        bookId: 1,
        content: '朱熹',
        cfi: anchor.encode(),
        chapter: '原书第8页',
        type: 'underline',
        color: 'ff0000',
        readerNote: '核对人名',
        updateTime: DateTime(2026));
    final restored = BookNote.fromDb(jsonDecode(jsonEncode(note.toMap())));
    final saved = DocumentReflowAnchor.parse(restored.cfi)!;
    expect(saved.page, 7);
    expect(saved.rects.single.toJson(), first.toJson());
    expect(restored.readerNote, '核对人名');
    expect(saved.matches(page), true);
    final original = DocumentReflowAnchor.parse(saved.originalReference)!;
    expect(original.original, true);
    expect(original.encode(), saved.encode());
  });
  test(
      'changed OCR names, variants or column order never overwrite old notes or revisions',
      () async {
    final dir = await Directory.systemTemp.createTemp('modu-note-geometry-');
    addTearDown(() => dir.delete(recursive: true));
    final store = DocumentReflowStore('same-book', directory: dir);
    final old = DocumentReflowPage(
        page: 1,
        ocr: true,
        rawText: '朱熹\n異體',
        rawRegions: const [
          DocumentTextRegion(0, 2, first),
          DocumentTextRegion(3, 5, second)
        ]);
    final anchor = old.anchor(0, 2), original = old.anchor(0, 2).encode();
    await store.save(old, 'profile');
    for (final text in ['朱喜\n异体', '異體\n朱熹', '朱熹\n異體']) {
      final newer = DocumentReflowPage(
          page: 1,
          ocr: true,
          rawText: text,
          rawRegions: const [
            DocumentTextRegion(0, 2, second),
            DocumentTextRegion(3, 5, first)
          ]);
      await store.save(newer, 'profile');
      expect(anchor.matches(newer), false);
      expect(anchor.encode(), original);
      final cached = (await store.readAnchor(anchor))!;
      expect(cached.text, old.text);
      expect(cached.anchor(0, 2).rects.single.toJson(), first.toJson());
    }
  });
  test(
      'legacy notes stay legacy; invalid geometry is rejected instead of guessed',
      () {
    final old = DocumentReflowPage(page: 0, ocr: true, rawText: '旧笔记');
    final anchor = DocumentReflowAnchor(0, true, old.revision, 0, 2);
    expect(DocumentReflowAnchor.parse(anchor.encode())!.rects, isEmpty);
    expect(DocumentReflowAnchor.parse(anchor.originalReference)!.page, 0);
    for (final rect in [
      <num>[0, 0, -1, 1],
      [0, 0, 2, 1],
      [double.nan, 0, 1, 1]
    ]) {
      expect(DocumentImageRect.decode(rect), isNull);
    }
    final damaged = '${DocumentReflowAnchor.prefix}v2:0:1:${old.revision}:0:2:'
        '${base64Url.encode(utf8.encode('[[0,0,2,1]]'))}';
    expect(DocumentReflowAnchor.parse(damaged), isNull);
    expect(
        () => DocumentTextResult.decode({
              'text': '短',
              'regions': [
                {'start': 0, 'end': 3, 'rect': first.toJson()}
              ]
            }),
        throwsFormatException);
  });
}
