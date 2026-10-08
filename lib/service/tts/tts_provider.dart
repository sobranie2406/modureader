import 'dart:convert';
import 'dart:async';

import 'package:crypto/crypto.dart';

class TtsRequest {
  const TtsRequest({
    required this.text,
    required this.voice,
    required this.model,
    this.parameters = const {},
  });

  final String text;
  final String voice;
  final String model;
  final Map<String, String> parameters;
}

class TtsAudioChunk {
  const TtsAudioChunk({required this.bytes, required this.mimeType});

  final List<int> bytes;
  final String mimeType;
}

abstract interface class TtsProvider {
  Future<TtsAudioChunk> synthesize(TtsRequest request);
}

/// Small in-memory LRU cache. A disk-backed implementation can use the same
/// request key without changing Provider or playback contracts.
class TtsCache {
  TtsCache(
      {this.maxEntries = 128,
      this.maxBytes = 32 * 1024 * 1024,
      DateTime Function()? now})
      : assert(maxEntries > 0),
        assert(maxBytes > 0),
        _now = now ?? DateTime.now;

  final int maxEntries;
  final int maxBytes;
  final DateTime Function() _now;
  final Map<String, ({TtsAudioChunk audio, DateTime created})> _entries = {};
  final Map<String, Future<TtsAudioChunk>> _pending = {};
  Duration? _retention;
  Timer? _expiry;
  int _bytes = 0;
  int _epoch = 0;

  int get byteCount {
    _prune();
    return _bytes;
  }

  int get entryCount {
    _prune();
    return _entries.length;
  }

  /// Null retains the session cache until clear; positive TTLs expire even idle.
  void setRetention(Duration? duration) {
    assert(duration == null || duration > Duration.zero);
    _retention = duration;
    _prune();
    _scheduleExpiry();
  }

  void clear() {
    _epoch++;
    _expiry?.cancel();
    _expiry = null;
    _entries.clear();
    _pending.clear();
    _bytes = 0;
  }

  void _remove(String key) {
    final entry = _entries.remove(key);
    if (entry != null) _bytes -= entry.audio.bytes.length;
  }

  void _prune() {
    final ttl = _retention;
    if (ttl == null) return;
    final now = _now();
    for (final entry in _entries.entries.toList()) {
      if (!entry.value.created.add(ttl).isAfter(now)) _remove(entry.key);
    }
  }

  void _scheduleExpiry() {
    _expiry?.cancel();
    _expiry = null;
    final ttl = _retention;
    if (ttl == null || _entries.isEmpty) return;
    final oldest = _entries.values
        .map((entry) => entry.created)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final remaining = oldest.add(ttl).difference(_now());
    _expiry = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      _prune();
      _scheduleExpiry();
    });
  }

  Future<TtsAudioChunk> synthesize(
    TtsProvider provider,
    TtsRequest request,
  ) async {
    final key = _key(request);
    _prune();
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached.audio;
    }
    final pending = _pending[key];
    if (pending != null) return pending;
    final epoch = _epoch;
    final operation =
        Future<TtsAudioChunk>.sync(() => provider.synthesize(request));
    _pending[key] = operation;
    try {
      final result = await operation;
      // Clear cannot be undone by a request already in flight. Oversized audio
      // can still play, but must not evict the whole cache or exceed its budget.
      if (epoch == _epoch &&
          result.bytes.isNotEmpty &&
          result.bytes.length <= maxBytes) {
        _entries[key] = (audio: result, created: _now());
        _bytes += result.bytes.length;
        while (_entries.length > maxEntries || _bytes > maxBytes) {
          _remove(_entries.keys.first);
        }
        _scheduleExpiry();
      }
      return result;
    } finally {
      if (identical(_pending[key], operation)) _pending.remove(key);
    }
  }

  String _key(TtsRequest request) {
    final parameters = request.parameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final payload = jsonEncode({
      'text': request.text,
      'voice': request.voice,
      'model': request.model,
      'parameters': {for (final entry in parameters) entry.key: entry.value},
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }
}
