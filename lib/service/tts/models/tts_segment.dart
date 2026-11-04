import 'dart:typed_data';

import 'package:anx_reader/service/tts/models/tts_sentence.dart';

class TtsSegment {
  TtsSegment({required this.sentence, this.roleRate = 1});

  final TtsSentence sentence;
  // Keep the voice and its multiplier together for already queued passages.
  final double roleRate;
  double? synthesizedEffectiveRate;
  double? playbackRate;
  Uint8List? audio;
  // Intentionally non-spoken punctuation, never a synthesis failure.
  bool isSilent = false;
  Object? error;
  int fetchVersion =
      0; // Version to track if audio was fetched with current settings

  bool get isReady =>
      error != null || isSilent || (audio != null && audio!.isNotEmpty);
}
