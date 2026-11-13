import 'dart:async';
import 'package:modu_reader/service/reading/text_filter.dart';
import 'dart:ui' show TextRange;

import 'models/tts_sentence.dart';
import 'tts_pipeline.dart';

/// A page-local speech cursor. Prefetch can inspect it but cannot advance it.
class TtsPageSource {
  TtsPageSource(String text,
      {required this.chapter,
      this.onPosition,
      this.excludedRanges,
      this.onHighlight,
      this.onNextPage,
      this.onCancelAdvance}) {
    _setText(text);
  }

  final List<TextRange> Function(String)? excludedRanges;

  void _setText(String text) {
    text = maskFilteredText(text, excludedRanges?.call(text) ?? const []);
    _sentences.clear();
    _offsets.clear();
    _index = 0;
    var offset = 0;
    for (final sentence in TtsPipeline(text).sentences) {
      // Bound unpunctuated OCR text for system engines and online providers.
      final runes = sentence.runes.toList();
      for (var start = 0; start < runes.length; start += 500) {
        final part = String.fromCharCodes(runes.skip(start).take(500));
        final position = text.indexOf(part, offset);
        _offsets.add(position);
        offset = position + part.length;
        _sentences.add(TtsSentence(
            text: part,
            endsParagraph: RegExp(r'^(?:[ \t]*\n|\s*$)')
                .hasMatch(text.substring(offset))));
      }
    }
  }

  String chapter;
  final Future<bool> Function(TtsPageSource source, bool Function() isCurrent)?
      onNextPage;
  final void Function()? onCancelAdvance;
  Future<String>? _continuation;
  Completer<bool>? _advanceCancellation;
  int _generation = 0;
  final void Function(int offset)? onPosition;
  final void Function(TextRange? range)? onHighlight;
  final _sentences = <TtsSentence>[];
  final _offsets = <int>[];
  int _index = 0;
  bool _valid = true;
  bool get valid => _valid && (_sentences.isNotEmpty || onNextPage != null);
  bool get atEnd => _index >= _sentences.length;

  void invalidate() {
    cancelAdvance();
    _valid = false;
    clearHighlight();
  }

  void clearHighlight() => onHighlight?.call(null);
  void rewind() => _index = 0;

  /// Start at the sentence containing a selected word, within this page only.
  void seekToOffset(int offset) {
    if (!valid) return;
    _index = 0;
    while (_index + 1 < _sentences.length &&
        _offsets[_index] + _sentences[_index].text.length <= offset) {
      _index++;
    }
  }

  String currentText() {
    if (!valid) return '';
    if (_index >= _sentences.length) rewind();
    return _current();
  }

  Future<String> currentTextContinuous() async {
    final text = currentText();
    return text.isEmpty && valid && onNextPage != null
        ? await nextTextContinuous()
        : text;
  }

  String nextText() {
    if (!valid) return '';
    if (_index < _sentences.length) _index++;
    return _current();
  }

  /// Only the playback consumer may load another original page. Prefetch and
  /// selection-only speech keep using this page's non-mutating/synchronous API.
  Future<String> nextTextContinuous() {
    return _continuation ??= _nextContinuous().whenComplete(() {
      _continuation = null;
    });
  }

  Future<String> _nextContinuous() async {
    final generation = _generation, previous = _index;
    final next = nextText();
    if (next.isNotEmpty || !valid || onNextPage == null) return next;
    bool current() => valid && generation == _generation;
    final cancelled = Completer<bool>();
    _advanceCancellation = cancelled;
    try {
      final loaded = await Future.any<bool>([
        onNextPage!(this, current),
        cancelled.future,
      ]);
      if (current() && loaded && _sentences.isEmpty) {
        return await _nextContinuous();
      }
      return current() && loaded ? _current() : '';
    } catch (_) {
      // Retry the last sentence, not the entire page, after OCR/load failure.
      if (current()) _index = previous;
      rethrow;
    } finally {
      if (identical(_advanceCancellation, cancelled)) {
        _advanceCancellation = null;
      }
    }
  }

  void replacePage(String text, {required String chapter}) {
    clearHighlight();
    this.chapter = chapter;
    _setText(text);
  }

  void cancelAdvance() {
    _generation++;
    final cancelled = _advanceCancellation;
    if (cancelled != null && !cancelled.isCompleted) {
      cancelled.complete(false);
      onCancelAdvance?.call();
    }
  }

  String previousText() {
    if (!valid) return '';
    if (_index > 0) _index--;
    return _current();
  }

  String _current() {
    if (_index >= _sentences.length) {
      clearHighlight();
      return '';
    }
    showCurrent();
    return _sentences[_index].text;
  }

  void showCurrent() {
    if (valid && _index < _offsets.length) {
      final start = _offsets[_index];
      onHighlight?.call(
          TextRange(start: start, end: start + _sentences[_index].text.length));
      onPosition?.call(start);
    }
  }

  List<TtsSentence> collect(int count) => valid
      ? _sentences.skip(_index).take(count).toList(growable: false)
      : const [];
}
