import 'dart:typed_data';

import 'package:anx_reader/service/tts/models/tts_sentence.dart';

class TtsSegment {
  TtsSegment({required this.sentence});

  final TtsSentence sentence;
  Uint8List? audio;
  bool isSilent = false;
  Object? error;
  int fetchVersion =
      0; // Version to track if audio was fetched with current settings

  bool get isReady =>
      error != null || isSilent || (audio != null && audio!.isNotEmpty);
}
