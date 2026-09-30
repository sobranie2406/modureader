import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Receive Android remote keys before the platform WebView consumes them.
/// The owner rechecks its current route/focus state on every delivered event.
class ReaderPageKeys {
  ReaderPageKeys({required this.onDirection, bool? android})
      : _android = android ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (_android) channel.setMethodCallHandler(_handle);
  }

  static const channel = MethodChannel('com.modu.reader/page_keys');
  final void Function(int) onDirection;
  final bool _android;
  bool _active = false;
  bool _volume = false;
  bool _disposed = false;

  Future<void> _handle(MethodCall call) async {
    if (_disposed || !_active || call.method != 'turnPage') return;
    final direction = call.arguments;
    if (direction is int && (direction == -1 || direction == 1)) {
      onDirection(direction);
    }
  }

  void update({required bool active, required bool volume}) {
    if (_disposed || !_android) return;
    if (_active == active && _volume == volume) return;
    _active = active;
    _volume = volume;
    unawaited(_send(active, volume));
  }

  Future<void> _send(bool active, bool volume) async {
    try {
      await channel.invokeMethod<void>('configure', {
        'active': active,
        'volume': volume,
      });
    } on MissingPluginException {
      // Older development hosts may not yet have the native bridge.
    } on PlatformException catch (error) {
      debugPrint('Reader page keys unavailable: ${error.code}');
    }
  }

  void dispose() {
    _disposed = true;
    if (!_android) return;
    channel.setMethodCallHandler(null);
    unawaited(_send(false, false));
  }
}
