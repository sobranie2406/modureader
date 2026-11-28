import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/service/ocr/document_text_geometry.dart';
import 'package:modu_reader/service/ocr/manga_page.dart';

void main() {
  const bubble = DocumentImageRect(.1, .1, .5, .5);
  final result = DocumentTextResult('右\n左\n音', const [
    DocumentTextRegion(0, 1, DocumentImageRect(.35, .2, .1, .2),
        bubble: bubble),
    DocumentTextRegion(2, 3, DocumentImageRect(.20, .2, .1, .2),
        bubble: bubble),
    DocumentTextRegion(4, 5, DocumentImageRect(.65, .6, .1, .2)),
  ]);
  test(
      'recognition and translations cache separately; blank pages send nothing',
      () async {
    var ocr = 0, translations = 0;
    final reader = MangaPageReader(recognize: (page, _) async {
      ocr++;
      return page == 0
          ? DocumentTextResult.decode(result.toJson())
          : DocumentTextResult('');
    }, translate: (text, _, __) async {
      translations++;
      return '译$text';
    });
    final original = await reader.load(0);
    expect(original.map((b) => b['original']), ['右左', '音']);
    expect(original.map((b) => b['tapToReveal']), [false, true]);
    expect(original.first['masks'], hasLength(2));
    expect(translations, 0);
    final translated = await reader.load(0, translationSettings: 'zh');
    expect(translated.first['translation'], '译右左');
    await reader.load(0, translationSettings: 'zh');
    expect([ocr, translations], [1, 2]);
    await reader.load(0, translationSettings: 'en');
    expect(await reader.load(1, translationSettings: 'en'), isEmpty);
    expect([ocr, translations], [2, 4]);
  });
  test('dark balloons retain their text grouping but open on tap', () {
    final page = DocumentTextResult('暗', const [
      DocumentTextRegion(0, 1, DocumentImageRect(.2, .2, .1, .2),
          bubble: bubble, tapToReveal: true)
    ]);
    final cached = DocumentTextResult.decode(page.toJson())
        .within(const DocumentImageRect(.1, .1, .5, .5));
    expect(mangaPageBubbles(cached).single['tapToReveal'], isTrue);
    expect(cached.regions.single.bubble!.width, .25);
  });

  test('leaving the page while recognizing never starts translation', () async {
    final pending = Completer<DocumentTextResult>();
    final reader = MangaPageReader(
        recognize: (_, __) => pending.future,
        translate: (_, __, ___) => throw TestFailure('stale page translation'));
    final load = expectLater(
        reader.load(1, translationSettings: 'zh'), throwsStateError);
    final stopping = reader.cancel();
    pending.complete(result);
    await stopping;
    await load;
    expect(await reader.load(2), hasLength(2));
  });
}
