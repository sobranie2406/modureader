import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/service/config_transfer/tts_config_transfer.dart';
import 'package:anx_reader/widgets/settings/config_transfer_tile.dart';
import 'package:anx_reader/service/tts/mimo_voice_presets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ttsService': 'openai',
      'onlineTtsConfig_openai': '{"key":"old-test-key"}',
      'unrelated': 'unchanged',
    });
    await Prefs().initPrefs();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: Locale('en'),
      home: Scaffold(body: NarrateSettings()),
    )));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'model editing preserves desktop IME and Android middle insertion',
      (tester) async {
    await open(tester);
    final model = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Model');
    await tester.ensureVisible(model);
    await tester.showKeyboard(model);
    final controller = tester.widget<TextField>(model).controller!;
    const value = TextEditingValue(
      text: 'qwen3-ttsff',
      selection: TextSelection.collapsed(offset: 11),
      composing: TextRange(start: 9, end: 11),
    );
    tester.testTextInput.updateEditingValue(value);
    await tester.pump();
    expect(tester.widget<TextField>(model).controller, same(controller));
    expect(controller.value, value);
    const inserted = TextEditingValue(
      text: 'Xqwen3-ttsff',
      selection: TextSelection.collapsed(offset: 1),
    );
    tester.testTextInput.updateEditingValue(inserted);
    await tester.pump();
    expect(controller.value, inserted);
    await tap(tester, 'Save settings');
    expect(Prefs().getOnlineTtsConfig('openai')['model'], 'Xqwen3-ttsff');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'service edits remain drafts until saved and export uses saved data',
      (tester) async {
    await open(tester);
    final keyField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'API Key');
    await tester.enterText(keyField, 'new-test-key');
    await tester.pumpAndSettle();
    expect(Prefs().getOnlineTtsConfig('openai')['key'], 'old-test-key');
    expect(find.byType(ConfigTransferTile), findsNothing);
    await tap(tester, 'Save settings');
    expect(Prefs().getOnlineTtsConfig('openai')['key'], 'new-test-key');
    expect(find.byType(ConfigTransferTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'MiMo description and connection fields save together and transfer',
      (tester) async {
    Prefs().ttsService = 'xiaomi';
    await Prefs().saveOnlineTtsConfig('xiaomi', {
      'key': 'mimo-fixture-key',
      'voice': '茉莉',
      'model': MimoVoicePresets.designModel,
      'stylePrompt': '原描述',
    });
    await open(tester);
    final field = find.byKey(const ValueKey('mimo-description'));
    await tester.ensureVisible(field);
    await tester.enterText(field, MimoVoicePresets.designs['温柔女声']!);
    await tester.pumpAndSettle();
    final keyField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'API key');
    await tester.ensureVisible(keyField);
    await tester.enterText(keyField, 'edited-mimo-fixture-key');
    await tester.pumpAndSettle();
    expect(Prefs().getOnlineTtsConfig('xiaomi')['stylePrompt'], '原描述');
    await tap(tester, 'Save settings');
    final saved = Prefs().getOnlineTtsConfig('xiaomi');
    expect(saved['stylePrompt'], MimoVoicePresets.designs['温柔女声']);
    expect(saved['key'], 'edited-mimo-fixture-key');
    expect(saved['voice'], '茉莉');
    final snapshot = TtsConfigTransfer.snapshot(Prefs());
    await Prefs().saveOnlineTtsConfig('xiaomi', {});
    await TtsConfigTransfer.apply(Prefs(), snapshot);
    expect(Prefs().getOnlineTtsConfig('xiaomi'), saved);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OpenAI description, toggle and connection share a saved draft',
      (tester) async {
    await open(tester);
    final field = find.byKey(const ValueKey('openai-description'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '声音温暖，语速稍慢。');
    await tester.pumpAndSettle();
    final toggle =
        find.widgetWithText(SwitchListTile, 'Enable speech instructions');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final keyField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'API Key');
    await tester.ensureVisible(keyField);
    await tester.enterText(keyField, 'new-fixture-key');
    await tester.pumpAndSettle();
    expect(Prefs().getOnlineTtsConfig('openai')['instructions'], isNull);
    await tap(tester, 'Save settings');
    final saved = Prefs().getOnlineTtsConfig('openai');
    expect(saved['instructions'], '声音温暖，语速稍慢。');
    expect(saved['instructionsEnabled'], 'false');
    expect(saved['key'], 'new-fixture-key');
    final snapshot = TtsConfigTransfer.snapshot(Prefs());
    await Prefs().saveOnlineTtsConfig('openai', {});
    await TtsConfigTransfer.apply(Prefs(), snapshot);
    expect(Prefs().getOnlineTtsConfig('openai'), saved);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear requires confirmation and resets only TTS',
      (tester) async {
    await open(tester);
    await tap(tester, 'Clear settings');
    await tap(tester, 'Cancel');
    expect(Prefs().getOnlineTtsConfig('openai')['key'], 'old-test-key');
    await tap(tester, 'Clear settings');
    await tap(tester, 'Clear');
    expect(TtsConfigTransfer.snapshot(Prefs()), TtsConfigTransfer.defaults());
    expect(Prefs().prefs.getString('unrelated'), 'unchanged');
    expect(tester.takeException(), isNull);
  });
}
