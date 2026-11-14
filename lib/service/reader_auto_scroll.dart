import 'dart:async';

import 'package:flutter/foundation.dart';

/// A stopped or replaced reader must never accept a late WebView start result.
class ReaderAutoScroll extends ChangeNotifier {
  ReaderAutoScroll(
      {required this.startReader,
      required this.stopReader,
      this.onSpeedChanged,
      double speed = 1}) {
    _speed = speed.isFinite ? (speed.clamp(.1, 4) * 10).round() / 10 : 1;
  }

  final Future<bool> Function(double speed) startReader;
  final VoidCallback stopReader;
  final ValueChanged<double>? onSpeedChanged;
  double _speed = 1;
  bool _running = false, _starting = false, _disposed = false;
  int _generation = 0;
  Duration? _timeLimit, _remaining;
  Timer? _countdown;

  double get speed => _speed;
  bool get running => _running;
  bool get active => _running || _starting;
  int get generation => _generation;
  Duration? get timeLimit => _timeLimit;
  Duration? get remaining => _remaining;

  void setTimeLimit(Duration? value) {
    if (_disposed) return;
    _timeLimit = value == null || value <= Duration.zero
        ? null
        : Duration(seconds: value.inSeconds.clamp(1, 120 * 60));
    _remaining = _timeLimit;
    _startCountdown();
    notifyListeners();
  }

  void _startCountdown() {
    _countdown?.cancel();
    _countdown = null;
    if (!_running || _remaining == null) return;
    final initial = _remaining!;
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      // tick includes missed callbacks, so a busy reader cannot extend the limit.
      final next = initial - Duration(seconds: timer.tick);
      if (next <= Duration.zero) {
        _remaining = Duration.zero;
        stop();
      } else {
        _remaining = next;
        notifyListeners();
      }
    });
  }

  void setSpeed(double value) {
    if (_disposed || !value.isFinite) return;
    _speed = (value.clamp(.1, 4) * 10).round() / 10;
    onSpeedChanged?.call(_speed);
    notifyListeners();
  }

  Future<bool> start() async {
    if (_disposed || active) return false;
    final generation = ++_generation;
    _starting = true;
    notifyListeners();
    bool started;
    try {
      started = await startReader(_speed);
    } catch (_) {
      started = false;
    }
    if (_disposed || generation != _generation) {
      if (started && !active) stopReader();
      return false;
    }
    _starting = false;
    _running = started;
    if (started) {
      if (_remaining == Duration.zero) _remaining = _timeLimit;
      _startCountdown();
    }
    if (!started) stopReader();
    notifyListeners();
    return started;
  }

  void stop({bool fromReader = false}) {
    if (_disposed || !active) return;
    _generation++;
    _starting = _running = false;
    _countdown?.cancel();
    _countdown = null;
    if (!fromReader) stopReader();
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    super.dispose();
  }
}
