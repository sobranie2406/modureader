import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/tts/mimo_voice_presets.dart';
import 'package:anx_reader/service/tts/openai_voice_presets.dart';
import 'package:anx_reader/widgets/settings/mimo_voice_settings.dart';
import 'package:anx_reader/widgets/settings/openai_voice_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  for (final mimo in [true, false]) {
    testWidgets(
        '${mimo ? 'MiMo' : 'OpenAI'} French presets insert French instructions and preserve custom text',
        (tester) async {
      var config = <String, dynamic>{
        'model': mimo ? MimoVoicePresets.model : 'gpt-4o-mini-tts',
        'stylePrompt': 'MY CUSTOM STYLE',
        'instructions': 'MY CUSTOM STYLE',
      };
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: Scaffold(body: SingleChildScrollView(
            child: StatefulBuilder(builder: (context, setState) {
          void change(Map<String, dynamic> value) =>
              setState(() => config = value);
          return mimo
              ? MimoVoiceSettings(config: config, onChanged: change)
              : OpenAiVoiceSettings(config: config, onChanged: change);
        }))),
      ));
      await tester.pumpAndSettle();
      final editor = find
          .byKey(ValueKey(mimo ? 'mimo-description' : 'openai-description'));
      expect(
          tester.widget<TextField>(editor).controller!.text, 'MY CUSTOM STYLE');
      final original =
          (mimo ? MimoVoicePresets.styles : OpenAiVoicePresets.templates)
              .entries
              .first;
      final context = tester.element(editor);
      final label = ModuStrings.text(context, original.key, original.key);
      expect(label, isNot(original.key));
      final menus = find.byType(DropdownButtonFormField<String>);
      final menu = mimo ? menus.at(2) : menus.first;
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(config[mimo ? 'stylePrompt' : 'instructions'],
          ModuStrings.text(context, original.value, original.value));
      expect(tester.widget<TextField>(editor).controller!.text,
          config[mimo ? 'stylePrompt' : 'instructions']);
      expect(tester.takeException(), isNull);
    });
  }
}
