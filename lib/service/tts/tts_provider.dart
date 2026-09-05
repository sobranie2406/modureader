import 'dart:convert';

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
  TtsCache({this.maxEntries = 128}) : assert(maxEntries > 0);

  final int maxEntries;
  final Map<String, TtsAudioChunk> _entries = {};

  Future<TtsAudioChunk> synthesize(
    TtsProvider provider,
    TtsRequest request,
  ) async {
    final key = _key(request);
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }

    final result = await provider.synthesize(request);
    _entries[key] = result;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return result;
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
