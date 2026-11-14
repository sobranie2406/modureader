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

  double get speed => _speed;
  bool get running => _running;
  bool get active => _running || _starting;
  int get generation => _generation;

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
    if (!started) stopReader();
    notifyListeners();
    return started;
  }

  void stop({bool fromReader = false}) {
    if (_disposed || !active) return;
    _generation++;
    _starting = _running = false;
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
