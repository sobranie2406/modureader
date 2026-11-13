import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'media_diagnostic_fields.dart';

/// Opt-in test builds only. Observes; never sends transport commands.
class MediaDiagnostics {
  static const enabled = bool.fromEnvironment('MODU_MEDIA_DIAGNOSTICS');
  static const _channel = MethodChannel('com.modu.reader/media_diagnostics');
  static StreamSubscription<PlaybackState>? _subscription;
  static final _clock = Stopwatch();
  static String? _lastState;
  static int _count = 0;

  static Map<String, Object> describeState(PlaybackState state) => {
        'source': 'dart',
        'event': 'state',
        'playing': state.playing,
        'processing': state.processingState.name,
        'controls': state.controls.map((c) => c.action.index).toList(),
        'systemActions': state.systemActions.map((a) => a.index).toList()
          ..sort(),
        'compact': state.androidCompactActionIndices ?? <int>[],
      };

  static void _record(Object? input) {
    if (_count >= 2000) return;
    final fields = safeMediaDiagnosticFields(input);
    if (fields.isEmpty) return;
    fields['elapsedMs'] = _clock.elapsedMilliseconds;
    _count++;
    // Logging must never interrupt TTS if storage is unavailable.
    try {
      AnxLog.info('TTS media diagnostic: ${jsonEncode(fields)}');
    } catch (_) {}
  }

  static Future<void> start(AudioHandler handler) async {
    if (!enabled || !Platform.isAndroid || _subscription != null) return;
    _clock.start();
    _record({'source': 'dart', 'event': 'start'});
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'event') _record(call.arguments);
    });
    _subscription = handler.playbackState.listen((state) {
      final fields = describeState(state);
      final serialized = jsonEncode(fields);
      if (serialized == _lastState) return;
      _lastState = serialized;
      _record(fields);
    }, onError: (Object _) {
      _record({'source': 'dart', 'event': 'error'});
    });
    try {
      await _channel.invokeMethod<void>('start');
    } catch (_) {
      _record({'source': 'android', 'event': 'error'});
    }
  }
}
