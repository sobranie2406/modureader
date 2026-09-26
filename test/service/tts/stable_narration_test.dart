import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/readany_compatible_tts_backend.dart';
import 'package:anx_reader/service/tts/stable_narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('steady narration preserves user style and is appended only once', () {
    expect(withStableNarration(null), stableNarrationInstruction);
    expect(withStableNarration('  '), stableNarrationInstruction);
    final prompt = withStableNarration('温柔女声，整体稍慢。');
    expect(prompt, '温柔女声，整体稍慢。\n$stableNarrationInstruction');
    expect(withStableNarration(prompt), prompt);
    expect(withStableNarration('  $prompt  '), prompt);
  });

  for (final design in [false, true]) {
    test('MiMo independent sentences share instructions (design=$design)',
        () async {
      final requests = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
            jsonEncode({
              'choices': [
                {
                  'finish_reason': 'stop',
                  'message': {
                    'audio': {
                      'data': base64Encode([1, 2, 3])
                    }
                  },
                }
              ],
            }),
            200);
      });
      addTearDown(client.close);
      await Prefs().saveOnlineTtsConfig('xiaomi', {
        'key': 'test-only',
        'voice': '茉莉',
        'model': design ? 'mimo-v2.5-tts-voicedesign' : 'mimo-v2.5-tts',
        'stylePrompt': '温柔女声，整体稍慢。',
      });
      final provider = XiaomiMimoTtsProvider.forTesting(client: client);
      final before = provider.getConfig();
      for (final text in ['短句。', '这是带有对话情绪的另一句：“真的吗？！”']) {
        await provider.speak(text, null, 1, 1);
        expect(requests.last['messages'].last,
            {'role': 'assistant', 'content': text});
      }
      expect(requests[0]['messages'].first, requests[1]['messages'].first);
      expect(requests[0]['messages'].first['content'],
          '温柔女声，整体稍慢。\n$stableNarrationInstruction');
      expect(provider.getConfig(), before);
    });
  }

  for (final model in [
    'qwen3-tts-flash',
    'qwen3-tts-instruct-flash',
    'qwen3-tts-instruct-flash-2026-01-26',
    'custom-tts'
  ]) {
    test('DashScope instruction capability is gated for $model', () async {
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response.bytes([1, 2, 3], 200,
            headers: {'content-type': 'audio/mpeg'});
      });
      addTearDown(client.close);
      await Prefs().saveOnlineTtsConfig('dashscope', {
        'key': 'test-only',
        'model': model,
        'voice': 'Cherry',
      });
      final provider = DashScopeTtsProvider.forTesting(client: client);
      await provider.speak('正文不变。', null, 1.2, 1);
      expect(body['input'], '正文不变。');
      expect(body['voice'], 'Cherry');
      expect(body['speed'], 1.2);
      if (model.startsWith('qwen3-tts-instruct-flash')) {
        expect(body['instructions'], contains(stableNarrationInstruction));
      } else {
        expect(body.containsKey('instructions'), isFalse);
      }
      expect(provider.getConfig()['stylePrompt'], '');
    });
  }
}
