import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/audio_mime_type.dart';
import 'package:anx_reader/service/tts/readany_compatible_tts_backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late XiaomiMimoTtsProvider provider;
  late http.Request request;
  late http.Response response;
  var calls = 0;
  const fixtureKey = 'fixture-not-a-real-credential';

  http.Response audioResponse({String finish = 'stop', String? data}) =>
      http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': finish,
                'message': {
                  'audio': {
                    'data': data ?? base64Encode([73, 68, 51, 0])
                  }
                }
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'});

  Future<void> config(Map<String, dynamic> values) =>
      Prefs().saveOnlineTtsConfig('xiaomi', {'key': fixtureKey, ...values});

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    calls = 0;
    response = audioResponse();
    final client = MockClient((r) async {
      calls++;
      request = r;
      return response;
    });
    addTearDown(client.close);
    provider = XiaomiMimoTtsProvider.forTesting(client: client);
    await config({});
  });

  test('official endpoint, bearer auth, assistant text and nested audio',
      () async {
    expect(await provider.speak('第一章\n正文不改写。', null, 1, 1), [73, 68, 51, 0]);
    expect(request.url.toString(),
        'https://api.xiaomimimo.com/v1/chat/completions');
    expect(request.headers['Authorization'], 'Bearer $fixtureKey');
    expect(jsonDecode(request.body), {
      'model': 'mimo-v2.5-tts',
      'messages': [
        {'role': 'assistant', 'content': '第一章\n正文不改写。'}
      ],
      'audio': {'format': 'mp3', 'voice': 'mimo_default'},
      'stream': false,
    });
  });

  test('style, rate and pitch are user instructions, never spoken input',
      () async {
    await config({'stylePrompt': '平稳讲述', 'voice': '冰糖'});
    await provider.speak('原文', null, 1.5, 0.8);
    final body = jsonDecode(request.body);
    expect(body['messages'][0]['role'], 'user');
    expect(body['messages'][0]['content'], contains('平稳讲述'));
    expect(body['messages'][0]['content'], contains('1.50'));
    expect(body['messages'][0]['content'], contains('降低'));
    expect(body['messages'][1], {'role': 'assistant', 'content': '原文'});
    for (final key in [
      'input',
      'voice',
      'speed',
      'instructions',
      'response_format'
    ]) {
      expect(body.containsKey(key), isFalse);
    }
  });

  test('legacy blank URL, old endpoint/model/voice/PCM become usable defaults',
      () async {
    await config({
      'baseUrl': '',
      'endpoint': '/v1/audio/speech',
      'model': 'MiMo-V2.5-TTS',
      'voice': 'default',
      'format': 'pcm'
    });
    await provider.speak('正文', 'default', 1, 1);
    expect(request.url.path, '/v1/chat/completions');
    expect(jsonDecode(request.body)['audio'],
        {'format': 'mp3', 'voice': 'mimo_default'});
    expect(provider.getConfig()['key'], fixtureKey);
  });

  test('legacy absolute official speech endpoint is repaired', () async {
    await config({'endpoint': 'https://api.xiaomimimo.com/v1/audio/speech'});
    await provider.speak('正文', null, 1, 1);
    expect(request.url.toString(),
        'https://api.xiaomimimo.com/v1/chat/completions');
  });

  test('custom proxy host and key are preserved during normalization',
      () async {
    await config({
      'baseUrl': 'https://proxy.example/v1',
      'endpoint': '/v1/audio/speech'
    });
    await provider.speak('正文', null, 1, 1);
    expect(request.url.toString(), 'https://proxy.example/v1/chat/completions');
    expect(provider.getConfig()['baseUrl'], 'https://proxy.example/v1');
  });

  test(
      'complete base URL and absolute custom endpoint resolve without duplication',
      () {
    expect(
        resolveMimoEndpoint('https://proxy.example/v1/chat/completions',
                '/v1/chat/completions')
            .path,
        '/v1/chat/completions');
    expect(
        resolveMimoEndpoint(
                'https://unused.example', 'https://proxy.example/custom')
            .toString(),
        'https://proxy.example/custom');
  });

  test(
      'rejects insecure remote endpoints or credentials in URLs before sending',
      () async {
    for (final endpoint in [
      'http://remote.example/v1/chat/completions',
      'https://user:password@remote.example/v1/chat/completions',
      'https://remote.example/v1/chat/completions?key=private'
    ]) {
      await config({'endpoint': endpoint});
      await expectLater(
          provider.speak('正文', null, 1, 1), throwsFormatException);
    }
    expect(calls, 0);
  });

  test('official voice list and explicit voice override', () async {
    expect((await provider.getVoices()).map((v) => v.shortName), [
      'mimo_default',
      '冰糖',
      '茉莉',
      '苏打',
      '白桦',
      'Mia',
      'Chloe',
      'Milo',
      'Dean'
    ]);
    await provider.speak('Hello', 'Chloe', 1, 1);
    expect(jsonDecode(request.body)['audio']['voice'], 'Chloe');
  });

  test('voice design omits voice and disables text rewriting', () async {
    await config({
      'model': 'mimo-v2.5-tts-voicedesign',
      'stylePrompt': '温柔的青年女声',
      'format': 'wav'
    });
    await provider.speak('必须原样朗读', 'default', 1, 1);
    final body = jsonDecode(request.body);
    expect(body['audio'], {'format': 'wav', 'optimize_text_preview': false});
    expect(body['messages'].last['content'], '必须原样朗读');
  });

  test('voice design requires explicit description', () async {
    await config({'model': 'mimo-v2.5-tts-voicedesign'});
    await expectLater(provider.speak('正文', null, 1, 1), throwsStateError);
    expect(calls, 0);
  });

  test('unsupported model and voice fail before any network request', () async {
    await config({'model': 'mimo-v2.5-tts-voiceclone'});
    await expectLater(provider.speak('正文', null, 1, 1), throwsStateError);
    await config({'voice': 'unsupported-voice'});
    await expectLater(provider.speak('正文', null, 1, 1), throwsStateError);
    expect(calls, 0);
  });

  test('missing key and empty text fail without sending', () async {
    await config({'key': ''});
    await expectLater(provider.speak('正文', null, 1, 1), throwsStateError);
    await config({});
    await expectLater(provider.speak(' ', null, 1, 1), throwsStateError);
    expect(calls, 0);
  });

  for (final status in [400, 401, 403, 404, 429, 500]) {
    test('HTTP $status gives actionable error without echoed secrets or text',
        () async {
      response = http.Response('$fixtureKey PRIVATE_BOOK_TEXT', status);
      await expectLater(
          provider.speak('正文', null, 1, 1),
          throwsA(isA<StateError>()
              .having((e) => e.toString(), 'status', contains('$status'))
              .having(
                  (e) => e.toString(), 'no secret', isNot(contains(fixtureKey)))
              .having((e) => e.toString(), 'no text',
                  isNot(contains('PRIVATE_BOOK_TEXT')))));
    });
  }

  test('invalid, empty, blocked or truncated audio cannot silently advance',
      () async {
    for (final r in [
      http.Response('not JSON', 200),
      http.Response('{}', 200),
      audioResponse(data: ''),
      audioResponse(data: '%%%'),
      audioResponse(finish: 'length'),
      audioResponse(finish: 'content_filter')
    ]) {
      response = r;
      await expectLater(provider.speak('正文', null, 1, 1), throwsStateError);
    }
  });

  test('WAV playback uses WAV MIME and MP3 stays MPEG', () {
    expect(ttsAudioMimeType(ascii.encode('RIFF0000WAVE')), 'audio/wav');
    expect(ttsAudioMimeType([73, 68, 51, 0]), 'audio/mpeg');
    expect(ttsAudioMimeType([]), 'audio/mpeg');
    expect(provider.synthesisTimeout, const Duration(seconds: 60));
  });

  testWidgets('settings offer only supported formats and models',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      final items = provider.getConfigItems(context);
      expect(
          items
              .firstWhere((i) => i.key == 'format')
              .options!
              .map((o) => o['value']),
          ['mp3', 'wav']);
      expect(
          items
              .firstWhere((i) => i.key == 'model')
              .options!
              .map((o) => o['value']),
          ['mimo-v2.5-tts', 'mimo-v2.5-tts-voicedesign']);
      return const SizedBox();
    })));
  });
}
