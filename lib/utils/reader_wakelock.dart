import 'dart:async';

import 'package:modu_reader/utils/log/common.dart';
import 'package:modu_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Serializes enable/timeout/exit so a late enable cannot outlive the reader.
class ReaderWakelock {
  static const channel = MethodChannel('modu/reader_wakelock');
  static Future<void> _pending = Future<void>.value();

  static Future<void> setEnabled(bool enabled, {AnxPlatformEnum? platform}) {
    final target = platform ?? AnxPlatform.type;
    return _pending = _pending.then((_) async {
      try {
        if (target == AnxPlatformEnum.ohos) {
          await channel.invokeMethod<void>('toggle', {'enabled': enabled});
        } else {
          await WakelockPlus.toggle(enable: enabled);
        }
      } catch (error) {
        // A missing window/plugin must not interrupt opening or closing a book.
        AnxLog.warning('Reader wakelock failed: ${error.runtimeType}');
      }
    });
  }
}

/// Reading inactivity and auto scroll share one native screen-lock request.
class ReaderAwakeSession {
  Timer? _timer;
  bool _reading = false, _scrolling = false, _foreground = true;
  bool _enabled = false, _disposed = false;

  void reset(int minutes) {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _reading = minutes > 0;
    if (_reading) {
      _timer = Timer(Duration(minutes: minutes), () {
        _timer = null;
        _reading = false;
        _update();
      });
    }
    _update();
  }

  void setAutoScrolling(bool value) {
    if (_disposed || value == _scrolling) return;
    _scrolling = value;
    _update();
  }

  void setForeground(bool value) {
    if (_disposed || value == _foreground) return;
    _foreground = value;
    _update();
  }

  void _update() {
    final enabled = !_disposed && _foreground && (_reading || _scrolling);
    if (_enabled == enabled) return;
    _enabled = enabled;
    unawaited(ReaderWakelock.setEnabled(enabled));
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _update();
  }
}
