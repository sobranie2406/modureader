import 'dart:async';
import 'package:flutter/services.dart';

/// Capability-based, one-shot hardware refresh. No repaint/flash fallback.
class EinkRefresh {
  EinkRefresh({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel('com.modu.reader/eink_refresh');
  final MethodChannel _channel;
  Future<bool>? _supported;

  Future<bool> get supported => _supported ??= _call('supported');

  Future<bool> _call(String method) async {
    try {
      return await _channel
              .invokeMethod<bool>(method)
              .timeout(const Duration(seconds: 2)) ==
          true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  Future<bool> refresh({bool Function()? canRefresh}) async {
    if (!await supported || canRefresh?.call() == false) return false;
    return _call('refresh');
  }
}

/// Count original-page transitions, not panels, scroll events or repagination.
/// Wait for rapid navigation to settle before requesting a hardware refresh.
class EinkPageRefreshScheduler {
  EinkPageRefreshScheduler(this.refresh,
      {this.delay = const Duration(milliseconds: 350)});
  final Future<bool> Function() refresh;
  final Duration delay;
  Timer? _timer;
  int? _page;
  int _count = 0;
  int _interval = 0;
  bool _active = false;
  bool _disposed = false;
  bool _busy = false;

  void configure({required bool active, required int interval}) {
    final bounded = interval.clamp(0, 100);
    if (_interval != bounded) reset();
    _interval = bounded;
    _active = active;
    if (!active || bounded == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void observe(int page, {required bool readingAction}) {
    if (_disposed || page < 0) return;
    final previous = _page;
    _page = page;
    if (previous == null ||
        previous == page ||
        !readingAction ||
        !_active ||
        _interval == 0) {
      return;
    }
    _count++;
    if (_count < _interval) return;
    _timer?.cancel();
    _timer = Timer(delay, () async {
      if (_disposed || !_active || _busy) return;
      _count = 0;
      _busy = true;
      try {
        await refresh();
      } catch (_) {
        // An OEM rejection must not disrupt paging or leave an async error.
      } finally {
        _busy = false;
      }
    });
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _count = 0;
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}
