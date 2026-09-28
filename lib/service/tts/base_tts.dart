import 'dart:async';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:flutter/material.dart';

enum TtsStateEnum { playing, stopped, paused, continued }

abstract class BaseTts {
  /// Loading is separate from user intent: buffering must keep the background
  /// audio session playing, rather than release its foreground service.
  final bufferingNotifier = ValueNotifier<bool>(false);
  final _bufferingWaits = <Object>{};
  Timer? _bufferingTimer;

  VoidCallback beginBuffering() {
    final token = Object();
    _bufferingWaits.add(token);
    if (_bufferingWaits.length == 1) {
      _bufferingTimer = Timer(const Duration(milliseconds: 300), () {
        if (_bufferingWaits.isNotEmpty) bufferingNotifier.value = true;
      });
    }
    return () {
      if (_bufferingWaits.remove(token) && _bufferingWaits.isEmpty) {
        clearBuffering();
      }
    };
  }

  Future<T> waitForSpeechInput<T>(FutureOr<T> Function() load) async {
    final finish = beginBuffering();
    try {
      return await load();
    } finally {
      finish();
    }
  }

  void clearBuffering() {
    _bufferingWaits.clear();
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
    bufferingNotifier.value = false;
  }

  double get volume;
  set volume(double volume);

  double get pitch;
  set pitch(double pitch);

  double get rate;
  set rate(double rate);

  ValueNotifier<TtsStateEnum> get ttsStateNotifier;
  void updateTtsState(TtsStateEnum newState);

  Future<void> init(
      Function getCurrentText, Function getNextText, Function getPrevText);

  Future<void> speak({String? content});

  Future<dynamic> stop();

  Future<void> pause();

  Future<void> resume();

  Future<void> prev();

  Future<void> next();

  Future<void> restart();

  Future<void> dispose();

  bool get isPlaying;

  String? get currentVoiceText;

  /// A failed sentence stays at the cursor; resume retries instead of skipping.
  String? get playbackError => null;

  Future<List<TtsVoice>> getVoices();
}
