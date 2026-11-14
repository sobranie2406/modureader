import 'dart:async';

import 'package:flutter/foundation.dart';

class ReaderToolbarVisibility extends ChangeNotifier {
  static const hideDelay = Duration(seconds: 5);

  Timer? _timer;
  bool _visible = false;
  bool _enabled = false;
  bool _held = false;
  bool _disposed = false;

  bool get visible => _visible;
  bool get enabled => _enabled;

  void setEnabled(bool value) {
    if (_disposed || value == _enabled) return;
    _enabled = _visible = value;
    _held = false;
    _scheduleHide();
    notifyListeners();
  }

  void reveal() {
    if (_disposed || !_enabled) return;
    final changed = !_visible;
    _visible = true;
    _scheduleHide();
    if (changed) notifyListeners();
  }

  void hold(bool value) {
    if (_disposed || value == _held) return;
    _held = value;
    _scheduleHide();
  }

  void _scheduleHide() {
    _timer?.cancel();
    _timer = null;
    if (!_enabled || !_visible || _held) return;
    _timer = Timer(hideDelay, () {
      _timer = null;
      _visible = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _enabled = _visible = _held = false;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
