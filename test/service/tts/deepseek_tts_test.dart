import 'dart:convert';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/tts/deepseek_tts_backend.dart';
import 'package:modu_reader/service/tts/tts_synthesis_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal RIFF/WAVE header; the player only needs a recognizable container.
final wave = <int>[
  ...ascii.encode('RIFF'),
  0x24,
  0x00,
  0x00,
  0x00,
  ...ascii.encode('WAVE'),
  ...ascii.encode('fmt '),
  0x10,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0x3e,
  0x00,
  0x00,
  0x00,
  0x7d,
  0x00,
  0x00,
  0x02,
  0x00,
  0x10,
  0x00,
  ...ascii.encode('data'),
  0x00,
  0x00,
  0x00,
  0x00,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DeepSeekTtsProvider provider;
  late Map<String, dynamic> body;
  late Uri requestUrl;
  late Map<String, String> requestHeaders;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    provider =
        DeepSeekTtsProvider.forTesting(client: MockClient((request) async {
      requestUrl = request.url;
      requestHeaders = request.headers;
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response.bytes(wave, 200,
          headers: {'content-type': 'audio/wav'});
    }));
  });

  Future<void> config(Map<String, dynamic> values) => Prefs()
      .saveOnlineTtsConfig('deepseek', {'key': 'fixture-key', ...values});

  test('posts the documented request to the DeepSeek TTS endpoint', () async {
    await config({});
    final audio = await provider.speak('你好，我是 DeepSeek。', null, 1, 1);

    expect(audio, wave);
    expect(requestUrl.toString(), 'https://api.deepseek.com/v1/tools/tts');
    expect(requestHeaders['Authorization'], 'Bearer fixture-key');
    expect(body['text'], '你好，我是 DeepSeek。');
    expect(body['voice_id'], 'stella');
    expect(body['format'], 'wav');
    expect(body['filter_markdown'], isTrue);
    // The service has no speed or pitch parameter.
    expect(body.containsKey('speed'), isFalse);
    expect(body.containsKey('rate'), isFalse);
    expect(body.containsKey('pitch'), isFalse);
  });

  test('sends the tide voice and a disabled markdown filter', () async {
    await config({'voice': 'tide', 'filterMarkdown': 'false'});
    await provider.speak('正文', null, 1, 1);
    expect(body['voice_id'], 'tide');
    expect(body['filter_markdown'], isFalse);
  });

  test('an unknown stored voice falls back to stella', () async {
    await config({'voice': 'alloy'});
    expect(provider.getSelectedVoice(), 'stella');
    await provider.speak('正文', null, 1, 1);
    expect(body['voice_id'], 'stella');
  });

  test('a per-run voice overrides the selection but stays in the catalog',
      () async {
    await config({});
    await provider.speak('正文', 'tide', 1, 1);
    expect(body['voice_id'], 'tide');
    await expectLater(
        provider.speak('正文', 'alloy', 1, 1),
        throwsA(isA<TtsSynthesisError>().having(
            (e) => e.reason, 'reason', TtsFailureReason.configuration)));
  });

  test('a missing key fails before any request', () async {
    await Prefs().saveOnlineTtsConfig('deepseek', {'voice': 'stella'});
    await expectLater(
        provider.speak('正文', null, 1, 1),
        throwsA(isA<TtsSynthesisError>().having(
            (e) => e.reason, 'reason', TtsFailureReason.configuration)));
  });

  test('documented error codes keep their retry policy without echoing bodies',
      () async {
    await config({});
    const reasons = {
      400: TtsFailureReason.http,
      429: TtsFailureReason.http,
      503: TtsFailureReason.http,
      504: TtsFailureReason.http,
    };
    for (final entry in reasons.entries) {
      final client = MockClient((_) async => http.Response(
          'PRIVATE_BOOK fixture-key', entry.key,
          headers: {'retry-after': '3'}));
      addTearDown(client.close);
      final failing = DeepSeekTtsProvider.forTesting(client: client);
      await expectLater(
          failing.speak('正文', null, 1, 1),
          throwsA(isA<TtsSynthesisError>()
              .having((e) => e.statusCode, 'status', entry.key)
              .having((e) => e.reason, 'reason', entry.value)
              .having((e) => e.retryable, 'retryable',
                  [429, 503, 504].contains(entry.key))
              .having(
                  (e) => e.retryAfter, 'cooldown', const Duration(seconds: 3))
              .having((e) => e.toString(), 'no content',
                  isNot(contains('PRIVATE_BOOK')))
              .having((e) => e.toString(), 'no key',
                  isNot(contains('fixture-key')))));
    }
  });

  test('a non-WAV body is rejected as invalid audio', () async {
    await config({});
    final client = MockClient((_) async => http.Response.bytes(
        ascii.encode('{"error":"not audio"}'), 200,
        headers: {'content-type': 'application/json'}));
    addTearDown(client.close);
    await expectLater(
        DeepSeekTtsProvider.forTesting(client: client).speak('正文', null, 1, 1),
        throwsA(isA<TtsSynthesisError>()
            .having((e) => e.reason, 'reason', TtsFailureReason.invalidAudio)));
  });

  test('a body shorter than content-length is a truncated stream', () async {
    await config({});
    final client =
        MockClient((_) async => http.Response.bytes(wave, 200, headers: {
              'content-type': 'audio/wav',
              'content-length': '${wave.length + 64}',
            }));
    addTearDown(client.close);
    await expectLater(
        DeepSeekTtsProvider.forTesting(client: client).speak('正文', null, 1, 1),
        throwsA(isA<TtsSynthesisError>()
            // A cut stream is not a length limit; retrying cannot help here.
            .having((e) => e.reason, 'reason', TtsFailureReason.truncated)
            .having((e) => e.retryable, 'retryable', isFalse)));
  });

  test('a custom endpoint and boolean config survive a save round-trip',
      () async {
    final saved = provider.getConfig();
    expect(saved['voice'], 'stella');
    expect(saved['filterMarkdown'], 'true');
    provider.saveConfig({
      'url': 'https://proxy.test/v1/tools/tts',
      'key': 'k',
      'voice': 'tide',
      'filterMarkdown': false,
    });
    final reloaded = provider.getConfig();
    expect(reloaded['url'], 'https://proxy.test/v1/tools/tts');
    expect(reloaded['voice'], 'tide');
    // Provider config values are strings, matching every other service.
    expect(reloaded['filterMarkdown'], 'false');
  });

  test('the bundled voice list contains exactly the two documented voices',
      () async {
    final voices = await provider.getVoices();
    expect(voices.map((v) => v.shortName), ['stella', 'tide']);
    expect(voices.map((v) => v.locale), ['zh-CN', 'zh-CN']);
  });
}
