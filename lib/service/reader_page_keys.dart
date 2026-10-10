import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Receive Android remote keys before the platform WebView consumes them.
/// The owner rechecks its current route/focus state on every delivered event.
class ReaderPageKeys {
  ReaderPageKeys(
      {required this.onDirection,
      this.onShortcut,
      this.onHostStateChanged,
      bool? android})
      : _android = android ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (_android) channel.setMethodCallHandler(_handle);
  }

  static const channel = MethodChannel('com.modu.reader/page_keys');
  final void Function(int) onDirection;
  final void Function(int)? onShortcut;
  final VoidCallback? onHostStateChanged;
  final bool _android;
  bool _active = false;
  bool _volume = false;
  bool _disposed = false;
  List<Map<String, int>>? _shortcuts;

  Future<void> _handle(MethodCall call) async {
    if (_disposed) return;
    // Configuration changes also happen while a reader dialog blocks keys.
    // Let the owner re-evaluate the route instead of activating keys blindly.
    if (call.method == 'hostStateChanged') {
      onHostStateChanged?.call();
      return;
    }
    if (!_active) return;
    if (call.method == 'shortcut') {
      final action = call.arguments;
      if (action is int && action >= 3 && action <= 7) onShortcut?.call(action);
      return;
    }
    if (call.method != 'turnPage') return;
    final direction = call.arguments;
    if (direction is int && (direction == -1 || direction == 1)) {
      onDirection(direction);
    }
  }

  void update(
      {required bool active,
      required bool volume,
      bool force = false,
      List<Map<String, int>>? shortcuts}) {
    if (_disposed || !_android) return;
    if (!force &&
        _active == active &&
        _volume == volume &&
        jsonEncode(_shortcuts) == jsonEncode(shortcuts)) {
      return;
    }
    _active = active;
    _volume = volume;
    _shortcuts = shortcuts;
    unawaited(_send(active, volume));
  }

  Future<void> _send(bool active, bool volume) async {
    try {
      await channel.invokeMethod<void>('configure', {
        'active': active,
        'volume': volume,
        if (_shortcuts != null) 'shortcuts': _shortcuts,
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
