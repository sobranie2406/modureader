import 'package:flutter/foundation.dart';
import 'dart:ui' show TextRange;
import 'package:modu_reader/enums/translation_mode.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'reader_translation_session.dart';

/// Ephemeral translation of one saved source page, never an OCR cache revision.
class DocumentPageTranslation extends ChangeNotifier {
  final mode = ValueNotifier(TranslationModeEnum.off);
  final _session = ReaderTranslationSession();
  List<String> _original = [];
  List<String?> _translated = [];
  Future<String> Function(ReaderTranslationSession, int, String)? _request;
  String? _revision, _settings;
  int? _page;
  bool busy = false;

  String get text => List.generate(
      _original.length,
      (i) => _translated[i] == null
          ? _original[i]
          : mode.value == TranslationModeEnum.bilingual
              ? '${_original[i]}\n\n${_translated[i]}'
              : _translated[i]!).join('\n\n');

  List<TextRange> get translatedRanges {
    final ranges = <TextRange>[];
    var offset = 0;
    for (var i = 0; i < _original.length; i++) {
      final translated = _translated[i];
      if (translated == null) {
        offset += _original[i].length + 2;
        continue;
      }
      if (mode.value == TranslationModeEnum.bilingual) {
        offset += _original[i].length + 2;
      }
      ranges.add(TextRange(start: offset, end: offset + translated.length));
      offset += translated.length + 2;
    }
    return ranges;
  }

  Future<void> translate(DocumentReflowPage page, TranslationModeEnum display,
      {required String settings,
      required Future<String> Function(ReaderTranslationSession, int, String)
          request,
      bool force = false,
      int visibleStart = 0,
      int? visibleEnd}) async {
    if (display == TranslationModeEnum.off ||
        display == TranslationModeEnum.originalOnly) {
      stop();
      return;
    }
    if (!force &&
        _revision == page.revision &&
        _page == page.page &&
        _settings == settings &&
        _translated.isNotEmpty) {
      mode.value = display;
      notifyListeners();
      await translateVisible(visibleStart, visibleEnd);
      return;
    }
    _session.start();
    _revision = page.revision;
    _page = page.page;
    _settings = settings;
    // DocumentReflowPage.text already prefers the saved edited text.
    _original = page.text
        .split(RegExp(r'\n\s*\n'))
        .where((text) => text.trim().isNotEmpty)
        .toList();
    _translated = List.filled(_original.length, null);
    _request = request;
    busy = false;
    mode.value = display;
    notifyListeners();
    await translateVisible(visibleStart, visibleEnd);
  }

  Future<void> translateVisible(int start, int? end) async {
    if (!_session.enabled || busy || _request == null) return;
    final generation = _session.generation;
    final indices = <int>[];
    var offset = 0;
    for (var i = 0; i < _original.length; i++) {
      final displayed = _translated[i] == null
          ? _original[i]
          : mode.value == TranslationModeEnum.bilingual
              ? '${_original[i]}\n\n${_translated[i]}'
              : _translated[i]!;
      if (offset + displayed.length >= start &&
          (end == null || offset <= end) &&
          _translated[i] == null) {
        indices.add(i);
      }
      offset += displayed.length + 2;
    }
    if (indices.isEmpty) return;
    busy = true;
    notifyListeners();
    try {
      for (final i in indices) {
        final result = await _request!(_session, generation, _original[i]);
        if (!_session.enabled || generation != _session.generation) return;
        _translated[i] = result;
        notifyListeners();
      }
    } on TranslationCancelled {
      // Page changes, closing the reader and Stop cancel both transport and UI.
    } catch (_) {
      if (_session.enabled && generation == _session.generation) {
        stop();
        rethrow;
      }
    } finally {
      if (_session.enabled && generation == _session.generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  void stop() {
    _session.stop();
    busy = false;
    _original = [];
    _translated = [];
    _request = null;
    _revision = null;
    _page = null;
    _settings = null;
    mode.value = TranslationModeEnum.off;
    notifyListeners();
  }

  @override
  void dispose() {
    _session.stop();
    mode.dispose();
    super.dispose();
  }
}
