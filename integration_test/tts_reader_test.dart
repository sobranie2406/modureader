import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Explicit opt-in: this test speaks three public fixture sentences aloud.
// Preference writes are in-memory; no personal library or API config is read.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native system voice completes titles and text in cursor order',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
      body: Center(
          child: Text('Modu native TTS regression: synthetic chapter titles')),
    )));
    final tts = SystemTts();
    final sentences = ['Chapter one.', 'First paragraph.', 'Chapter two.'];
    final completed = <String>[];
    var index = 0;
    try {
      await tts.init(() async => sentences[index], () async {
        completed.add(tts.currentVoiceText!);
        index++;
        return index < sentences.length ? sentences[index] : '';
      }, () async => '');
      tts.updateTtsState(TtsStateEnum.playing);
      await tts.speak().timeout(const Duration(seconds: 60));
      expect(tts.playbackError, isNull);
      expect(completed, sentences);
      expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
      debugPrint(
          'NATIVE TTS PASS: 3 fixture utterances completed in order, including both chapter titles.');
    } finally {
      await tts.stop();
    }
  },
      skip: !const bool.fromEnvironment('MODU_NATIVE_TTS_TEST'),
      timeout: const Timeout(Duration(minutes: 3)));
}
