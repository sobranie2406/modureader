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
    expect(state.controls.map((control) => control.action), [
      MediaAction.skipToPrevious,
      MediaAction.pause,
      MediaAction.skipToNext,
      MediaAction.stop
    ]);
    expect(state.controls.last.androidIcon, 'drawable/ic_stat_tts_exit');
    expect(state.androidCompactActionIndices, [0, 1, 2]);
    expect(
        state.systemActions,
        containsAll(
            [MediaAction.playPause, MediaAction.play, MediaAction.pause]));
  });
  test('paused notification remains resumable and stop removes controls', () {
    final paused = ttsMediaState(PlaybackState(), TtsStateEnum.paused);
    expect(paused.playing, isFalse);
    expect(paused.processingState, AudioProcessingState.ready);
    expect(paused.controls[1].action, MediaAction.play);
    expect(paused.systemActions, contains(MediaAction.playPause));
    expect(paused.controls.map((control) => control.action), [
      MediaAction.skipToPrevious,
      MediaAction.play,
      MediaAction.skipToNext,
      MediaAction.stop,
    ]);
    final stopped = ttsMediaState(paused, TtsStateEnum.stopped);
    expect(stopped.playing, isFalse);
    expect(stopped.processingState, AudioProcessingState.idle);
    expect(stopped.controls, isEmpty);
    expect(stopped.androidCompactActionIndices, isEmpty);
    expect(stopped.systemActions, isEmpty);
  });

  test('Chinese transport labels expose passage navigation and stop reading',
      () {
    final state =
        ttsMediaState(PlaybackState(), TtsStateEnum.playing, chinese: true);
    expect(state.controls.map((control) => control.label),
        ['上一段', '暂停', '下一段', '停止朗读']);
    expect(
        ttsMediaState(state, TtsStateEnum.paused, chinese: true)
            .controls[1]
            .label,
        '播放');
  });

  test('notification displays book and chapter, not author as the second line',
      () {
    for (final paused in [false, true]) {
      final item = ttsMediaItem(
          bookId: '17',
          title: '唐砖',
          author: '作者',
          chapter: '第三十二节 长孙的五指山',
          coverPath: '/tmp/cover image.jpg',
          state: paused ? TtsStateEnum.paused : TtsStateEnum.playing,
          chinese: true);
      expect(item.id, '17');
      expect(item.title, '唐砖');
      expect(item.displayTitle, '${paused ? '已暂停' : '正在朗读'}: 唐砖');
      expect(item.displaySubtitle, '第三十二节 长孙的五指山');
      expect(item.artist, item.displaySubtitle);
      expect(item.extras?['bookAuthor'], '作者');
      expect(item.extras?['ttsChapter'], item.displaySubtitle);
      expect(item.artUri, Uri.file('/tmp/cover image.jpg'));
      expect(item.duration, isNull);
    }
  });

  test('missing chapter or cover has a safe fallback', () {
    final item = ttsMediaItem(
        bookId: '17',
        title: 'Book',
        author: 'Author',
        chapter: '',
        coverPath: '',
        state: TtsStateEnum.playing);
    expect(item.displayTitle, 'Reading: Book');
    expect(item.displaySubtitle, 'Author');
    expect(item.artUri, isNull);
  });
}
