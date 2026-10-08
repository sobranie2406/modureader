import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/tts_buffer_settings.dart';
import 'package:anx_reader/service/config_transfer/tts_config_transfer.dart';
import 'package:anx_reader/service/config_transfer/settings_value_validation.dart';
import 'package:anx_reader/service/tts/tts_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Provider implements TtsProvider {
  int calls = 0;
  int size = 3;
  Completer<TtsAudioChunk>? pending;
  @override
  Future<TtsAudioChunk> synthesize(TtsRequest request) async {
    calls++;
    return pending?.future ??
        TtsAudioChunk(bytes: List.filled(size, 1), mimeType: 'audio/mpeg');
  }
}

TtsRequest request(String text) =>
    TtsRequest(text: text, voice: 'test', model: 'test');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('bounded settings persist, transfer, reset and accept legacy snapshots',
      () async {
    const settings = TtsBufferSettings(
        ahead: 8,
        maxCharacters: 600,
        concurrency: 3,
        paragraphPauseMs: 100,
        cacheMinutes: 30);
    Prefs().ttsBufferSettings = settings;
    final snapshot = TtsConfigTransfer.snapshot(Prefs());
    expect(snapshot['buffer'], settings.toMap());
    await TtsConfigTransfer.apply(Prefs(), TtsConfigTransfer.defaults());
    await TtsConfigTransfer.apply(Prefs(), snapshot);
    expect(Prefs().ttsBufferSettings.toMap(), settings.toMap());
    snapshot.remove('buffer');
    await TtsConfigTransfer.apply(Prefs(), snapshot);
    expect(
        Prefs().ttsBufferSettings.toMap(), const TtsBufferSettings().toMap());
    for (final entry in {
      'ahead': 13,
      'maxCharacters': 99,
      'concurrency': 5,
      'paragraphPauseMs': -1,
      'cacheMinutes': 121
    }.entries) {
      final invalid = settings.toMap()..[entry.key] = entry.value;
      expect(
          () => validateSettingsValue('ttsBufferSettings', jsonEncode(invalid)),
          throwsFormatException);
    }
    Prefs().prefs.setString('ttsBufferSettings', '{broken');
    expect(Prefs().ttsBufferSettings.ahead, 3);
  });

  test('byte budget evicts LRU and oversized audio is not cached', () async {
    final cache = TtsCache(maxBytes: 6);
    final provider = Provider();
    await cache.synthesize(provider, request('a'));
    await cache.synthesize(provider, request('b'));
    await cache.synthesize(provider, request('a'));
    await cache.synthesize(provider, request('c'));
    expect(provider.calls, 3);
    expect(cache.byteCount, 6);
    await cache.synthesize(provider, request('b'));
    expect(provider.calls, 4);
    provider.size = 7;
    await cache.synthesize(provider, request('oversized'));
    expect(cache.byteCount, 6);
    cache.clear();
    expect(cache.byteCount, 0);
  });

  test('TTL expires idle audio', () async {
    final cache = TtsCache();
    final provider = Provider();
    cache.setRetention(const Duration(milliseconds: 15));
    await cache.synthesize(provider, request('a'));
    expect(cache.entryCount, 1);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(cache.entryCount, 0);
    expect(cache.byteCount, 0);
    await cache.synthesize(provider, request('a'));
    expect(provider.calls, 2);
    cache.clear();
  });

  test('cache hits do not extend retention', () async {
    var now = DateTime(2026);
    final cache = TtsCache(now: () => now);
    addTearDown(cache.clear);
    final provider = Provider();
    cache.setRetention(const Duration(minutes: 10));
    await cache.synthesize(provider, request('a'));
    now = now.add(const Duration(minutes: 9));
    await cache.synthesize(provider, request('a'));
    expect(provider.calls, 1);
    now = now.add(const Duration(minutes: 1));
    expect(cache.entryCount, 0);
    await cache.synthesize(provider, request('a'));
    expect(provider.calls, 2);
  });

  test(
      'clear cannot be undone by in-flight synthesis; duplicate requests coalesce',
      () async {
    final cache = TtsCache();
    final provider = Provider()..pending = Completer<TtsAudioChunk>();
    final a = cache.synthesize(provider, request('a'));
    final b = cache.synthesize(provider, request('a'));
    expect(provider.calls, 1);
    cache.clear();
    provider.pending!
        .complete(const TtsAudioChunk(bytes: [1], mimeType: 'audio/mpeg'));
    expect((await a).bytes, [1]);
    expect((await b).bytes, [1]);
    expect(cache.entryCount, 0);
    provider.pending = null;
    await cache.synthesize(provider, request('a'));
    expect(provider.calls, 2);
    cache.clear();
  });
}
