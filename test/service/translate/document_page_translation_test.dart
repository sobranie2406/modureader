import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/enums/translation_mode.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:modu_reader/service/translate/document_page_translation.dart';
import 'package:modu_reader/service/translate/reader_translation_session.dart';

void main() {
  late DocumentPageTranslation translation;
  late List<String> requests;
  Future<String> request(
          ReaderTranslationSession session, int generation, String text) =>
      session.translate(generation, (_) {
        requests.add(text);
        return Stream.value('translated: $text');
      });
  DocumentReflowPage page({String? edit, int index = 0}) => DocumentReflowPage(
      page: index, ocr: true, rawText: 'OCR source.', editedText: edit);
  setUp(() {
    translation = DocumentPageTranslation();
    requests = [];
  });
  tearDown(() => translation.dispose());

  test(
      'visible ranges translate only intersecting paragraphs; scrolling loads others',
      () async {
    final source = page(edit: 'first\n\nsecond\n\nthird');
    await translation.translate(source, TranslationModeEnum.translationOnly,
        settings: 'classical',
        request: request,
        visibleStart: 0,
        visibleEnd: 4);
    expect(requests, ['first']);
    expect(translation.text, 'translated: first\n\nsecond\n\nthird');
    expect(translation.translatedRanges.length, 1);
    expect(translation.translatedRanges.single.textInside(translation.text),
        'translated: first');
    final second = translation.text.indexOf('second');
    await translation.translateVisible(second, second + 3);
    expect(requests, ['first', 'second']);
    await translation.translateVisible(second, second + 3);
    expect(requests, ['first', 'second']);
    translation.stop();
    await translation.translateVisible(0, 9999);
    expect(requests, ['first', 'second']);
  });

  test('saved edits first, bilingual paragraph order, source is immutable',
      () async {
    final source = page(edit: 'Corrected first.\n\nCorrected second.');
    final revision = source.revision;
    await translation.translate(source, TranslationModeEnum.bilingual,
        settings: 'en', request: request);
    expect(requests, ['Corrected first.', 'Corrected second.']);
    expect(translation.text,
        'Corrected first.\n\ntranslated: Corrected first.\n\nCorrected second.\n\ntranslated: Corrected second.');
    expect(source.rawText, 'OCR source.');
    expect(source.editedText, 'Corrected first.\n\nCorrected second.');
    expect(source.revision, revision);
    expect(translation.busy, isFalse);
    expect(
        translation.translatedRanges.map((r) => r.textInside(translation.text)),
        ['translated: Corrected first.', 'translated: Corrected second.']);
  });

  test('without edits use recognized text; mode switch reuses current result',
      () async {
    final source = page();
    await translation.translate(source, TranslationModeEnum.bilingual,
        settings: 'en', request: request);
    await translation.translate(source, TranslationModeEnum.translationOnly,
        settings: 'en', request: request);
    expect(requests, [source.text]);
    expect(translation.text, 'translated: ${source.text}');
    translation.stop();
    expect(translation.mode.value, TranslationModeEnum.off);
    expect(translation.text, isEmpty);
    expect(translation.translatedRanges, isEmpty);
  });

  test('page, edits, language changes and explicit retry invalidate results',
      () async {
    Future<void> run(DocumentReflowPage source,
            {String settings = 'en', bool force = false}) =>
        translation.translate(source, TranslationModeEnum.bilingual,
            settings: settings, request: request, force: force);
    await run(page());
    await run(page(index: 1));
    await run(page(index: 1, edit: 'Correction.'));
    await run(page(index: 1, edit: 'Correction.'), settings: 'fr');
    await run(page(index: 1, edit: 'Correction.'), settings: 'fr', force: true);
    expect(requests.length, 5);
  });

  test('stop cancels current transport and never submits the next paragraph',
      () async {
    final stream = StreamController<String>();
    var cancelled = false;
    stream.onCancel = () => cancelled = true;
    final task = translation.translate(
        page(edit: 'first\n\nsecond'), TranslationModeEnum.bilingual,
        settings: 'en', request: (session, generation, text) {
      requests.add(text);
      return session.translate(generation, (_) => stream.stream);
    });
    expect(translation.busy, isTrue);
    translation.stop();
    await task;
    stream.add('late');
    await stream.close();
    expect(cancelled, isTrue);
    expect(requests, ['first']);
    expect(translation.text, isEmpty);
    expect(translation.busy, isFalse);
  });

  test('late old-page response cannot replace the new page', () async {
    final old = Completer<String>();
    final task = translation.translate(page(), TranslationModeEnum.bilingual,
        settings: 'en', request: (_, __, ___) => old.future);
    await translation.translate(
        page(index: 1, edit: 'new page'), TranslationModeEnum.translationOnly,
        settings: 'en', request: request);
    old.complete('old page');
    await task;
    expect(translation.text, 'translated: new page');
  });

  test('opening a prefetched page reuses it and cancels the next request',
      () async {
    final started = Completer<void>();
    var cancelled = false;
    final stream = StreamController<String>(onCancel: () => cancelled = true);
    final first = page(edit: 'Current'), next = page(index: 1, edit: 'Next');
    final following = page(index: 2, edit: 'Following');
    Future<String> requestPage(
        ReaderTranslationSession session, int generation, String text) {
      if (text != 'Following') return request(session, generation, text);
      return session.translate(generation, (_) {
        requests.add(text);
        started.complete();
        return stream.stream;
      });
    }

    await translation.translate(first, TranslationModeEnum.bilingual,
        settings: 'en', request: requestPage);
    final prefetch = translation
        .prefetch([1, 2], (index, _) async => index == 1 ? next : following);
    await started.future;
    expect(translation.text, 'Current\n\ntranslated: Current');
    translation.stop(retainPrefetched: true);
    await translation.translate(next, TranslationModeEnum.translationOnly,
        settings: 'en', request: requestPage);
    await prefetch;
    await stream.close();
    expect(cancelled, isTrue);
    expect(translation.text, 'translated: Next');
    expect(requests, ['Current', 'Next', 'Following']);
  });

  test('prefetch is reused only for the matching source revision and settings',
      () async {
    final old = page(index: 1, edit: 'Old');
    final newer = page(index: 1, edit: 'Correction');
    Future<void> run(DocumentReflowPage source, String settings) =>
        translation.translate(source, TranslationModeEnum.translationOnly,
            settings: settings, request: request);
    await run(page(edit: 'Current'), 'en');
    await translation.prefetch([1], (_, __) async => old);
    await run(newer, 'en');
    await translation.prefetch([2], (_, __) async => page(index: 2));
    await run(page(index: 2), 'ja');
    expect(requests,
        ['Current', 'Old', 'Correction', 'OCR source.', 'OCR source.']);
  });

  test('failure restores original mode and can retry', () async {
    await expectLater(
        translation.translate(page(), TranslationModeEnum.bilingual,
            settings: 'en',
            request: (_, __, ___) async => throw StateError('offline')),
        throwsStateError);
    expect(translation.mode.value, TranslationModeEnum.off);
    expect(translation.busy, isFalse);
    await translation.translate(page(), TranslationModeEnum.translationOnly,
        settings: 'en', request: request);
    expect(translation.text, isNotEmpty);
  });
}
