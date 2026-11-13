import 'package:modu_reader/service/ocr/document_text_geometry.dart';
import 'package:modu_reader/service/ocr/document_text_reflow.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:flutter_test/flutter_test.dart';

DocumentTextResult source(List<String> lines, List<DocumentImageRect> boxes) {
  var start = 0;
  final regions = <DocumentTextRegion>[];
  for (var i = 0; i < lines.length; i++) {
    regions.add(DocumentTextRegion(start, start + lines[i].length, boxes[i]));
    start += lines[i].length + 1;
  }
  return DocumentTextResult(lines.join('\n'), regions);
}

void main() {
  test('source geometry joins soft wraps and preserves paragraph indent', () {
    final input = source([
      '甲乙丙丁戊己庚辛壬。',
      '下一行继续同段正文。',
      '新段首行缩进文字',
      '段末。'
    ], const [
      DocumentImageRect(.1, .1, .5, .02),
      DocumentImageRect(.1, .13, .5, .02),
      DocumentImageRect(.2, .16, .4, .02),
      DocumentImageRect(.1, .19, .15, .02),
    ]);
    final page = DocumentReflowPage(
        page: 0, ocr: true, rawText: input.text, rawRegions: input.regions);
    expect(page.text, '甲乙丙丁戊己庚辛壬。下一行继续同段正文。\n\n　　新段首行缩进文字段末。');
    final start = page.text.indexOf('新段');
    expect(page.anchor(start, start + 2).rects.single.toJson(),
        input.regions[2].rect.toJson());
    expect(page.regions[2].start, start);
  });

  test('headers, footers and column transitions are not discarded', () {
    final input = source([
      '页眉',
      '正文第一栏',
      '正文第二栏',
      '短行甲',
      '短行乙',
      '12'
    ], const [
      DocumentImageRect(.4, .02, .1, .02),
      DocumentImageRect(.1, .1, .3, .02),
      DocumentImageRect(.6, .1, .3, .02),
      DocumentImageRect(.1, .2, .15, .02),
      DocumentImageRect(.1, .23, .15, .02),
      DocumentImageRect(.48, .95, .04, .01),
    ]);
    final text = reflowDocumentText(input.text, regions: input.regions);
    expect(text.replaceAll(RegExp(r'\s'), ''), input.text.replaceAll('\n', ''));
    expect(text, contains('正文第一栏\n\n正文第二栏'));
    expect(text, endsWith('12'));
  });

  test('wide line spacing and noisy OCR boxes do not split every sentence', () {
    final words = List.filled(6, '这是同一个段落的连续文字，不应按句号随意分段。');
    final input = source(words, [
      for (var i = 0; i < words.length; i++)
        DocumentImageRect(.1 + (i.isEven ? .003 : 0), .1 + i * .04,
            .8 - (i.isEven ? .003 : 0), i.isEven ? .01 : .016),
    ]);
    final page = DocumentReflowPage(
        page: 0, ocr: true, rawText: input.text, rawRegions: input.regions);
    expect(page.text, words.join());
    expect(page.regions.length, words.length);
    for (var i = 0; i < words.length; i++) {
      expect(page.text.substring(page.regions[i].start, page.regions[i].end),
          words[i]);
      expect(page.regions[i].rect.toJson(), input.regions[i].rect.toJson());
    }
    final old = DocumentReflowPage(
        page: 0,
        ocr: true,
        layoutVersion: 3,
        rawText: input.text,
        rawRegions: input.regions);
    expect(old.text, words.join('\n\n'));
    expect(DocumentReflowPage.decode(old.toJson())!.text, old.text);
    expect(DocumentReflowPage.decode(old.toJson())!.revision, old.revision);
    expect(old.anchor(0, 2).matches(page), false);
  });

  for (final evidence in ['gap', 'indent', 'short tail']) {
    test('clear $evidence starts a new paragraph, ordinary wraps merge', () {
      final words = List.filled(5, '这是正文中的一行文字需要按照原书的段落来排版');
      final input = source(words, [
        const DocumentImageRect(.1, .1, .8, .02),
        DocumentImageRect(.1, .14, evidence == 'short tail' ? .5 : .8, .02),
        DocumentImageRect(
            evidence == 'indent' ? .18 : .1,
            evidence == 'gap' ? .22 : .18,
            evidence == 'indent' ? .72 : .8,
            .02),
        DocumentImageRect(.1, evidence == 'gap' ? .26 : .22, .8, .02),
        DocumentImageRect(.1, evidence == 'gap' ? .30 : .26, .8, .02),
      ]);
      expect(reflowDocumentText(input.text, regions: input.regions),
          '${words.take(2).join()}\n\n${evidence == 'indent' ? '　　' : ''}${words.skip(2).join()}');
    });
  }

  test('ragged English line ends do not automatically become paragraphs', () {
    final input = source([
      'An ordinary English sentence.',
      'continues here on another printed line',
      'and continues once more.'
    ], const [
      DocumentImageRect(.1, .1, .72, .02),
      DocumentImageRect(.1, .14, .8, .02),
      DocumentImageRect(.1, .18, .65, .02),
    ]);
    expect(reflowDocumentText(input.text, regions: input.regions),
        input.text.replaceAll('\n', ' '));
  });

  test('adjacent OCR fragments on one printed row do not create paragraphs',
      () {
    final input = source([
      '这是同一行',
      '后半行文字内容',
      '下一行正文继续'
    ], const [
      DocumentImageRect(.1, .1, .3, .02),
      DocumentImageRect(.415, .101, .485, .02),
      DocumentImageRect(.1, .14, .8, .02),
    ]);
    expect(reflowDocumentText(input.text, regions: input.regions),
        '这是同一行后半行文字内容下一行正文继续');
  });

  test('v2 annotations keep exact text and hash after new layout is available',
      () {
    final input = source([
      '甲乙丙丁戊己庚辛壬。',
      '接着同一段正文内容'
    ], const [
      DocumentImageRect(.1, .1, .5, .02),
      DocumentImageRect(.1, .13, .5, .02),
    ]);
    final legacy = DocumentReflowPage(
        page: 2,
        ocr: true,
        layoutVersion: 2,
        rawText: input.text,
        rawRegions: input.regions);
    final current = DocumentReflowPage(
        page: 2, ocr: true, rawText: input.text, rawRegions: input.regions);
    final restored = DocumentReflowPage.decode(legacy.toJson())!;
    expect(restored.text, legacy.text);
    expect(restored.revision, legacy.revision);
    expect(legacy.anchor(0, 2).matches(restored), true);
    expect(legacy.anchor(0, 2).matches(current), false);
    expect(DocumentReflowPage.decode(current.toJson())!.text, current.text);
  });
}
