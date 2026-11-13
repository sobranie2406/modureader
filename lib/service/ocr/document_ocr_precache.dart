import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'document_reflow_loader.dart';
import 'local_ocr_service.dart';

/// Original PDFs and scanned EPUBs do not always report a cropped panel.
int documentOcrPage(Map<String, dynamic> location) {
  final region = location['pdfRegion'];
  final page = region is Map ? region['page'] : null;
  if (page is num && page.isFinite && page >= 0 && page == page.toInt()) {
    return page.toInt();
  }
  final chapter = location['currentChapter'];
  return chapter is num &&
          chapter.isFinite &&
          chapter >= 1 &&
          chapter == chapter.toInt()
      ? chapter.toInt() - 1
      : -1;
}

/// Small rolling window; a navigation replaces the queue, never adds to it.
class DocumentOcrPrecache extends ChangeNotifier {
  DocumentOcrPrecache(
      {required this.load,
      required this.canRun,
      this.cachedPages,
      this.delay = const Duration(milliseconds: 300)});
  final Future<void> Function(int, OcrCancellation) load;
  final Future<Set<int>> Function(int start, int count)? cachedPages;
  final bool Function() canRun;
  final Duration delay;
  Timer? _timer;
  Future<void>? _pending;
  OcrCancellation? _cancel;
  int _page = -1, _count = 0, _generation = 0, _scannedGeneration = -1;
  final Set<int> _cached = {};
  int? currentPage;
  (int, int)? progress;
  bool _disposed = false, _paused = false;
  int _attempts = 0;
  int _foregroundJobs = 0;
  Object? error;
  int get completed => _cached.length;
  int get total => _count;
  int get startPage => _page;
  bool get running => currentPage != null && _cancel?.cancelled == false;
  bool get paused => _paused;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void update(int page, int count, {int? totalPages}) {
    count = count.clamp(0, 5);
    if (totalPages != null) {
      count = count.clamp(0, (totalPages - page).clamp(0, 5));
    }
    if (_disposed || (_page == page && _count == count)) return;
    _page = page;
    _count = count;
    _cached.removeWhere((saved) => saved < page || saved >= page + count);
    _attempts = 0;
    error = null;
    _generation++;
    // A page already being recognized may finish and persist even if we turn
    // away. Only disabling prefetch invalidates it here.
    if (count == 0) _cancel?.cancel();
    _timer?.cancel();
    _schedule();
    _changed();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed ||
        _pending != null ||
        _foregroundJobs > 0 ||
        _paused ||
        _attempts >= 3 ||
        _count == 0 ||
        _page < 0 ||
        (_scannedGeneration == _generation && completed == _count)) {
      return;
    }
    _timer = Timer(delay * (1 << _attempts), _tick);
  }

  Future<void> _tick() async {
    if (_disposed || _paused || _foregroundJobs > 0) return;
    if (_pending != null || !canRun()) {
      _schedule();
      return;
    }
    final generation = _generation;
    final cancel = OcrCancellation();
    _cancel = cancel;
    final pending = _load(generation, cancel);
    _pending = pending;
    _changed();
    await pending;
    _pending = null;
    if (!cancel.cancelled && generation == _generation) {
      if (error == null) {
        _attempts = 0;
      } else {
        _attempts++;
      }
    }
    _schedule();
    _changed();
  }

  Future<void> _load(int generation, OcrCancellation cancel) async {
    try {
      if (_scannedGeneration != generation) {
        final saved = await cachedPages?.call(_page, _count) ?? <int>{};
        cancel.check();
        if (generation != _generation) return;
        _cached.addAll(
            saved.where((page) => page >= _page && page < _page + _count));
        _scannedGeneration = generation;
        _changed();
      }
      if (_paused ||
          _foregroundJobs > 0 ||
          !canRun() ||
          generation != _generation) {
        return;
      }
      final missing = [
        for (var p = _page; p < _page + _count; p++)
          if (!_cached.contains(p)) p
      ];
      if (missing.isEmpty) {
        error = null;
        return;
      }
      final page = missing.first;
      currentPage = page;
      progress = null;
      error = null;
      _changed();
      await load(page, cancel);
      if (!cancel.cancelled) {
        if (page >= _page && page < _page + _count) _cached.add(page);
        if (generation == _generation) error = null;
      }
    } catch (failure, stack) {
      if (!cancel.cancelled && generation == _generation) {
        error = failure;
        final reason = switch (failure) {
          ReflowModelUnavailable() => 'ocr_model_unavailable',
          FormatException(
            message: 'Invalid image page' || 'Invalid precache page'
          ) =>
            'ocr_invalid_page',
          FormatException(message: 'Invalid reflow bounds') =>
            'ocr_invalid_bounds',
          FormatException(message: 'Invalid page image') => 'ocr_invalid_image',
          FormatException(message: 'No usable text') => 'ocr_no_text',
          StateError(message: 'PDF preview failed') => 'ocr_preview_failed',
          _ => 'unknown',
        };
        // Never log raw errors: file/bridge failures may contain private paths.
        AnxLog.warning(
            'OCR precache failed: ${failure.runtimeType}; reason=$reason',
            null,
            stack);
      }
    } finally {
      currentPage = null;
      progress = null;
    }
  }

  void reportProgress(int done, int total) {
    if (!running || _disposed || total <= 0) return;
    progress = (done.clamp(0, total), total);
    _changed();
  }

  /// Let the in-flight source page persist before sharing the OCR/render worker.
  Future<T> runForeground<T>(Future<T> Function() action) async {
    _foregroundJobs++;
    _timer?.cancel();
    try {
      await _pending;
      if (_disposed) throw StateError('Reader closed');
      return await action();
    } finally {
      _foregroundJobs--;
      _scannedGeneration = -1;
      _schedule();
      _changed();
    }
  }

  Future<void> pause({bool cancelRunning = true}) async {
    _paused = true;
    _timer?.cancel();
    if (cancelRunning) {
      _cancel?.cancel();
      _scannedGeneration = -1;
    }
    _changed();
    if (cancelRunning) await _pending;
  }

  void resume() {
    if (!_disposed) {
      _paused = false;
      _attempts = 0;
      _schedule();
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _cancel?.cancel();
    super.dispose();
  }
}
