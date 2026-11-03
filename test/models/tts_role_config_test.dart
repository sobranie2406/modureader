import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/tts_role_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('config survives a JSON round trip', () {
    const config = TtsRoleConfig(
      enabled: true,
      narrationVoice: 'zh-CN-YunxiNeural',
      dialogueVoice: 'zh-CN-XiaoxiaoNeural',
      characters: [
        TtsCharacterRole(id: 'c1', name: '小明', voice: 'zh-CN-YunjianNeural'),
      ],
    );
    final decoded =
        TtsRoleConfig.fromMap(jsonDecode(jsonEncode(config.toMap())));
    expect(decoded, config);
  });

  test('malformed values fall back to a disabled configuration', () {
    expect(TtsRoleConfig.fromMap(null).enabled, isFalse);
    expect(TtsRoleConfig.fromMap('bad'), TtsRoleConfig.disabled);
    expect(
        TtsRoleConfig.fromMap({
          'enabled': 'yes',
          'narrationVoice': 7,
          'characters': [
            {'id': 'c1'},
            'junk'
          ],
        }),
        const TtsRoleConfig());
  });

  test('distinct voices require both a switch and two different voices', () {
    expect(const TtsRoleConfig(narrationVoice: 'a').isDistinct, isFalse);
    expect(
        const TtsRoleConfig(
                enabled: true, narrationVoice: 'a', dialogueVoice: 'a')
            .isDistinct,
        isFalse);
    expect(
        const TtsRoleConfig(
                enabled: true, narrationVoice: 'a', dialogueVoice: 'b')
            .isDistinct,
        isTrue);
    expect(const TtsRoleConfig(enabled: true).isDistinct, isFalse);
  });

  test('book override only replaces the fields it sets', () {
    const global = TtsRoleConfig(
      enabled: true,
      narrationVoice: 'narrator',
      dialogueVoice: 'dialogue',
    );
    expect(
      const TtsRoleBookOverride(dialogueVoice: 'other').resolve(global),
      const TtsRoleConfig(
        enabled: true,
        narrationVoice: 'narrator',
        dialogueVoice: 'other',
      ),
    );
    expect(const TtsRoleBookOverride().resolve(global), global);
  });

  test('prefs persist the global config and per-book deltas separately',
      () async {
    final prefs = Prefs();
    await prefs.saveTtsRoleConfig(const TtsRoleConfig(
      enabled: true,
      narrationVoice: 'narrator',
      dialogueVoice: 'dialogue',
    ));
    expect(prefs.ttsRoleConfig.narrationVoice, 'narrator');
    expect(prefs.ttsRoleConfigForBook(7).dialogueVoice, 'dialogue');

    await prefs.saveTtsRoleBookOverride(
        7, const TtsRoleBookOverride(dialogueVoice: 'book-voice'));
    expect(prefs.ttsRoleConfigForBook(7).dialogueVoice, 'book-voice');
    expect(prefs.ttsRoleConfigForBook(8).dialogueVoice, 'dialogue');

    await prefs.saveTtsRoleBookOverride(7, const TtsRoleBookOverride());
    expect(prefs.ttsRoleConfigForBook(7).dialogueVoice, 'dialogue');
  });

  test(
      'global and per-book voices are isolated by service and restored on return',
      () async {
    final prefs = Prefs();
    prefs.ttsService = 'edge';
    await prefs.saveTtsRoleConfig(
        const TtsRoleConfig(enabled: true, dialogueVoice: 'edge-voice'));
    await prefs.saveTtsRoleBookOverride(
        7, const TtsRoleBookOverride(dialogueVoice: 'edge-book'));
    prefs.ttsService = 'xiaomi-mimo';
    expect(prefs.ttsRoleConfig.enabled, isFalse);
    expect(prefs.ttsRoleBookOverride(7).isEmpty, isTrue);
    await prefs.saveTtsRoleConfig(
        const TtsRoleConfig(enabled: true, dialogueVoice: 'mimo-voice'));
    prefs.ttsService = 'edge';
    expect(prefs.ttsRoleConfig.dialogueVoice, 'edge-voice');
    expect(prefs.ttsRoleConfigForBook(7).dialogueVoice, 'edge-book');
    await prefs.saveTtsRoleConfig(TtsRoleConfig.disabled);
    prefs.ttsService = 'xiaomi-mimo';
    expect(prefs.ttsRoleConfig.dialogueVoice, 'mimo-voice');
  });

  test('a corrupt stored value never breaks narration', () async {
    SharedPreferences.setMockInitialValues({'ttsRoleConfig': '{oops'});
    await Prefs().initPrefs();
    expect(Prefs().ttsRoleConfig, TtsRoleConfig.disabled);
  });
}
