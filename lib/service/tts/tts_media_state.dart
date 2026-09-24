import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:audio_service/audio_service.dart';

/// One policy for the expanded notification, lock screen and compact controls.
PlaybackState ttsMediaState(PlaybackState previous, TtsStateEnum state,
    {bool chinese = false}) {
  final stopped = state == TtsStateEnum.stopped;
  final playing = state == TtsStateEnum.playing;
  return previous.copyWith(
    playing: playing,
    processingState:
        stopped ? AudioProcessingState.idle : AudioProcessingState.ready,
    // Bluetooth remotes may send a toggle, explicit play, or explicit pause.
    // Advertise all supported commands, not only the currently visible icon.
    systemActions: stopped
        ? const {}
        : const {MediaAction.play, MediaAction.pause, MediaAction.playPause},
    controls: stopped
        ? []
        : [
            MediaControl.skipToPrevious
                .copyWith(label: chinese ? '上一段' : 'Previous passage'),
            playing
                ? MediaControl.pause.copyWith(label: chinese ? '暂停' : 'Pause')
                : MediaControl.play.copyWith(label: chinese ? '播放' : 'Play'),
            MediaControl.skipToNext
                .copyWith(label: chinese ? '下一段' : 'Next passage'),
            MediaControl.stop.copyWith(
              androidIcon: 'drawable/ic_stat_tts_exit',
              label: chinese ? '停止朗读' : 'Stop reading',
            ),
          ],
    androidCompactActionIndices: stopped ? [] : [0, 1, 2],
  );
}

/// Supply both generic metadata (lock screen/media session) and Android's
/// display overrides. The chapter, not the author, is the second line.
MediaItem ttsMediaItem({
  required String bookId,
  required String title,
  required String author,
  required String chapter,
  required String coverPath,
  required TtsStateEnum state,
  bool chinese = false,
}) {
  final paused = state == TtsStateEnum.paused;
  final status =
      chinese ? (paused ? '已暂停' : '正在朗读') : (paused ? 'Paused' : 'Reading');
  return MediaItem(
    id: bookId,
    title: title,
    artist: chapter.isEmpty ? author : chapter,
    album: title,
    displayTitle: '$status: $title',
    displaySubtitle: chapter.isEmpty ? author : chapter,
    // Unknown duration: speech has no stable seekable audio timeline.
    duration: null,
    artUri: coverPath.isEmpty ? null : Uri.file(coverPath),
    extras: {
      'bookAuthor': author,
      'ttsChapter': chapter,
      'ttsCoverPath': coverPath
    },
  );
}
