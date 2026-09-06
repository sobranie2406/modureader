import 'dart:async';
import 'package:anx_reader/utils/platform_utils.dart';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/system_tts_support.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SystemTts extends BaseTts {
  static final SystemTts _instance = SystemTts._internal();

  factory SystemTts() {
    return _instance;
  }

  SystemTts._internal();

  @visibleForTesting
  SystemTts.forTesting({required bool supported})
      : _supportedOverride = supported;

  bool? _supportedOverride;
  bool get isSupported => _supportedOverride ?? supportsSystemTts();

  void _requireSupport() {
    if (!isSupported) {
      throw UnsupportedError(systemTtsUnsupportedMessage(chinese: true));
    }
  }

  final FlutterTts flutterTts = FlutterTts();

  String? _currentVoiceText;
  int _generation = 0;
  Future<void>? _running;
  Future<dynamic>? _pendingAdvance;
  Future<dynamic>? _resumeAfterAdvance;
  String? _playbackError;

  @override
  String? get playbackError => _playbackError;

  bool restarting = false;

  late Function getHereFunction;
  late Function getNextTextFunction;
  late Function getPrevTextFunction;

  @override
  final ValueNotifier<TtsStateEnum> ttsStateNotifier =
      ValueNotifier<TtsStateEnum>(TtsStateEnum.stopped);

  @override
  void updateTtsState(TtsStateEnum newState) {
    ttsStateNotifier.value = newState;
  }

  bool get isIOS => AnxPlatform.isIOS;
  bool get isAndroid => AnxPlatform.isAndroid;
  bool get isWindows => AnxPlatform.isWindows;
  bool get isWeb => kIsWeb;

  @override
  double get volume => Prefs().ttsVolume;

  @override
  set volume(double volume) {
    Prefs().ttsVolume = volume;
    restart();
  }

  @override
  double get pitch => Prefs().ttsPitch;

  @override
  set pitch(double pitch) {
    Prefs().ttsPitch = pitch;
    restart();
  }

  @override
  double get rate => Prefs().ttsRate;

  @override
  set rate(double rate) {
    Prefs().ttsRate = rate;
    restart();
  }

  @override
  bool get isPlaying => ttsStateNotifier.value == TtsStateEnum.playing;

  @override
  String? get currentVoiceText => _currentVoiceText;

  @override
  Future<void> init(Function getCurrentText, Function getNextText,
      Function getPrevText) async {
    getHereFunction = getCurrentText;
    getNextTextFunction = getNextText;
    getPrevTextFunction = getPrevText;

    // Opening a book must not fail just because no supported voice service
    // has been chosen. Report the actionable error only when playing.
    if (!isSupported) return;

    await setAwaitOptions();

    if (isAndroid) {
      await getDefaultEngine();
      await getDefaultVoice();
    }

    // Await one utterance, then advance once. Native start/completion callbacks
    // must not enqueue or move the reader independently.
  }

  Future<void> setAwaitOptions() async {
    _requireSupport();
    await flutterTts.awaitSpeakCompletion(true);
    if (isAndroid) {
      await flutterTts.awaitSynthCompletion(true);
      await flutterTts.setQueueMode(0);
    }
  }

  Future<void> getDefaultEngine() async {
    var engine = await flutterTts.getDefaultEngine;
    if (engine != null) {}
  }

  Future<void> getDefaultVoice() async {
    var voice = await flutterTts.getDefaultVoice;
    if (voice != null) {}
  }

  /// Apply the voice by shortName
  Future<void> _applyVoice(String? voiceShortName) async {
    if (voiceShortName == null || voiceShortName.isEmpty) {
      return;
    }

    try {
      // Get all voices to find the matching one
      final voices = await flutterTts.getVoices;
      if (voices is List) {
        for (var voice in voices) {
          final map = Map<String, dynamic>.from(voice);
          if (map['name'] == voiceShortName) {
            // flutter_tts setVoice expects a Map with 'name' and 'locale'
            await flutterTts.setVoice({
              'name': map['name'],
              'locale': map['locale'],
            });
            return;
          }
        }
      }
    } catch (e) {
      // Fallback: try to set voice directly (some platforms support this)
      // Ignore errors if voice not found
    }
  }

  /// For testing a specific voice in settings (matching OnlineTts API)
  Future<void> speakWithVoice(String content, String voiceShortName) async {
    _requireSupport();
    await stop();
    await flutterTts.setVolume(volume);
    await flutterTts.setSpeechRate(rate);
    await flutterTts.setPitch(pitch);
    await _applyVoice(voiceShortName);
    await flutterTts.speak(content);
  }

  @override
  Future<void> speak({String? content}) async {
    _requireSupport();
    if (_running != null) return _running!;
    final generation = ++_generation;
    _playbackError = null;
    final continuous = isPlaying;
    final run = _speakLoop(generation, content, continuous);
    _running = run;
    return run.whenComplete(() {
      if (identical(_running, run)) _running = null;
    });
  }

  Future<void> _speakLoop(
      int generation, String? content, bool continuous) async {
    bool active() => generation == _generation && (!continuous || isPlaying);
    try {
      await setAwaitOptions();
      if (!active()) return;
      final initial = content ?? _currentVoiceText ?? await getHereFunction();
      if (!active()) return;
      _currentVoiceText = initial as String?;
      while (active() && (_currentVoiceText?.trim().isNotEmpty ?? false)) {
        await flutterTts.setVolume(volume);
        await flutterTts.setSpeechRate(rate);
        await flutterTts.setPitch(pitch);
        await _applyVoice(Prefs().getTtsVoiceModel('system'));
        if (!active()) return;
        final result = await flutterTts.speak(_currentVoiceText!);
        if (!active()) return;
        if (result == 0) throw StateError('System speech failed');
        if (!continuous) return;
        final advancing = Future<dynamic>.sync(() => getNextTextFunction());
        _pendingAdvance = advancing;
        final next = await advancing;
        if (identical(_pendingAdvance, advancing)) _pendingAdvance = null;
        if (!active()) return;
        _currentVoiceText = next as String?;
      }
      if (active() && continuous) updateTtsState(TtsStateEnum.stopped);
    } catch (error) {
      if (active()) {
        _pendingAdvance = null;
        _playbackError =
            '朗读失败，已保留当前位置，请重试 / Speech failed; retry from this sentence.';
        updateTtsState(TtsStateEnum.paused);
      }
      if (!continuous) rethrow;
    }
  }

  @override
  Future<dynamic> stop() async {
    ++_generation;
    _running = null;
    _pendingAdvance = null;
    _resumeAfterAdvance = null;
    _currentVoiceText = null;
    _playbackError = null;
    updateTtsState(TtsStateEnum.stopped);
    return isSupported ? await flutterTts.stop() : 1;
  }

  @override
  Future<void> pause() async {
    _resumeAfterAdvance = _pendingAdvance;
    ++_generation;
    _running = null;
    updateTtsState(TtsStateEnum.paused);
    if (isSupported) await flutterTts.stop();
  }

  @override
  Future<void> resume() async {
    final generation = _generation;
    final advancing = _resumeAfterAdvance;
    if (advancing != null) {
      try {
        final next = await advancing;
        if (generation != _generation) return;
        _currentVoiceText = next as String?;
        _resumeAfterAdvance = null;
      } catch (_) {
        if (generation != _generation) return;
        _resumeAfterAdvance = null;
        updateTtsState(TtsStateEnum.paused);
        return;
      }
    }
    updateTtsState(TtsStateEnum.playing);
    await speak(content: _currentVoiceText);
  }

  Future<void> _navigate(Function move, {bool forward = false}) async {
    if (restarting) return;
    restarting = true;
    try {
      final advancing = _pendingAdvance;
      await stop();
      final generation = _generation;
      if (advancing != null && !forward) await advancing;
      final text =
          forward && advancing != null ? await advancing : await move();
      if (generation != _generation) return;
      if (text is! String || text.trim().isEmpty) return;
      updateTtsState(TtsStateEnum.playing);
      unawaited(speak(content: text));
    } finally {
      restarting = false;
    }
  }

  @override
  Future<void> prev() => _navigate(getPrevTextFunction);

  @override
  Future<void> next() => _navigate(getNextTextFunction, forward: true);

  @override
  Future<void> restart() async {
    if (restarting || !isPlaying) return;
    restarting = true;
    final text = _currentVoiceText;
    final advancing = _pendingAdvance;
    try {
      await stop();
      final generation = _generation;
      final resumedText = advancing != null ? await advancing as String? : text;
      if (generation != _generation) return;
      updateTtsState(TtsStateEnum.playing);
      unawaited(speak(content: resumedText));
    } finally {
      restarting = false;
    }
  }

  @override
  Future<List<TtsVoice>> getVoices() async {
    if (!isSupported) return [];
    try {
      dynamic voices = await flutterTts.getVoices;
      if (voices is List) {
        return voices.map((e) {
          final map = Map<String, dynamic>.from(e);
          return TtsVoice(
              shortName: map['name'] ?? '',
              name: map['name'] ?? '',
              locale: map['locale']?.replaceAll('_', '-') ?? '',
              gender: map['gender']?.toString().toLowerCase() ?? '',
              rawData: map);
        }).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}
