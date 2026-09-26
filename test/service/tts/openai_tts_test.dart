import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/openai_tts_backend.dart';
import 'package:anx_reader/service/tts/openai_voice_presets.dart';
import 'package:anx_reader/service/tts/stable_narration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OpenAiTtsProvider provider;
  late Map<String, dynamic> body;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    provider = OpenAiTtsProvider.forTesting(client: MockClient((request) async {
      body = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response.bytes([1, 2, 3], 200);
    }));
  });

  Future<void> config(Map<String, dynamic> values) =>
      Prefs().saveOnlineTtsConfig(
          'openai', {'key': 'fixture-key', 'voice': 'nova', ...values});

  test('every template is instructions, never input or a voice ID', () async {
    for (final prompt in OpenAiVoicePresets.templates.values) {
      await config({'instructions': prompt});
      await provider.speak('正文保持原样。', null, 1, 1);
      expect(body['instructions'], '$prompt\n$stableNarrationInstruction');
      expect(body['input'], '正文保持原样。');
      expect(body['voice'], 'nova');
      expect(body.containsKey('speed'), isFalse);
    }
  });

  test('empty style receives steady narration without overriding target speed',
      () async {
    await config({'instructions': '  '});
    await provider.speak('正文', null, 1, 1);
    expect(body['instructions'], stableNarrationInstruction);
    expect(body.containsKey('speed'), isFalse);
  });

  test('non-neutral sliders use speed and pitch without rewriting user style',
      () async {
    await config({'instructions': '温暖柔和'});
    await provider.speak('正文', null, 1.3, 0.8);
    expect(body['speed'], 1.3);
    expect(body['instructions'], startsWith('温暖柔和\n'));
    expect(body['instructions'], contains('lower pitch'));
    expect(body['instructions'], isNot(contains('speed')));
  });

  test('disabled instructions retain description and never send pitch prompt',
      () async {
    await config({'instructions': '稍慢', 'instructionsEnabled': 'false'});
    await provider.speak('正文', null, 0.8, 1.2);
    expect(body.containsKey('instructions'), isFalse);
    expect(body['speed'], 0.8);
    expect(provider.getConfig()['instructions'], '稍慢');
  });

  test(
      'legacy models omit instructions; third party model names remain allowed',
      () async {
    for (final model in ['tts-1', 'tts-1-hd', 'custom-tts']) {
      await config({'model': model, 'instructions': '稍慢'});
      await provider.speak('正文', null, 1, 1);
      expect(body.containsKey('instructions'), model == 'custom-tts');
      expect(body['model'], model);
    }
  });

  test('speed clamps and non-finite slider values are omitted', () async {
    await config({});
    await provider.speak('正文', null, 0, 1);
    expect(body['speed'], 0.25);
    await provider.speak('正文', null, 5, 1);
    expect(body['speed'], 4);
    await provider.speak('正文', null, double.nan, double.infinity);
    expect(body.containsKey('speed'), isFalse);
    expect(body['instructions'], stableNarrationInstruction);
  });
}
