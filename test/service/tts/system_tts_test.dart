import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/system_voice_identity.dart';
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

  test('reader initialization does not query unused native defaults', () async {
    await tts.init(() async => '正文', () async => '', () async => '');
    expect(
        calls.map((call) => call.method),
        isNot(
            anyOf(contains('getDefaultVoice'), contains('getDefaultEngine'))));
  });

  test('native error releases a hung completion and retries the same sentence',
      () async {
    final hung = Completer<int>();
    final submitted = Completer<void>();
    var failing = true;
    var advances = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      calls.add(call);
      if (call.method == 'speak' && failing) {
        submitted.complete();
        return hung.future;
      }
      if (call.method == 'stop' && !hung.isCompleted) hung.complete(0);
      return 1;
    });
    await tts.init(() async => '保留原句', () async {
      advances++;
      return '';
    }, () async => '');
    tts.updateTtsState(TtsStateEnum.playing);
    final reading = tts.speak();
    await submitted.future;
    // The actual Android plugin sends this event but leaves speak unresolved.
    await tts.flutterTts.platformCallHandler(const MethodCall(
        'speak.onError', 'Error from TextToSpeech (speak) - -6'));
    await reading.timeout(const Duration(seconds: 1));
    expect(tts.ttsStateNotifier.value, TtsStateEnum.paused);
    expect(tts.currentVoiceText, '保留原句');
    expect(tts.playbackError, isNotNull);
    expect(advances, 0);
    expect(calls.map((call) => call.method), contains('stop'));
    failing = false;
    await tts.resume();
    expect(advances, 1);
    expect(tts.playbackError, isNull);
    await tts.stop();
  });

  test('missing native start times out without skipping text', () async {
    tts = SystemTts.forTesting(
        supported: true, startTimeout: const Duration(milliseconds: 10));
    final hung = Completer<int>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'speak') return hung.future;
      if (call.method == 'stop' && !hung.isCompleted) hung.complete(0);
      return 1;
    });
    var advances = 0;
    await tts.init(() async => '不要跳过', () async {
      advances++;
      return '';
    }, () async => '');
    tts.updateTtsState(TtsStateEnum.playing);
    await tts.speak().timeout(const Duration(seconds: 1));
    expect(advances, 0);
    expect(tts.currentVoiceText, '不要跳过');
    expect(tts.playbackError, contains('未开始播放'));
    expect(tts.bufferingNotifier.value, isFalse);
    await tts.stop();
  });

  test('start deadline never interrupts an already speaking long passage',
      () async {
    tts = SystemTts.forTesting(
        supported: true, startTimeout: const Duration(milliseconds: 10));
    final completion = Completer<int>();
    final submitted = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      calls.add(call);
      if (call.method == 'speak') {
        submitted.complete();
        return completion.future;
      }
      return 1;
    });
    final reading = tts.speak(content: '长段落');
    await submitted.future;
    await tts.flutterTts
        .platformCallHandler(const MethodCall('speak.onStart', true));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(calls.map((call) => call.method), isNot(contains('stop')));
    completion.complete(1);
    await reading;
    expect(tts.playbackError, isNull);
    await tts.stop();
  });

  test('explicit saved voice is applied before speaking', () async {
    Prefs().setTtsVoiceModel('system', 'test-voice');
    await tts.speak(content: '已选声线测试');
    final methods = calls.map((c) => c.method).toList();
    expect(methods.indexOf('setVoice'), lessThan(methods.indexOf('speak')));
    expect(calls.firstWhere((c) => c.method == 'setVoice').arguments,
        {'name': 'test-voice', 'locale': 'zh-CN'});
  });

  test('same-name voices have distinct IDs and each exact locale can be used',
      () async {
    final voices = [
      for (final locale in ['zh-Hant', 'zh-Hans', 'zh'])
        {'name': 'zh', 'locale': locale}
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      calls.add(call);
      return call.method == 'getVoices' ? [...voices, voices.first] : 1;
    });
    final available = await tts.getVoices();
    expect(available.length, 3);
    expect(available.map((voice) => voice.shortName).toSet().length, 3);
    for (var i = 0; i < voices.length; i++) {
      Prefs().setTtsVoiceModel('system', available[i].shortName);
      calls.clear();
      await tts.speak(content: '真实朗读');
      expect(calls.firstWhere((call) => call.method == 'setVoice').arguments,
          voices[i]);
    }
    final saved = Prefs().getTtsVoiceModel('system');
    calls.clear();
    await tts.speakWithVoice('试听', available[1].shortName);
    expect(calls.firstWhere((call) => call.method == 'setVoice').arguments,
        voices[1]);
    expect(Prefs().getTtsVoiceModel('system'), saved);
  });

  test('legacy name selection migrates and remains stable after list reorder',
      () async {
    var voices = [
      {'name': 'zh', 'locale': 'zh_Hant'},
      {'name': 'zh', 'locale': 'zh_Hans'},
    ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      calls.add(call);
      return call.method == 'getVoices' ? voices : 1;
    });
    Prefs().setTtsVoiceModel('system', 'zh');
    await tts.getVoices();
    final migrated = Prefs().getTtsVoiceModel('system');
    expect(migrated, systemVoiceId(voices.first));
    voices = voices.reversed.toList();
    await tts.speak(content: '迁移后朗读');
    expect(calls.firstWhere((call) => call.method == 'setVoice').arguments,
        {'name': 'zh', 'locale': 'zh_Hant'});
    expect(Prefs().getTtsVoiceModel('system'), migrated);
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

  test('missing Windows speech resources do not block opening or stopping',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      calls.add(call);
      if (call.method == 'speak' || call.method == 'getVoices') {
        throw PlatformException(
            code: 'windows_tts_unavailable', message: 'HRESULT=0x80070002');
      }
      return 1;
    });
    await tts.init(() async => '保留的正文', () async => '下一段', () async => '上一段');
    expect(calls.map((c) => c.method), isNot(contains('speak')));
    expect(await tts.getVoices(), isEmpty);
    tts.updateTtsState(TtsStateEnum.playing);
    await tts.speak();
    expect(tts.ttsStateNotifier.value, TtsStateEnum.paused);
    expect(tts.currentVoiceText, '保留的正文');
    expect(tts.playbackError, contains('系统语音包'));
    expect(tts.playbackError, contains('切换在线朗读'));
    expect(Prefs().ttsService, 'system'); // No unrequested online upload.
    await tts.stop();
    await tts.dispose();
  });

  test('Windows native failure can be retried without restarting the app',
      () async {
    var available = false;
    var advances = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      calls.add(call);
      if (call.method == 'speak' && !available) {
        throw PlatformException(code: 'windows_tts_unavailable');
      }
      return 1;
    });
    await tts.init(() async => '原段落', () async {
      advances++;
      return '';
    }, () async => '');
    tts.updateTtsState(TtsStateEnum.playing);
    await tts.speak();
    expect(advances, 0);
    expect(tts.currentVoiceText, '原段落');
    available = true;
    await tts.resume();
    expect(advances, 1);
    expect(tts.playbackError, isNull);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
  });

  test('settings preview receives actionable Windows error, not silent success',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'speak') {
        throw PlatformException(
            code: 'windows_tts_unavailable',
            message: 'Windows 系统朗读不可用，请安装系统语音包');
      }
      return call.method == 'getVoices' ? [] : 1;
    });
    await expectLater(
        tts.speakWithVoice('试听', ''),
        throwsA(isA<PlatformException>().having(
            (e) => e.message, 'actionable message', contains('系统语音包'))));
  });
}
