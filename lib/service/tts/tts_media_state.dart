import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:audio_service/audio_service.dart';

/// One policy for the expanded notification, lock screen and compact controls.
PlaybackState ttsMediaState(PlaybackState previous, TtsStateEnum state) {
  final stopped = state == TtsStateEnum.stopped;
  final playing = state == TtsStateEnum.playing;
  return previous.copyWith(
    playing: playing,
    processingState:
        stopped ? AudioProcessingState.idle : AudioProcessingState.ready,
    controls: stopped
        ? []
        : [
            MediaControl.skipToPrevious,
            playing ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ],
    androidCompactActionIndices: stopped ? [] : [0, 1, 2],
  );
}
