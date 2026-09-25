import 'package:anx_reader/service/tts/mimo_voice_presets.dart';
import 'package:anx_reader/service/tts/readany_compatible_tts_backend.dart';
import 'package:anx_reader/widgets/settings/mimo_voice_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> config;
  setUp(() {
    config = {
      'model': MimoVoicePresets.model,
      'voice': '冰糖',
      'stylePrompt': '',
      'key': 'fixture-key',
      'baseUrl': 'https://proxy.example',
    };
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: MimoVoiceSettings(
            config: config,
            onChanged: (value) => setState(() => config = value),
          ),
        ),
      ))),
    ));
  }

  Future<void> choose(WidgetTester tester, Finder field, String label) async {
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('official presets keep exact IDs and do not mutate credentials',
      (tester) async {
    await open(tester);
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('mimo-voice')));
    expect(dropdown.initialValue, '冰糖');
    await choose(
        tester, find.byKey(const ValueKey('mimo-voice')), 'Chloe · English');
    expect(config['voice'], 'Chloe');
    expect(config['key'], 'fixture-key');
    expect(config['baseUrl'], 'https://proxy.example');
    expect(XiaomiMimoTtsProvider().bundledVoices.length, 9);
  });

  testWidgets(
      'templates remain editable and suggestions append without duplicates',
      (tester) async {
    await open(tester);
    await choose(
        tester, find.byType(DropdownButtonFormField<String>).last, '自然听书');
    expect(config['stylePrompt'], MimoVoicePresets.styles['自然听书']);
    await tester.enterText(
        find.byKey(const ValueKey('mimo-description')), '自己的描述');
    await tester.pump();
    final chip = find.widgetWithText(ActionChip, '吐字清晰');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
    expect(config['stylePrompt'], '自己的描述\n${MimoVoicePresets.phrases['吐字清晰']}');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'design mode requires description, retains preset for switching back',
      (tester) async {
    await open(tester);
    await choose(
        tester, find.byKey(const ValueKey('mimo-model')), 'Voice design');
    expect(find.byKey(const ValueKey('mimo-voice')), findsNothing);
    expect(
        find.text('Enter a description or select a template'), findsOneWidget);
    await choose(
        tester, find.byType(DropdownButtonFormField<String>).last, '沉稳男声');
    expect(config['stylePrompt'], MimoVoicePresets.designs['沉稳男声']);
    expect(find.text('Enter a description or select a template'), findsNothing);
    await choose(
        tester, find.byKey(const ValueKey('mimo-model')), 'Preset voices');
    expect(config['voice'], '冰糖');
    expect(config['stylePrompt'], MimoVoicePresets.designs['沉稳男声']);
  });

  testWidgets('unknown imported values and narrow layout are safe',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    config['voice'] = 'unknown-voice';
    config['model'] = 'unknown-model';
    await open(tester);
    await tester.pumpAndSettle();
    expect(config['voice'], 'unknown-voice');
    expect(tester.takeException(), isNull);
  });
}
