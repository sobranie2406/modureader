import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/readany_compatible_tts_backend.dart';
import 'package:anx_reader/service/tts/tts_synthesis_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final status in [401, 429, 503]) {
    test('DashScope HTTP $status uses shared safe error classification',
        () async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      await Prefs().saveOnlineTtsConfig('dashscope', {'key': 'fixture-only'});
      final client = MockClient((_) async => http.Response(
          'PRIVATE_RESPONSE', status,
          headers: {'retry-after': '4'}));
      addTearDown(client.close);
      final provider = DashScopeTtsProvider.forTesting(client: client);
      await expectLater(
          provider.speak('PRIVATE_TEXT', null, 1, 1),
          throwsA(isA<TtsSynthesisError>()
              .having((e) => e.statusCode, 'status', status)
              .having((e) => e.retryable, 'retryable', status != 401)
              .having(
                  (e) => e.retryAfter, 'cooldown', const Duration(seconds: 4))
              .having((e) => e.toString(), 'sanitized',
                  isNot(contains('PRIVATE')))));
    });
  }

  test('resolves relative and absolute speech endpoints', () {
    expect(
      resolveSpeechEndpoint(
        'https://example.com/',
        '/v1/audio/speech',
      ).toString(),
      'https://example.com/v1/audio/speech',
    );
    expect(
      resolveSpeechEndpoint(
        'https://ignored.example',
        'https://speech.example/custom',
      ).toString(),
      'https://speech.example/custom',
    );
  });

  test('decodes raw and JSON base64 audio responses', () {
    final raw = decodeTtsAudioResponse(http.Response.bytes(
      [1, 2, 3],
      200,
      headers: {'content-type': 'audio/mpeg'},
    ));
    expect(raw, [1, 2, 3]);

    final encoded = base64Encode([4, 5, 6]);
    final jsonAudio = decodeTtsAudioResponse(http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {
              'audio': {'data': encoded},
            },
          },
        ],
      }),
      200,
      headers: {'content-type': 'application/json'},
    ));
    expect(jsonAudio, [4, 5, 6]);
  });
}
