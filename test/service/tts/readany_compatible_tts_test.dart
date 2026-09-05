import 'dart:convert';

import 'package:anx_reader/service/tts/readany_compatible_tts_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
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
