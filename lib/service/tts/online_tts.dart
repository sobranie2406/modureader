import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:anx_reader/service/tts/tts_provider.dart';
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
    required Future<Uint8List> Function(String) synthesize,
    required Future<void> Function(TtsSegment) play,
  })  : _collectOverride = collect,
        _synthesizeOverride = synthesize,
        _playOverride = play;

  Future<List<TtsSentence>> Function(int)? _collectOverride;
  Future<Uint8List> Function(String)? _synthesizeOverride;
  Future<void> Function(TtsSegment)? _playOverride;
  String? _playbackError;
  @override
  String? get playbackError => _playbackError;

  // ============ Configuration ============
  static const int _bufferCapacity = 10;
  static const int _batchSize = 5; // Max concurrent fetches
  static const int _fetchTimeoutSeconds = 10;
  static const int _maxRetries = 2;
  static final TtsCache _audioCache = TtsCache(maxEntries: 256);

  // ============ Audio Player ============
  AudioPlayer? _player;
  StreamSubscription<void>? _playerCompleteSubscription;

  // ============ Ordered Buffer ============
  // Segments are added in order; audio is fetched in background
  final List<TtsSegment> _buffer = [];
  TtsSegment? _currentSegment;
  String? _currentVoiceText;
  int _audioFetchVersion = 0; // Version counter for audio fetches
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
  bool _isStarting = false;

  // ============ Backend ============
  TtsServiceProvider? _currentBackend;

  TtsServiceProvider get backend {
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
    _player?.setVolume(volume);
  }

  @override
  double get pitch => Prefs().ttsPitch;

  @override
  set pitch(double pitch) {
    Prefs().ttsPitch = pitch;
    // Clear pending audio so it will be re-fetched with new pitch
    _clearPendingAudio();
  }

  @override
  set rate(double rate) {
    Prefs().ttsRate = rate;
    // Clear pending audio so it will be re-fetched with new rate
    _clearPendingAudio();
  }

  @override
  double get rate => Prefs().ttsRate;

  @override
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
  Future<AudioPlayer> _ensurePlayer() async {
    if (_player != null) return _player!;

    _player = AudioPlayer();
    await _player!.setReleaseMode(ReleaseMode.stop);
    await _player!.setPlayerMode(PlayerMode.mediaPlayer);
    await _player!.setVolume(volume);

    _playerCompleteSubscription = _player!.onPlayerComplete.listen((_) {
      if (_playbackCompleter?.isCompleted == false) {
        _playbackCompleter!.complete();
      }
    });

    return _player!;
  }

  Future<void> _disposePlayer() async {
    await _player?.stop();
    await _playerCompleteSubscription?.cancel();
    _playerCompleteSubscription = null;
    await _player?.dispose();
    _player = null;
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
        for (var i = 0; i < newSegments.length; i += _batchSize) {
          if (_shouldStop) break;
          final batch = newSegments.skip(i).take(_batchSize).toList();
          final futures =
              batch.map((segment) => _fetchAudioForSegment(segment));
          await Future.wait(futures);
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

    // Capture the version at the start of fetching
    final targetVersion = segment.fetchVersion;

    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      if (_shouldStop) return;
      if (segment.isReady) return;

      try {
        if (_synthesizeOverride != null) {
          final bytes = await _synthesizeOverride!(segment.sentence.text);
          if (_shouldStop || segment.fetchVersion != targetVersion) return;
          if (bytes.isEmpty) throw StateError('Empty speech audio');
          segment.audio = bytes;
          return;
        }
        final currentBackend = backend;
        final voice = currentBackend.getSelectedVoice();
        final audio = await _audioCache
            .synthesize(
              _ProviderAdapter(
                provider: currentBackend,
                rate: rate,
                pitch: pitch,
                voice: voice,
              ),
              TtsRequest(
                text: segment.sentence.text,
                voice: voice,
                model: currentBackend.serviceId,
                parameters: {
                  'rate': rate.toStringAsFixed(4),
                  'pitch': pitch.toStringAsFixed(4),
                },
              ),
            )
            .timeout(Duration(seconds: _fetchTimeoutSeconds));
        final bytes = audio.bytes;

        // Check if version is still valid (settings haven't changed during fetch)
        if (segment.fetchVersion != targetVersion) {
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
        AnxLog.severe(
            'Fetch timeout (attempt ${attempt + 1}/$_maxRetries): "${segment.sentence.text.substring(0, segment.sentence.text.length.clamp(0, 20))}..."');
        if (attempt == _maxRetries) {
          // Check version before marking as silent
          if (segment.fetchVersion == targetVersion) {
            segment.error = TimeoutException('Speech synthesis timed out');
          }
        }
      } catch (e) {
        AnxLog.severe('Fetch error (attempt ${attempt + 1}): $e');
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
        if (segment.error != null || segment.isSilent) {
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

        // Highlight current sentence
        await _highlightSegment(segment);
        if (_shouldStop) break;

        // Play audio
        _playbackCompleter = Completer<void>();
        final source = BytesSource(segment.audio!, mimeType: 'audio/mp3');

        try {
          if (_playOverride != null) {
            await _playOverride!(segment);
          } else {
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
    final state = epubPlayerKey.currentState;
    final cfi = segment.sentence.cfi;
    if (state == null || cfi == null || cfi.isEmpty) return;
    try {
      await state.ttsHighlightByCfi(cfi);
    } catch (_) {}
  }

  // ============ Public API ============
  @override
  Future<void> speak({String? content}) async {
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
  Future<void> stop() async {
    ++_generation;
    _isStarting = false;
    _shouldStop = true;
    _playbackError = null;
    updateTtsState(TtsStateEnum.stopped);

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
    updateTtsState(TtsStateEnum.paused);
    await _player?.pause();
  }

  @override
  Future<void> resume() async {
    if (_shouldStop && _playbackError != null) {
      await _prefetcherCompleter?.future;
      await _playerCompleter?.future;
      _currentSegment = null;
      _clearPendingAudio();
      _playbackError = null;
      _shouldStop = false;
      updateTtsState(TtsStateEnum.playing);
      unawaited(_startPrefetcher());
      await _startPlayer();
      return;
    }
    await _player?.resume();
    updateTtsState(TtsStateEnum.playing);
  }

  @override
  Future<void> prev() async {
    await stop();
    final text = await getPrevTextFunction();
    if (text is String && text.isNotEmpty) await speak(content: text);
  }

  @override
  Future<void> next() async {
    await stop();
    final text = await getNextTextFunction();
    if (text is String && text.isNotEmpty) await speak(content: text);
  }

  @override
  Future<void> restart() async {
    await stop();
    await speak();
  }

  /// For testing a specific voice in settings
  Future<void> speakWithVoice(String content, String voice) async {
    await stop();
    final audioPlayer = await _ensurePlayer();

    final bytes = await backend.speak(content, voice, rate, pitch);
    if (bytes.isNotEmpty) {
      final source = BytesSource(bytes, mimeType: 'audio/mp3');
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
    return TtsAudioChunk(bytes: bytes, mimeType: 'audio/mpeg');
  }
}
