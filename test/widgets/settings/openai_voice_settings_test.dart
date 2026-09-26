import 'package:anx_reader/service/tts/openai_voice_presets.dart';
import 'package:anx_reader/widgets/settings/openai_voice_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> config;
  late StateSetter rebuild;
  setUp(() => config = {
        'model': 'gpt-4o-mini-tts',
        'voice': 'nova',
        'instructions': '旧描述',
        'key': 'fixture-key',
      });
  Future<void> open(WidgetTester tester) async {
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return OpenAiVoiceSettings(
            config: config,
            onChanged: (value) => setState(() => config = value));
      }),
    ))));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'presets replace only description; chips append once; clear works',
      (tester) async {
    await open(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('睡前轻读').last);
    await tester.pumpAndSettle();
    expect(config['instructions'], OpenAiVoicePresets.templates['睡前轻读']);
    final field = find.byKey(const ValueKey('openai-description'));
    await tester.enterText(field, '自己的描述');
    await tester.pump();
    final chip = find.widgetWithText(ActionChip, '温暖音色');
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    await tester.tap(chip);
    await tester.pump();
    expect(
        config['instructions'], '自己的描述\n${OpenAiVoicePresets.phrases['温暖音色']}');
    expect(config['voice'], 'nova');
    expect(config['key'], 'fixture-key');
    await tester.ensureVisible(find.text('Clear description'));
    await tester.tap(find.text('Clear description'));
    await tester.pump();
    expect(config['instructions'], '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabling retains prompt; legacy model switches preserve draft',
      (tester) async {
    await open(tester);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(config['instructionsEnabled'], 'false');
    expect(config['instructions'], '旧描述');
    rebuild(() =>
        config = {...config, 'model': 'tts-1', 'instructionsEnabled': 'true'});
    await tester.pump();
    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isFalse);
    expect(toggle.onChanged, isNull);
    rebuild(() => config = {...config, 'model': 'custom-tts'});
    await tester.pump();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    expect(config['instructions'], '旧描述');
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow layout and externally restored description remain usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);
    rebuild(() => config = {...config, 'instructions': '导入的提示词'});
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('openai-description')))
            .controller!
            .text,
        '导入的提示词');
    expect(tester.takeException(), isNull);
  });
}
