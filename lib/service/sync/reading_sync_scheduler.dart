import 'dart:async';

const readingSyncIntervals = [1, 2, 3, 5, 10, 15, 30, 60];

/// One-shot scheduling prevents overlaps and catch-up bursts after sleep.
/// The next interval begins when the previous attempt has finished.
class ReadingSyncScheduler {
  ReadingSyncScheduler({required this.sync, required this.onError});
  final Future<void> Function(bool Function() stillAllowed) sync;
  final void Function(Object, StackTrace) onError;
  Timer? _timer;
  bool _active = false, _running = false, _disposed = false;
  int _generation = 0;
  Duration _interval = const Duration(minutes: 5);

  void update(
      {required bool enabled,
      required bool foreground,
      required bool readingVisible,
      required int minutes}) {
    if (_disposed) return;
    final active = enabled && foreground && readingVisible;
    final interval =
        Duration(minutes: readingSyncIntervals.contains(minutes) ? minutes : 5);
    if (_active == active && _interval == interval) return;
    _active = active;
    _interval = interval;
    _generation++;
    _timer?.cancel();
    _timer = null;
    _schedule();
  }

  void _schedule() {
    if (_disposed || !_active || _running || _timer != null) return;
    _timer = Timer(_interval, () async {
      _timer = null;
      if (_disposed || !_active) return;
      _running = true;
      final generation = _generation;
      try {
        await sync(() => !_disposed && _active && generation == _generation);
      } catch (error, stack) {
        onError(error, stack);
      } finally {
        _running = false;
        _schedule();
      }
    });
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    _timer = null;
  }
}
