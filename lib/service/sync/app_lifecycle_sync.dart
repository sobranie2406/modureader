import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;

/// Groups the platform's lifecycle notifications into background/return pairs.
class AppLifecycleSync {
  AppLifecycleSync({
    required this.synchronize,
    required this.pauseAutomatic,
    this.onError,
  });

  final Future<void> Function(bool background) synchronize;
  final void Function() pauseAutomatic;
  final void Function(Object error, StackTrace stack)? onError;
  AppLifecycleState? _lastState;
  bool _background = false;

  void update(AppLifecycleState state) {
    if (state == _lastState) return;
    _lastState = state;
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_background) return;
        _background = true;
        pauseAutomatic();
        unawaited(_synchronize(true));
      case AppLifecycleState.resumed:
        if (!_background) return;
        _background = false;
        unawaited(_synchronize(false));
      case AppLifecycleState.inactive:
        if (!_background) pauseAutomatic();
      case AppLifecycleState.detached:
        _background = false;
        pauseAutomatic();
    }
  }

  Future<void> _synchronize(bool background) async {
    try {
      await synchronize(background);
    } catch (error, stack) {
      onError?.call(error, stack);
    }
  }
}
