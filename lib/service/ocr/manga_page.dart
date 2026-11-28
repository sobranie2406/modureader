import 'dart:math' as math;
import 'document_text_geometry.dart';
import 'local_ocr_service.dart';
import '../translate/reader_translation_session.dart';

/// Keep detector reading order within each bubble. Free lettering is independent.
List<Map<String, dynamic>> mangaPageBubbles(DocumentTextResult result) {
  final groups =
      <(double, double, double, double, int), List<DocumentTextRegion>>{};
  for (final region in result.regions) {
    final b = region.bubble ?? region.rect;
    final key = (
      b.x,
      b.y,
      b.width,
      b.height,
      region.bubble == null ? region.start : -1
    );
    (groups[key] ??= []).add(region);
  }
  return groups.values.map((regions) {
    final boxes = regions.map((r) => r.rect);
    final left = boxes.map((r) => r.x).reduce(math.min);
    final top = boxes.map((r) => r.y).reduce(math.min);
    final right = boxes.map((r) => r.x + r.width).reduce(math.max);
    final bottom = boxes.map((r) => r.y + r.height).reduce(math.max);
    final bubble = regions.first.bubble;
    final textOnly = bubble == null ||
        (bubble.x == left &&
            bubble.y == top &&
            (bubble.width - (right - left)).abs() < 1e-8 &&
            (bubble.height - (bottom - top)).abs() < 1e-8);
    return <String, dynamic>{
      'masks': [for (final box in boxes) box.toJson()],
      'rect': textOnly
          ? [left, top, right - left, bottom - top]
          : [
              bubble.x + bubble.width * .16,
              bubble.y + bubble.height * .18,
              bubble.width * .68,
              bubble.height * .64
            ],
      'tapToReveal': bubble == null || regions.any((r) => r.tapToReveal),
      'original':
          regions.map((r) => result.text.substring(r.start, r.end)).join(),
    };
  }).toList();
}

class MangaPageReader {
  MangaPageReader({required this.recognize, required this.translate});

  final Future<DocumentTextResult> Function(int, OcrCancellation) recognize;
  final Future<String> Function(String, ReaderTranslationSession, int)
      translate;
  final _pages = <int, List<Map<String, dynamic>>>{};
  final _translations = <(String, String), String>{};
  final _session = ReaderTranslationSession();
  OcrCancellation? _cancel;
  Future<List<Map<String, dynamic>>>? _pending;

  Future<void> cancel() async {
    _cancel?.cancel();
    _session.stop();
    try {
      await _pending;
    } catch (_) {
      // The caller handles actual recognition and translation errors.
    }
  }

  Future<List<Map<String, dynamic>>> load(int page,
      {String? translationSettings}) {
    if (_cancel != null) throw StateError('Manga page already loading');
    final token = _cancel = OcrCancellation();
    return _pending = _load(page, token, translationSettings).whenComplete(() {
      _cancel = null;
      _pending = null;
    });
  }

  Future<List<Map<String, dynamic>>> _load(
      int page, OcrCancellation token, String? settings) async {
    var bubbles = _pages.remove(page);
    if (bubbles == null) {
      final result = await recognize(page, token);
      token.check();
      bubbles = mangaPageBubbles(result);
    }
    _pages[page] = bubbles;
    if (_pages.length > 8) _pages.remove(_pages.keys.first);
    if (settings == null || bubbles.isEmpty) return bubbles;
    final generation = _session.start();
    final translated = <Map<String, dynamic>>[];
    for (final bubble in bubbles) {
      final source = bubble['original'] as String;
      final key = (settings, source);
      final text =
          _translations[key] ?? await translate(source, _session, generation);
      token.check();
      _translations[key] = text;
      if (_translations.length > 256) {
        _translations.remove(_translations.keys.first);
      }
      translated.add({...bubble, 'translation': text});
    }
    return translated;
  }
}
