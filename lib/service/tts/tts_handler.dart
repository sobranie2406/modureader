import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/tts_factory.dart';
import 'package:anx_reader/service/tts/tts_media_state.dart';
import 'package:anx_reader/service/tts/notification_permission.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/material.dart';

class TtsHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final TtsFactory _ttsFactory;
  final Future<bool> Function()? _activateSessionOverride;
  final Future<void> Function()? _deactivateSessionOverride;
  final Future<void> Function()? _stopReaderOverride;

  static final TtsHandler _instance = TtsHandler._internal();

  factory TtsHandler() {
    return _instance;
  }

  TtsHandler._internal()
      : _ttsFactory = TtsFactory(),
        _activateSessionOverride = null,
        _deactivateSessionOverride = null,
        _stopReaderOverride = null {
    _initAudioSession();
  }

  @visibleForTesting
  TtsHandler.forTesting({
    required TtsFactory factory,
    required Future<bool> Function() activateSession,
    Future<void> Function()? deactivateSession,
    Future<void> Function()? stopReader,
  })  : _ttsFactory = factory,
        _activateSessionOverride = activateSession,
        _deactivateSessionOverride = deactivateSession,
        _stopReaderOverride = stopReader;

  BaseTts get tts => _ttsFactory.current;

  Function? _getCurrentText;
  Function? _getNextText;
  Function? _getPrevText;
  BaseTts? _observedTts;
  int _transportCommand = 0;
  bool _resumeAfterInterruption = false;
  Future<void>? _pendingPause;

  bool get _chinese =>
      (Prefs().locale ?? WidgetsBinding.instance.platformDispatcher.locale)
          .languageCode ==
      'zh';

  void _publishMetadata(MediaItem item) {
    final previous = mediaItem.value;
    if (previous?.id == item.id &&
        previous?.displayTitle == item.displayTitle &&
        previous?.displaySubtitle == item.displaySubtitle &&
        previous?.artUri == item.artUri) return;
    queue.add([item]);
    mediaItem.add(item);
  }

  void _refreshMetadata({String? chapter}) {
    final current = mediaItem.value;
    if (current == null) return;
    _publishMetadata(ttsMediaItem(
      bookId: current.id,
      title: current.title,
      author: current.extras?['bookAuthor'] as String? ?? '',
      chapter: chapter ?? current.extras?['ttsChapter'] as String? ?? '',
      coverPath: current.extras?['ttsCoverPath'] as String? ?? '',
      state: tts.ttsStateNotifier.value,
      chinese: _chinese,
    ));
  }

  /// Called from the speech cursor, including detached/background chapters.
  /// Ignore a late callback from a stopped or different book.
  void updateChapter({required int bookId, required String chapter}) {
    if (mediaItem.value?.id != bookId.toString() ||
        tts.ttsStateNotifier.value == TtsStateEnum.stopped) return;
    _refreshMetadata(chapter: chapter);
  }

  void _observePlayback() {
    _observedTts?.ttsStateNotifier.removeListener(_syncPlaybackState);
    _observedTts = tts;
    tts.ttsStateNotifier.addListener(_syncPlaybackState);
  }

  void _syncPlaybackState() {
    playbackState.add(ttsMediaState(
        playbackState.value, tts.ttsStateNotifier.value,
        chinese: _chinese));
    if (tts.ttsStateNotifier.value != TtsStateEnum.stopped) _refreshMetadata();
  }

  Future<void> init(Function getCurrentText, Function getNextText,
      Function getPrevText) async {
    _getCurrentText = getCurrentText;
    _getNextText = getNextText;
    _getPrevText = getPrevText;
    await tts.init(getCurrentText, getNextText, getPrevText);
    _observePlayback();
  }

  Future<void> switchTtsType(String serviceId) async {
    await _ttsFactory.switchTtsType(serviceId);
    if (_getCurrentText != null &&
        _getNextText != null &&
        _getPrevText != null) {
      await tts.init(_getCurrentText!, _getNextText!, _getPrevText!);
      _observePlayback();
    }
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;

    final allowMix = Prefs().allowMixWithOtherAudio;

    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: allowMix
          ? AVAudioSessionCategoryOptions.mixWithOthers
          : AVAudioSessionCategoryOptions.none,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media,
      ),
    ));
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        final wasPlaying = tts.isPlaying;
        if (wasPlaying) unawaited(pause());
        _resumeAfterInterruption =
            wasPlaying && event.type != AudioInterruptionType.unknown;
      } else {
        final resume = _resumeAfterInterruption;
        _resumeAfterInterruption = false;
        if (resume && tts.ttsStateNotifier.value == TtsStateEnum.paused) {
          unawaited(play());
        }
      }
    });
    session.becomingNoisyEventStream.listen((_) {
      if (tts.isPlaying) pause();
    });
  }

  @override
  Future<void> play() async {
    _resumeAfterInterruption = false;
    final backend = tts;
    if (backend.isPlaying) return;
    final command = ++_transportCommand;
    final reader = epubPlayerKey.currentState;
    final previous = mediaItem.value;
    final resuming = backend.ttsStateNotifier.value == TtsStateEnum.paused &&
        previous != null &&
        (reader == null || previous.id == reader.book.id.toString());
    AnxLog.info('TTS transport play: resume=$resuming, '
        'lifecycle=${WidgetsBinding.instance.lifecycleState?.name}');
    // A notification resumes the retained audio session, not a new reading
    // operation. Never require foreground UI or permission dialogs for it.
    if (!resuming) {
      if (reader == null) return;
      await prepareTtsNotificationPermission();
      if (!reader.mounted || epubPlayerKey.currentState != reader) return;
    }
    // Native pause can finish after the notification has already shown Play.
    // Dispatch resume only after that pause completes, otherwise a late pause
    // can silence a player whose Dart/notification state already says playing.
    try {
      await _pendingPause;
      if (command != _transportCommand || !identical(tts, backend)) return;
      final active = await (_activateSessionOverride?.call() ??
          AudioSession.instance.then((session) => session.setActive(true)));
      if (!active) {
        AnxLog.warning('TTS transport play rejected: audio focus denied');
        return;
      }
    } catch (error) {
      AnxLog.warning('TTS transport preparation failed: ${error.runtimeType}');
      return;
    }
    if (command != _transportCommand || !identical(tts, backend)) return;
    if (resuming &&
        epubPlayerKey.currentState != null &&
        epubPlayerKey.currentState != reader) {
      return; // A newly opened book must not inherit this resume command.
    }
    if (!resuming &&
        (reader == null ||
            !reader.mounted ||
            epubPlayerKey.currentState != reader)) {
      return;
    }

    final item = resuming
        ? ttsMediaItem(
            bookId: previous.id,
            title: previous.title,
            author: previous.extras?['bookAuthor'] as String? ?? '',
            chapter: previous.extras?['ttsChapter'] as String? ?? '',
            coverPath: previous.extras?['ttsCoverPath'] as String? ?? '',
            state: TtsStateEnum.playing,
            chinese: _chinese,
          )
        : ttsMediaItem(
            bookId: reader!.book.id.toString(),
            title: reader.book.title,
            chapter: reader.chapterTitle,
            author: reader.book.author,
            coverPath: reader.book.coverFullPath,
            state: TtsStateEnum.playing,
            chinese: _chinese,
          );

    // Ensure system receives queue + active index for control center metadata.
    _publishMetadata(item);
    playbackState.add(ttsMediaState(playbackState.value, TtsStateEnum.playing,
            chinese: _chinese)
        .copyWith(
      queueIndex: 0,
      updatePosition: Duration.zero,
      bufferedPosition: Duration.zero,
    ));
    final resume = backend.ttsStateNotifier.value == TtsStateEnum.paused;
    backend.updateTtsState(TtsStateEnum.playing);
    // A media command must finish promptly, not hold its response open until
    // an entire book has finished. Later pause/stop remains authoritative.
    unawaited(
        Future<void>.sync(() => resume ? backend.resume() : backend.speak())
            .catchError((Object error) {
      AnxLog.warning('TTS playback command failed: ${error.runtimeType}');
      if (command == _transportCommand && identical(tts, backend)) {
        backend.updateTtsState(TtsStateEnum.paused);
      }
    }));
  }

  @override
  Future<void> pause() async {
    final command = ++_transportCommand;
    _resumeAfterInterruption = false;
    playbackState.add(ttsMediaState(playbackState.value, TtsStateEnum.paused,
            chinese: _chinese)
        .copyWith(
      queueIndex: queue.value.isNotEmpty ? 0 : null,
    ));

    final backend = tts;
    AnxLog.info('TTS transport pause');
    backend.updateTtsState(TtsStateEnum.paused);
    final previousPause = _pendingPause;
    final pausing = Future<void>.sync(() async {
      await previousPause;
      if (!identical(tts, backend)) return;
      if (command != _transportCommand &&
          backend.ttsStateNotifier.value == TtsStateEnum.stopped) {
        return;
      }
      await backend.pause();
    });
    _pendingPause = pausing;
    try {
      await pausing;
      if (command == _transportCommand && identical(tts, backend)) {
        backend.updateTtsState(TtsStateEnum.paused);
      }
    } finally {
      if (identical(_pendingPause, pausing)) _pendingPause = null;
    }
  }

  @override
  Future<void> stop() async {
    ++_transportCommand;
    _resumeAfterInterruption = false;
    playbackState.add(playbackState.value.copyWith(
      controls: [],
      systemActions: const {},
      androidCompactActionIndices: [],
      queueIndex: null,
      processingState: AudioProcessingState.idle,
      playing: false,
    ));

    tts.updateTtsState(TtsStateEnum.stopped);
    try {
      // The player loop may be awaiting a chapter from this reader. Dispatch
      // reader cancellation alongside backend shutdown, not after waiting for
      // that loop to finish (which would leave both sides waiting forever).
      await Future.wait<void>([
        Future<void>.sync(() async {
          await tts.stop();
        }),
        Future<void>.sync(() async {
          if (_stopReaderOverride != null) {
            await _stopReaderOverride();
          } else {
            await epubPlayerKey.currentState?.ttsStop();
          }
        }),
      ]);
    } finally {
      queue.add([]);
      mediaItem.add(null);
      if (_deactivateSessionOverride != null) {
        await _deactivateSessionOverride();
      } else {
        await (await AudioSession.instance).setActive(false);
      }
    }
  }

  @override
  Future<void> skipToNext() async {
    await playNext();
  }

  @override
  Future<void> skipToPrevious() async {
    await playPrevious();
  }

  Future<void> playPrevious() async {
    await tts.prev();
  }

  Future<void> playNext() async {
    await tts.next();
  }

  ValueNotifier<TtsStateEnum> get ttsStateNotifier => tts.ttsStateNotifier;

  bool get isPlaying => tts.isPlaying;

  set volume(double volume) {
    tts.volume = volume;
  }

  double get volume => tts.volume;

  set pitch(double pitch) {
    tts.pitch = pitch;
  }

  double get pitch => tts.pitch;

  set rate(double rate) {
    tts.rate = rate;
  }

  double get rate => tts.rate;
}
