import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/tts_media_state.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('playing exposes transport controls including pause in compact view',
      () {
    final state = ttsMediaState(PlaybackState(), TtsStateEnum.playing);
    expect(state.playing, isTrue);
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.controls, [
      MediaControl.skipToPrevious,
      MediaControl.pause,
      MediaControl.skipToNext,
      MediaControl.stop
    ]);
    expect(state.androidCompactActionIndices, [0, 1, 2]);
  });
  test('paused notification remains resumable and stop removes controls', () {
    final paused = ttsMediaState(PlaybackState(), TtsStateEnum.paused);
    expect(paused.playing, isFalse);
    expect(paused.processingState, AudioProcessingState.ready);
    expect(paused.controls[1], MediaControl.play);
    final stopped = ttsMediaState(paused, TtsStateEnum.stopped);
    expect(stopped.playing, isFalse);
    expect(stopped.processingState, AudioProcessingState.idle);
    expect(stopped.controls, isEmpty);
    expect(stopped.androidCompactActionIndices, isEmpty);
  });
}
