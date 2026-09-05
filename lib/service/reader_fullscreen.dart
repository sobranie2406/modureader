import 'package:window_manager/window_manager.dart';

/// Serializes native transitions and restores the window state on reader exit.
class ReaderFullscreenSession {
  bool? _previous;
  bool _closed = false;
  Future<void> _pending = Future.value();

  Future<void> set(bool enabled) {
    _pending = _pending.then((_) async {
      if (_closed) return;
      _previous ??= await windowManager.isFullScreen();
      await windowManager.setFullScreen(enabled);
    });
    return _pending;
  }

  Future<void> close() async {
    _closed = true;
    await _pending;
    if (_previous != null) await windowManager.setFullScreen(_previous!);
  }
}
