import 'package:flutter/foundation.dart';
import 'dart:ui' show TextRange;
import 'package:modu_reader/enums/translation_mode.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'reader_translation_session.dart';

typedef _PageIdentity = ({
  int page,
  bool ocr,
  String revision,
  String settings
});

/// Ephemeral translation of one saved source page, never an OCR cache revision.
class DocumentPageTranslation extends ChangeNotifier {
  final mode = ValueNotifier(TranslationModeEnum.off);
  final _session = ReaderTranslationSession();
  final _prefetchSession = ReaderTranslationSession();
  final _prefetched = <_PageIdentity, List<String?>>{};
  List<String> _original = [];
  List<String?> _translated = [];
  Future<String> Function(ReaderTranslationSession, int, String)? _request;
  _PageIdentity? _current;
  bool busy = false;

  _PageIdentity _identity(DocumentReflowPage page, String settings) => (
        page: page.page,
        ocr: page.ocr,
        revision: page.revision,
        settings: settings,
      );

  List<String> _paragraphs(DocumentReflowPage page) => page.text
      .split(RegExp(r'\n\s*\n'))
      .where((text) => text.trim().isNotEmpty)
      .toList();

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
    cancelPrefetch();
    final identity = _identity(page, settings);
    if (!force && _current == identity && _translated.isNotEmpty) {
      mode.value = display;
      notifyListeners();
      await translateVisible(visibleStart, visibleEnd);
      return;
    }
    _session.start();
    if (force || (_current != null && _current?.settings != settings)) {
      _prefetched.clear();
    }
    _current = identity;
    // DocumentReflowPage.text already prefers the saved edited text.
    _original = _paragraphs(page);
    _translated =
        _prefetched.remove(identity) ?? List.filled(_original.length, null);
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
    cancelPrefetch();
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

  Future<void> prefetch(
      Iterable<int> pages,
      Future<DocumentReflowPage?> Function(int, bool Function())
          loadPage) async {
    final request = _request, current = _current;
    if (request == null || current == null || busy || !_session.enabled) return;
    final generation = _prefetchSession.start();
    bool active() =>
        _prefetchSession.enabled && _prefetchSession.generation == generation;
    try {
      for (final index in pages) {
        if (!active()) return;
        final page = await loadPage(index, active);
        if (!active()) return;
        if (page == null || page.page != index) continue;
        final key = _identity(page, current.settings);
        final cached = _prefetched[key];
        if (cached != null && cached.every((part) => part != null)) continue;
        final original = _paragraphs(page);
        final results = cached ?? List<String?>.filled(original.length, null);
        for (var i = 0; i < original.length; i++) {
          if (results[i] != null) continue;
          final result =
              await request(_prefetchSession, generation, original[i]);
          if (!active()) return;
          results[i] = result;
          _prefetched.remove(key);
          _prefetched[key] = results;
          if (_prefetched.length > 5) {
            _prefetched.remove(_prefetched.keys.first);
          }
        }
      }
    } catch (_) {
      // A speculative request can fail without affecting the displayed page.
    } finally {
      if (active()) cancelPrefetch();
    }
  }

  void cancelPrefetch() => _prefetchSession.stop();

  void stop({bool retainPrefetched = false}) {
    _session.stop();
    cancelPrefetch();
    if (!retainPrefetched) _prefetched.clear();
    busy = false;
    _original = [];
    _translated = [];
    _request = null;
    _current = null;
    mode.value = TranslationModeEnum.off;
    notifyListeners();
  }

  @override
  void dispose() {
    _session.stop();
    cancelPrefetch();
    mode.dispose();
    super.dispose();
  }
}
