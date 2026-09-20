import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/material.dart';

class TtsFactory {
  static final TtsFactory _instance = TtsFactory._internal();

  factory TtsFactory() {
    return _instance;
  }

  TtsFactory._internal() : _createOverride = null;

  @visibleForTesting
  TtsFactory.forTesting(BaseTts Function() create) : _createOverride = create;

  final BaseTts Function()? _createOverride;
  Future<void> _lifecycle = Future<void>.value();

  // Serialize only short lifecycle operations, never the lifetime of speech.
  Future<void> _serialize(Future<void> Function() action) {
    final operation = _lifecycle.then((_) => action());
    _lifecycle =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  BaseTts? _currentTts;

  BaseTts get current {
    _currentTts ??= createTts();
    return _currentTts!;
  }

  BaseTts createTts() {
    if (_createOverride != null) return _createOverride!();
    TtsService service = getTtsService(Prefs().ttsService);
    return service == TtsService.system ? SystemTts() : OnlineTts();
  }

  Future<void> switchTtsType(String serviceId) => _serialize(() async {
        if (Prefs().ttsService == serviceId) return;

        await _releaseCurrent();

        Prefs().ttsService = serviceId;
        _currentTts = createTts();
      });

  Future<void> dispose() => _serialize(_releaseCurrent);

  Future<void> _releaseCurrent() async {
    final previous = _currentTts;
    if (previous == null) return;
    try {
      // Both concrete implementations stop as part of dispose. Do not send
      // duplicate native stop/dispose calls when services are switched quickly.
      await previous.dispose();
    } catch (error) {
      AnxLog.warning('TTS service cleanup failed: ${error.runtimeType}');
    } finally {
      _currentTts = null;
    }
  }

  ValueNotifier<TtsStateEnum> get ttsStateNotifier {
    return current.ttsStateNotifier;
  }
}
