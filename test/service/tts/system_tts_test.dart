import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:anx_reader/service/tts/system_tts_support.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  late SystemTts tts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    calls.clear();
    tts = SystemTts.forTesting(supported: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      calls.add(call);
      if (call.method == 'getVoices') {
        return [
          {'name': 'test-voice', 'locale': 'zh-CN'}
        ];
      }
      return 1;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'), null);
  });

  test('fresh install speaks using native default without selecting a voice',
      () async {
    await tts.speak(content: '默认声线测试');
    expect(calls.map((c) => c.method), contains('speak'));
    expect(calls.map((c) => c.method), isNot(contains('setVoice')));
    expect(Prefs().getTtsVoiceModel('system'), isEmpty);
  });

  test('explicit saved voice is applied before speaking', () async {
    Prefs().setTtsVoiceModel('system', 'test-voice');
    await tts.speak(content: '已选声线测试');
    final methods = calls.map((c) => c.method).toList();
    expect(methods.indexOf('setVoice'), lessThan(methods.indexOf('speak')));
    expect(calls.firstWhere((c) => c.method == 'setVoice').arguments,
        {'name': 'test-voice', 'locale': 'zh-CN'});
  });

  test('voice missing on this device falls back without failing', () async {
    Prefs().setTtsVoiceModel('system', 'voice-from-another-device');
    await tts.speak(content: '声线迁移测试');
    expect(calls.map((c) => c.method), contains('speak'));
    expect(calls.map((c) => c.method), isNot(contains('setVoice')));
  });

  test(
      'unsupported platform can initialize and switch away without native calls',
      () async {
    tts = SystemTts.forTesting(supported: false);
    await tts.init(() async {}, () async => '', () async => '');
    expect(await tts.getVoices(), isEmpty);
    await tts.stop();
    await tts.dispose();
    await expectLater(
        tts.speak(content: 'Do not send this online'), throwsUnsupportedError);
    await expectLater(
        tts.speakWithVoice('test', 'voice'), throwsUnsupportedError);
    expect(calls, isEmpty);
    expect(Prefs().ttsService, 'system'); // No implicit network fallback.
  });

  test('support list matches native plugin implementations', () {
    for (final os in ['android', 'ios', 'macos', 'windows']) {
      expect(supportsSystemTts(operatingSystem: os), isTrue);
    }
    for (final os in ['linux', 'ohos']) {
      expect(supportsSystemTts(operatingSystem: os), isFalse);
    }
  });

  test('online provider default and explicit voices are unchanged', () {
    expect(TtsService.openai.provider.resolveVoice(null), 'alloy');
    expect(TtsService.openai.provider.resolveVoice('nova'), 'nova');
  });
}
