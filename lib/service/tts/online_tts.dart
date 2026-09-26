import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/readany_compatible_tts_backend.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:anx_reader/service/tts/tts_provider.dart';
import 'package:anx_reader/service/tts/tts_text_filter.dart';
import 'package:anx_reader/service/tts/audio_mime_type.dart';
import 'package:anx_reader/service/tts/models/tts_segment.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class OnlineTts extends BaseTts {
  static final OnlineTts _instance = OnlineTts._internal();

  factory OnlineTts() {
    return _instance;
  }

  OnlineTts._internal();

  @visibleForTesting
  OnlineTts.forTesting({
    required Future<List<TtsSentence>> Function(int) collect,
    Future<Uint8List> Function(String)? synthesize,
    TtsServiceProvider? backend,
    Future<void> Function(TtsSegment)? play,
    AudioPlayer? player,
    AudioPlayer Function()? createPlayer,
    Future<void> Function(TtsSegment)? highlight,
  })  : assert(synthesize != null || backend != null),
        _backendOverride = backend,
        _collectOverride = collect,
        _synthesizeOverride = synthesize,
        _playOverride = play,
        _highlightOverride = highlight,
        _player = player,
        _createPlayer = createPlayer;

  Future<List<TtsSentence>> Function(int)? _collectOverride;
  Future<Uint8List> Function(String)? _synthesizeOverride;
  Future<void> Function(TtsSegment)? _playOverride;
  Future<void> Function(TtsSegment)? _highlightOverride;
  bool _isHighlighting = false;
  String? _playbackError;
  @override
  String? get playbackError => _playbackError;

  // ============ Configuration ============
  static const int _bufferCapacity =
      4; // Bounded paragraph groups, not sentences.
  static const int _batchSize = 2; // Avoid competing with the current passage.
  static const int _maxRetries = 2;
  static final TtsCache _audioCache = TtsCache(maxEntries: 256);

  // ============ Audio Player ============
  AudioPlayer? _player;
  AudioPlayer Function()? _createPlayer;
  StreamSubscription<void>? _playerCompleteSubscription;
  Future<void>? _stopping;

  // ============ Ordered Buffer ============
  // Segments are added in order; audio is fetched in background
  final List<TtsSegment> _buffer = [];
  TtsSegment? _currentSegment;
  String? _currentVoiceText;
  int _audioFetchVersion = 0; // Version counter for audio fetches
  final Set<Completer<void>> _fetchCancellations = {};
  // ============ Prefetcher State ============
  bool _isPrefetcherRunning = false;
  Completer<void>? _prefetcherCompleter;

  // ============ Player State ============
  bool _isPlayerRunning = false;
  Completer<void>? _playerCompleter;
  Completer<void>? _playbackCompleter;

  // ============ Lifecycle ============
  late Function getHereFunction;
  late Function getNextTextFunction;
  late Function getPrevTextFunction;
  bool isInit = false;
  bool _shouldStop = false;
  int _generation = 0;
  int _commandVersion = 0;
  bool _isStarting = false;
  int _controlVersion = 0;
  Future<void> _audioControl = Future<void>.value();
  bool? _navigationPlaying;

  // ============ Backend ============
  TtsServiceProvider? _currentBackend;
  TtsServiceProvider? _backendOverride;

  TtsServiceProvider get backend {
    if (_backendOverride != null) return _backendOverride!;
    TtsService service = getTtsService(Prefs().ttsService);
    if (_currentBackend?.service != service) {
      _currentBackend = service.provider;
    }
    return _currentBackend!;
  }

  // ============ TtsStateNotifier ============
  @override
  final ValueNotifier<TtsStateEnum> ttsStateNotifier =
      ValueNotifier<TtsStateEnum>(TtsStateEnum.stopped);

  @override
  void updateTtsState(TtsStateEnum newState) {
    ttsStateNotifier.value = newState;
  }

  // ============ Properties ============
  @override
  double get volume => Prefs().ttsVolume;

  @override
  set volume(double volume) {
    Prefs().ttsVolume = volume;
    final player = _player;
    if (player != null) {
      unawaited(player.setVolume(volume).catchError((Object error) {
        AnxLog.warning('TTS volume update failed: ${error.runtimeType}');
      }));
    }
  }

  @override
  double get pitch => Prefs().ttsPitch;

  @override
  set pitch(double pitch) {
    if (!pitch.isFinite || pitch < 0.5 || pitch > 2 || pitch == this.pitch)
      return;
    Prefs().ttsPitch = pitch;
    // Clear pending audio so it will be re-fetched with new pitch
    _clearPendingAudio();
  }

  @override
  set rate(double rate) {
    if (!rate.isFinite || rate < 0 || rate > 2 || rate == this.rate) return;
    Prefs().ttsRate = _usesPlaybackRate ? rate.clamp(0.5, 2.0) : rate;
    if (_usesPlaybackRate) {
      // Keep synthesized/prefetched audio: MiMo speed is a playback property.
      final player = _player;
      final command = _commandVersion;
      unawaited(_serializeAudioControl(() async {
        if (command != _commandVersion ||
            player == null ||
            !identical(player, _player) ||
            !isPlaying ||
            _playbackCompleter?.isCompleted != false) {
          return;
        }
        await player.setPlaybackRate(_playbackRate);
      }).catchError((Object error) {
        if (command == _commandVersion) _controlFailed(error);
      }));
      return;
    }
    // Clear pending audio so it will be re-fetched with new rate
    _clearPendingAudio();
  }

  @override
  double get rate => Prefs().ttsRate;

  bool get _usesPlaybackRate => backend is XiaomiMimoTtsProvider;
  double get _playbackRate => rate.isFinite ? rate.clamp(0.5, 2.0) : 1.0;
  double get _synthesisRate => _usesPlaybackRate ? 1.0 : rate;

  @override
  bool get isPlaying => ttsStateNotifier.value == TtsStateEnum.playing;

  @override
  String? get currentVoiceText => _currentVoiceText;

  @override
  Future<List<TtsVoice>> getVoices() async {
    return await backend.getVoices();
  }

  // ============ Initialization ============
  @override
  Future<void> init(Function getCurrentText, Function getNextText,
      Function getPrevText) async {
    getHereFunction = getCurrentText;
    getNextTextFunction = getNextText;
    getPrevTextFunction = getPrevText;
    isInit = true;
  }

  // ============ Audio Player Management ============
  AudioContext _audioContext({required bool preview}) => AudioContext(
        android: AudioContextAndroid(
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.media,
          stayAwake: true,
          // The reading session owns focus; a settings preview has no session.
          audioFocus: preview ? AndroidAudioFocus.gain : AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(options: {
          if (Prefs().allowMixWithOtherAudio)
            AVAudioSessionOptions.mixWithOthers,
        }),
      );

  Future<AudioPlayer> _ensurePlayer({bool preview = false}) async {
    if (_player != null) {
      await _player!.setAudioContext(_audioContext(preview: preview));
      return _player!;
    }
    final player = _createPlayer?.call() ?? AudioPlayer();
    try {
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setPlayerMode(PlayerMode.mediaPlayer);
      await player.setAudioContext(_audioContext(preview: preview));
      await player.setVolume(volume);
      _playerCompleteSubscription = player.onPlayerComplete.listen((_) {
        if (identical(_player, player) &&
            _playbackCompleter?.isCompleted == false) {
          _playbackCompleter!.complete();
        }
      });
      // Publish only after successful native initialization. Never reuse a
      // half-configured player on the next sentence/retry.
      _player = player;
      return player;
    } catch (_) {
      await _releasePlayer(player, null);
      rethrow;
    }
  }

  Future<void> _disposePlayer() async {
    final player = _player;
    final subscription = _playerCompleteSubscription;
    _player = null;
    _playerCompleteSubscription = null;
    await _releasePlayer(player, subscription);
  }

  Future<void> _releasePlayer(
      AudioPlayer? player, StreamSubscription<void>? subscription) async {
    // Detach before awaiting. A plugin failure must not retain a half-disposed
    // player or prevent subsequent cleanup/restart from the notification.
    for (final release in <Future<void> Function()>[
      if (player != null) player.stop,
      if (subscription != null) subscription.cancel,
      if (player != null) player.dispose,
    ]) {
      try {
        await release();
      } catch (error) {
        AnxLog.warning('TTS player cleanup failed: ${error.runtimeType}');
      }
    }
  }

  // ============ Buffer Management ============
  void _resetBuffer() {
    _buffer.clear();
    _currentSegment = null;
    _currentVoiceText = null;
  }

  /// Clear audio for all pending segments (not currently playing)
  /// so they will be re-fetched with new settings
  void _clearPendingAudio() {
    _audioFetchVersion++; // Increment version to invalidate in-flight fetches
    for (final segment in _buffer) {
      // Clear audio so it will be re-fetched
      segment.audio = null;
      segment.isSilent = false;
      segment.error = null;
      segment.fetchVersion = _audioFetchVersion; // Mark with current version
    }
    AnxLog.info(
        'Cleared pending audio buffer - will re-fetch with new settings (version: $_audioFetchVersion)');
  }

  // ============ Producer: Prefetcher Loop ============
  Future<void> _startPrefetcher() async {
    if (_isPrefetcherRunning) return;
    _isPrefetcherRunning = true;
    _prefetcherCompleter = Completer<void>();

    try {
      while (!_shouldStop) {
        // Check for segments that need audio re-fetch (after settings change)
        final segmentsNeedingAudio =
            _buffer.where((s) => !s.isReady && !s.isSilent).toList();

        if (segmentsNeedingAudio.isNotEmpty) {
          // Re-fetch audio for segments that were cleared
          for (var i = 0; i < segmentsNeedingAudio.length; i += _batchSize) {
            if (_shouldStop) break;
            final batch =
                segmentsNeedingAudio.skip(i).take(_batchSize).toList();
            final futures =
                batch.map((segment) => _fetchAudioForSegment(segment));
            await Future.wait(futures);
          }
        }

        // Refill only at a stable consumer cursor. In particular, do not peek
        // while the last sentence is advancing to the next chapter, or that
        // chapter's current (first) sentence can be excluded from the batch.
        if (_buffer.isNotEmpty || _currentSegment != null) {
          await Future.delayed(const Duration(milliseconds: 50));
          continue;
        }

        // Collect sentences from the reader
        final sentences = await _collectSentences(_bufferCapacity);

        if (sentences.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 100));
          continue;
        }

        // Create placeholder segments in ORDER first
        final newSegments = <TtsSegment>[];
        for (final sentence in sentences) {
          if (_shouldStop) break;
          final segment = TtsSegment(sentence: sentence);
          segment.fetchVersion = _audioFetchVersion;
          newSegments.add(segment);
          _buffer.add(segment); // Add in order!
        }

        // Now fetch audio in batches to limit concurrency
        for (var i = 0; i < newSegments.length;) {
          if (_shouldStop) break;
          // Get the first passage ready before issuing speculative work.
          final size = i == 0 ? 1 : _batchSize;
          final batch = newSegments.skip(i).take(size).toList();
          final futures =
              batch.map((segment) => _fetchAudioForSegment(segment));
          await Future.wait(futures);
          i += size;
        }
      }
    } catch (e) {
      AnxLog.severe('Prefetcher error: $e');
      if (!_shouldStop) {
        _playbackError = '朗读文本获取失败，请重试 / Could not read speech text; retry.';
        _shouldStop = true;
        updateTtsState(TtsStateEnum.paused);
      }
    } finally {
      _isPrefetcherRunning = false;
      _prefetcherCompleter?.complete();
      _prefetcherCompleter = null;
    }
  }

  Future<List<TtsSentence>> _collectSentences(int count) async {
    if (_collectOverride != null) return _collectOverride!(count);
    final state = epubPlayerKey.currentState;
    if (state == null) return [];

    try {
      final sentences = await state.ttsCollectDetails(
        count: count,
        includeCurrent: true,
      );

      // Note: We do NOT call getNextTextFunction here.
      // Advancing the reader position should only happen in the player loop
      // after playback completes, to avoid interfering with highlighting.

      return sentences;
    } catch (e) {
      AnxLog.severe('Collect sentences error: $e');
      rethrow;
    }
  }

  Future<void> _fetchAudioForSegment(TtsSegment segment) async {
    if (_shouldStop) return;
    if (segment.isReady) return;

    // Punctuation-only paragraphs (such as "……") produce no speech. Keep a
    // silent segment in the ordered buffer so only the consumer advances the
    // reader cursor, including when this separator ends a chapter.
    if (isTtsSeparator(segment.sentence.text)) {
      segment.isSilent = true;
      return;
    }

    // Capture the version at the start of fetching
    final targetVersion = segment.fetchVersion;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      if (_shouldStop || segment.fetchVersion != targetVersion) return;
      if (segment.isReady) return;

      try {
        if (_synthesizeOverride != null) {
          final bytes =
              await _untilStopped(_synthesizeOverride!(segment.sentence.text));
          if (bytes == null) return;
          if (_shouldStop || segment.fetchVersion != targetVersion) return;
          if (bytes.isEmpty) throw StateError('Empty speech audio');
          segment.audio = bytes;
          return;
        }
        final currentBackend = backend;
        final voice = currentBackend.getSelectedVoice();
        final bytes = await _untilStopped(_audioCache
            .synthesize(
              _ProviderAdapter(
                provider: currentBackend,
                rate: _synthesisRate,
                pitch: pitch,
                voice: voice,
              ),
              TtsRequest(
                text: segment.sentence.text,
                voice: voice,
                model: currentBackend.serviceId,
                parameters: {
                  'rate': _synthesisRate.toStringAsFixed(4),
                  'pitch': pitch.toStringAsFixed(4),
                  'config': currentBackend.cacheConfiguration(),
                },
              ),
            )
            .timeout(
                currentBackend.synthesisTimeout + const Duration(seconds: 1))
            .then((audio) => audio.bytes));
        if (bytes == null) return;

        // Check if version is still valid (settings haven't changed during fetch)
        if (_shouldStop || segment.fetchVersion != targetVersion) {
          AnxLog.info(
              'Audio fetch completed but version changed - discarding (segment version: ${segment.fetchVersion}, target: $targetVersion)');
          return;
        }

        if (bytes.isEmpty) {
          throw StateError('Empty speech audio');
        } else {
          segment.audio = Uint8List.fromList(bytes);
        }
        return; // Success, exit retry loop
      } on TimeoutException {
        if (_shouldStop || segment.fetchVersion != targetVersion) return;
        AnxLog.severe(
            'TTS fetch timeout (attempt ${attempt + 1}/${_maxRetries + 1})');
        if (attempt == _maxRetries) {
          // Check version before marking as silent
          if (segment.fetchVersion == targetVersion) {
            segment.error = TimeoutException('Speech synthesis timed out');
          }
        }
      } catch (e) {
        if (_shouldStop || segment.fetchVersion != targetVersion) return;
        AnxLog.severe(
            'TTS fetch failed (attempt ${attempt + 1}): ${e.runtimeType}');
        if (attempt == _maxRetries) {
          // Check version before marking as silent
          if (segment.fetchVersion == targetVersion) {
            segment.error = e;
          }
        }
      }
    }
  }

  // ============ Consumer: Player Loop ============
  // A navigation command must not wait for a remote paragraph to finish.
  // The request may still finish/cache its result, but cannot touch the old
  // cursor or playback buffer after cancellation (including late errors).
  Future<T?> _untilStopped<T>(Future<T> request) async {
    final cancellation = Completer<void>();
    _fetchCancellations.add(cancellation);
    try {
      return await Future.any<T?>([
        request,
        cancellation.future.then<T?>((_) => null),
      ]);
    } finally {
      // Do not retain every completed audio result on a session-long future.
      _fetchCancellations.remove(cancellation);
    }
  }

  Future<void> _startPlayer() async {
    if (_isPlayerRunning) return;
    _isPlayerRunning = true;
    _playerCompleter = Completer<void>();

    try {
      final audioPlayer = _playOverride == null ? await _ensurePlayer() : null;
      while (!_shouldStop) {
        if (ttsStateNotifier.value == TtsStateEnum.paused) {
          await Future.delayed(const Duration(milliseconds: 30));
          continue;
        }
        // Wait for buffer to have a segment
        while (_buffer.isEmpty && !_shouldStop) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        if (_shouldStop) break;
        if (ttsStateNotifier.value == TtsStateEnum.paused) continue;

        // Get the FIRST segment (preserving order)
        final segment = _buffer.first;

        // Wait for this segment's audio to be ready
        while (!segment.isReady && !_shouldStop) {
          await Future.delayed(const Duration(milliseconds: 30));
        }
        if (_shouldStop) break;
        if (ttsStateNotifier.value == TtsStateEnum.paused) continue;
        if (segment.error != null) {
          _playbackError =
              '语音生成失败，已保留当前位置，请重试 / Speech synthesis failed; retry this sentence.';
          _shouldStop = true;
          updateTtsState(TtsStateEnum.paused);
          break;
        }

        // Now remove it from buffer
        _buffer.removeAt(0);
        _currentSegment = segment;
        _currentVoiceText = segment.sentence.text;

        // Presentation must never gate audio on a suspended/background WebView.
        unawaited(_highlightSegment(segment));
        if (_shouldStop) break;

        // Silent separators still pass through the normal pause/stop and
        // cursor-advance path below, but never reach the audio player.
        if (!segment.isSilent) {
          _playbackCompleter = Completer<void>();
          final source = BytesSource(segment.audio!,
              mimeType: ttsAudioMimeType(segment.audio!));

          try {
            if (_playOverride != null) {
              await _playOverride!(segment);
            } else {
              if (_usesPlaybackRate) {
                await audioPlayer!.setPlaybackRate(_playbackRate);
              }
              await audioPlayer!.play(source);
              await _playbackCompleter!.future;
            }
          } catch (e) {
            AnxLog.severe('Playback error: $e');
            if (!_shouldStop) {
              _buffer.insert(0, segment);
              _playbackError =
                  '音频播放失败，请重试 / Audio playback failed; retry this sentence.';
              _shouldStop = true;
              updateTtsState(TtsStateEnum.paused);
            }
          }
        }

        _playbackCompleter = null;
        // Advance reader position
        if (!_shouldStop) {
          while (
              ttsStateNotifier.value == TtsStateEnum.paused && !_shouldStop) {
            await Future.delayed(const Duration(milliseconds: 30));
          }
          if (!_shouldStop) {
            final next = await getNextTextFunction();
            if (next == null || (next is String && next.trim().isEmpty)) {
              _shouldStop = true;
              updateTtsState(TtsStateEnum.stopped);
            }
          }
        }
        _currentSegment = null;
      }
    } catch (e) {
      AnxLog.severe('Player loop error: $e');
      if (!_shouldStop) {
        _playbackError = '朗读定位失败，请重试 / Reader navigation failed; retry.';
        _shouldStop = true;
        updateTtsState(TtsStateEnum.paused);
      }
    } finally {
      _isPlayerRunning = false;
      _playerCompleter?.complete();
      _playerCompleter = null;
    }
  }

  Future<void> _highlightSegment(TtsSegment segment) async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    if (_isHighlighting) return;
    _isHighlighting = true;
    try {
      if (_highlightOverride != null) {
        await _highlightOverride!(segment);
      } else {
        final state = epubPlayerKey.currentState;
        final cfi = segment.sentence.cfi;
        if (state == null || cfi == null || cfi.isEmpty) return;
        await state.ttsHighlightByCfi(cfi);
      }
    } catch (_) {
      // Visual feedback is optional; speech/navigation owns the cursor.
    } finally {
      _isHighlighting = false;
    }
  }

  // ============ Public API ============
  @override
  Future<void> speak({String? content}) async {
    final stopping = _stopping;
    if (stopping != null) await stopping;
    if (_isPlayerRunning || _isStarting) return;
    _isStarting = true;
    final generation = ++_generation;
    // A naturally ended/failed producer may still be finishing its current
    // request. Do not revive that old loop by clearing the stop flag early.
    if (_shouldStop) await _prefetcherCompleter?.future;
    if (generation != _generation) return;
    _shouldStop = false;
    _playbackError = null;
    updateTtsState(TtsStateEnum.playing);

    // Sync to current location first
    dynamic here;
    try {
      here = content ?? await getHereFunction();
    } catch (_) {
      if (generation == _generation) {
        _shouldStop = true;
        _playbackError = '朗读初始化失败，请重试 / Could not start reading; retry.';
        updateTtsState(TtsStateEnum.paused);
      }
      return;
    } finally {
      if (generation == _generation) _isStarting = false;
    }
    if (_shouldStop || generation != _generation) return;
    if (here is String && here.trim().isEmpty) {
      _shouldStop = true;
      updateTtsState(TtsStateEnum.stopped);
      return;
    }

    // Start both loops
    unawaited(_startPrefetcher());
    await _startPlayer();
  }

  @override
  Future<void> stop({bool forNavigation = false}) async {
    if (!forNavigation) {
      _navigationPlaying = null;
      // Explicit Stop wins even when navigation is already cleaning up.
      updateTtsState(TtsStateEnum.stopped);
    }
    ++_commandVersion;
    final pending = _stopping;
    if (pending != null) return pending;
    final operation = _stop(forNavigation: forNavigation);
    _stopping = operation;
    try {
      await operation;
    } finally {
      _stopping = null;
    }
  }

  Future<void> _stop({bool forNavigation = false}) async {
    ++_generation;
    _isStarting = false;
    _shouldStop = true;
    _playbackError = null;
    for (final cancellation in _fetchCancellations.toList()) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
    updateTtsState(forNavigation ? TtsStateEnum.paused : TtsStateEnum.stopped);

    // Complete any pending playback
    if (_playbackCompleter?.isCompleted == false) {
      _playbackCompleter!.complete();
    }

    // Wait for loops to finish
    await _prefetcherCompleter?.future;
    await _playerCompleter?.future;

    // Cleanup
    await _disposePlayer();
    _resetBuffer();
  }

  @override
  Future<void> pause() async {
    if (_navigationPlaying != null) _navigationPlaying = false;
    updateTtsState(TtsStateEnum.paused);
    final command = _commandVersion;
    final control = ++_controlVersion;
    try {
      await _serializeAudioControl(() async {
        if (command != _commandVersion || control != _controlVersion) return;
        await _player?.pause();
      });
    } catch (error) {
      if (command == _commandVersion && control == _controlVersion) {
        _controlFailed(error);
      }
    }
  }

  // Serialize native controls, not the lifetime of the speech loop. The last
  // requested state wins even when Android completes pause/resume out of order.
  Future<void> _serializeAudioControl(Future<void> Function() action) {
    final operation = _audioControl.then((_) => action());
    _audioControl =
        operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }

  @override
  Future<void> resume() async {
    if (_navigationPlaying != null) {
      _navigationPlaying = true;
      return;
    }
    final command = _commandVersion;
    final control = ++_controlVersion;
    Future<void>? playback;
    try {
      await _serializeAudioControl(() async {
        if (command != _commandVersion || control != _controlVersion) return;
        final stopping = _stopping;
        if (stopping != null) await stopping;
        if (command != _commandVersion || control != _controlVersion) return;
        if (_shouldStop && _playbackError == null && !_isPlayerRunning) {
          // Manual navigation while paused has a cursor but no active player.
          playback = speak(content: _currentVoiceText);
        } else if (_shouldStop && _playbackError != null) {
          await _prefetcherCompleter?.future;
          await _playerCompleter?.future;
          if (command != _commandVersion || control != _controlVersion) return;
          await _disposePlayer();
          if (command != _commandVersion || control != _controlVersion) return;
          _currentSegment = null;
          _clearPendingAudio();
          _playbackError = null;
          _shouldStop = false;
          updateTtsState(TtsStateEnum.playing);
          unawaited(_startPrefetcher());
          playback = _startPlayer();
        } else {
          // A completed source remains loaded in the native player. Resuming
          // it while the consumer waits for the reader/next audio can replay
          // the previous sentence. Only resume an unfinished active segment;
          // otherwise restore the loop state and let it play the next source.
          if (!_isPlayerRunning || _playbackCompleter?.isCompleted == false) {
            if (_usesPlaybackRate) {
              await _player?.setPlaybackRate(_playbackRate);
            }
            await _player?.resume();
          }
          if (command == _commandVersion && control == _controlVersion) {
            updateTtsState(TtsStateEnum.playing);
          }
        }
      });
    } catch (error) {
      if (command == _commandVersion && control == _controlVersion) {
        _controlFailed(error);
      }
    }
    // The lock covers recovery only, not the duration of the resumed audio.
    // A later pause must still be resumable while this future is running.
    if (playback != null) await playback;
  }

  void _controlFailed(Object error) {
    _playbackError =
        '音频控制失败，已保留当前位置，请重试 / Audio control failed; retry this sentence.';
    _shouldStop = true;
    final segment = _currentSegment;
    if (segment != null && !_buffer.contains(segment))
      _buffer.insert(0, segment);
    if (_playbackCompleter?.isCompleted == false)
      _playbackCompleter!.complete();
    updateTtsState(TtsStateEnum.paused);
    AnxLog.warning('TTS player control failed: ${error.runtimeType}');
  }

  @override
  Future<void> prev() async {
    await _navigate(() => getPrevTextFunction());
  }

  @override
  Future<void> next() async {
    await _navigate(() => getNextTextFunction());
  }

  @override
  Future<void> restart() async {
    await _navigate(() => getHereFunction());
  }

  Future<void> _navigate(FutureOr<dynamic> Function() locate) async {
    _navigationPlaying ??= isPlaying;
    final previousText = _currentVoiceText;
    final stopping = stop(forNavigation: true);
    final command = _commandVersion;
    await stopping;
    if (command != _commandVersion) return;
    try {
      final text = await locate();
      if (command != _commandVersion) return;
      final wasPlaying = _navigationPlaying == true;
      _navigationPlaying = null;
      if (text is String && text.isNotEmpty) {
        _currentVoiceText = text;
        if (wasPlaying) {
          await speak(content: text);
        } else {
          updateTtsState(TtsStateEnum.paused);
        }
      } else {
        _currentVoiceText = previousText;
      }
    } catch (error) {
      if (command != _commandVersion) return;
      _navigationPlaying = null;
      _playbackError = '朗读定位失败，请重试 / Reader navigation failed; retry.';
      updateTtsState(TtsStateEnum.paused);
      AnxLog.warning('TTS navigation failed: ${error.runtimeType}');
    }
  }

  /// For testing a specific voice in settings
  Future<void> speakWithVoice(String content, String voice) async {
    await stop();
    final audioPlayer = await _ensurePlayer(preview: true);

    final bytes = await backend.speak(content, voice, _synthesisRate, pitch);
    if (bytes.isNotEmpty) {
      final source = BytesSource(bytes, mimeType: ttsAudioMimeType(bytes));
      if (_usesPlaybackRate) {
        await audioPlayer.setPlaybackRate(_playbackRate);
      }
      await audioPlayer.play(source);
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    isInit = false;
  }
}

class _ProviderAdapter implements TtsProvider {
  const _ProviderAdapter({
    required this.provider,
    required this.rate,
    required this.pitch,
    required this.voice,
  });

  final TtsServiceProvider provider;
  final double rate;
  final double pitch;
  final String voice;

  @override
  Future<TtsAudioChunk> synthesize(TtsRequest request) async {
    final bytes = await provider.speak(request.text, voice, rate, pitch);
    return TtsAudioChunk(bytes: bytes, mimeType: ttsAudioMimeType(bytes));
  }
}
