import 'package:anx_reader/service/local_data/local_data_store.dart';

class TtsPipeline {
  TtsPipeline(String text)
      : sentences = _split(text),
        _index = 0;

  final List<String> sentences;
  int _index;

  String? get current => _index < sentences.length ? sentences[_index] : null;

  String? next() {
    if (_index >= sentences.length - 1) {
      _index = sentences.length;
      return null;
    }
    _index++;
    return current;
  }

  static List<String> _split(String text) {
    final matches = RegExp(r'.+?(?:[。！？.!?]|$)', dotAll: true)
        .allMatches(text)
        .map((match) => match.group(0)!.trim())
        .where((sentence) => sentence.isNotEmpty)
        .toList();
    return matches;
  }
}

enum TtsPlaybackStatus { stopped, playing, paused, completed }

class TtsPlaybackItem {
  const TtsPlaybackItem({required this.location, required this.text});

  final ReaderLocation location;
  final String text;
}

typedef TtsSpeakCallback = Future<void> Function(TtsPlaybackItem item);

/// Coordinates sentence playback without coupling the reader to one TTS SDK.
/// The callback can be backed by system TTS or any online provider.
class TtsPlaybackController {
  TtsPlaybackController(
      {required Iterable<TtsPlaybackItem> items, required this.speak})
      : _items = List.unmodifiable(items);

  final List<TtsPlaybackItem> _items;
  final TtsSpeakCallback speak;
  int _index = 0;
  TtsPlaybackStatus _status = TtsPlaybackStatus.stopped;
  Future<void>? _running;

  TtsPlaybackStatus get status => _status;

  TtsPlaybackItem? get current =>
      _index < _items.length ? _items[_index] : null;

  Future<void> playFrom(ReaderLocation location) {
    final index = _items.indexWhere((item) => item.location == location);
    if (index < 0) {
      throw StateError('No TTS item found for reader location');
    }
    _index = index;
    _status = TtsPlaybackStatus.playing;
    return _run();
  }

  void pause() {
    if (_status == TtsPlaybackStatus.playing) {
      _status = TtsPlaybackStatus.paused;
    }
  }

  Future<void> resume() {
    if (_status != TtsPlaybackStatus.paused) return Future<void>.value();
    _status = TtsPlaybackStatus.playing;
    return _run();
  }

  void stop() {
    _status = TtsPlaybackStatus.stopped;
  }

  Future<void> next() {
    if (_index < _items.length - 1) _index++;
    return _status == TtsPlaybackStatus.playing ? _run() : Future<void>.value();
  }

  Future<void> _run() {
    final running = _running;
    if (running != null) return running;

    final future = _playLoop();
    _running = future;
    return future.whenComplete(() {
      if (identical(_running, future)) _running = null;
    });
  }

  Future<void> _playLoop() async {
    while (_status == TtsPlaybackStatus.playing && current != null) {
      await speak(current!);
      if (_status != TtsPlaybackStatus.playing) return;
      if (_index >= _items.length - 1) {
        _status = TtsPlaybackStatus.completed;
      } else {
        _index++;
      }
    }
  }
}
