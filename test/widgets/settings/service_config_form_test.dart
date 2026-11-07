import 'package:anx_reader/service/config/config_item.dart';
import 'package:anx_reader/widgets/settings/service_config_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, dynamic> config;
  late StateSetter rebuild;
  late List<ConfigItem> items;
  setUp(() {
    config = {'model': 'qwen3-tts', 'key': 'test-key', 'count': 12};
    items = [
      ConfigItem(key: 'model', label: 'Model', type: ConfigItemType.text),
      ConfigItem(key: 'key', label: 'Key', type: ConfigItemType.password),
      ConfigItem(key: 'count', label: 'Count', type: ConfigItemType.number),
    ];
  });
  Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label);
  TextEditingController controller(WidgetTester tester, String label) =>
      tester.widget<TextField>(field(label)).controller!;
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
        rebuild = setState;
        return ServiceConfigForm(
          configItems: items,
          initialConfig: config,
          onConfigChanged: (value) => setState(() => config = Map.from(value)),
        );
      })),
    ));
  }

  for (final type in ConfigItemType.values) {
    testWidgets('$type guidance is hidden until help is opened',
        (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const hint = 'Choose the setting for your service.';
      items = [
        ConfigItem(
          key: 'setting',
          label: 'Setting',
          type: type,
          description: hint,
          defaultValue: switch (type) {
            ConfigItemType.tip => hint,
            ConfigItemType.range => 2.0,
            ConfigItemType.toggle || ConfigItemType.checkbox => false,
            _ => 'one'
          },
          min: 1,
          max: 3,
          step: 1,
          options: [
            {'value': 'one', 'label': 'One'},
            {'value': 'two', 'label': 'Two'}
          ],
        )
      ];
      await open(tester);
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);
      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text(hint), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final label in ['Model', 'Key', 'Count']) {
    testWidgets('$label preserves mid-text selection after parent draft echo',
        (tester) async {
      await open(tester);
      final original = controller(tester, label);
      await tester.showKeyboard(field(label));
      final value = TextEditingValue(
        text: '1${original.text}',
        selection: const TextSelection.collapsed(offset: 1),
      );
      tester.testTextInput.updateEditingValue(value);
      await tester.pump();
      expect(controller(tester, label), same(original));
      expect(original.value, value);
      rebuild(() => config = Map.from(config));
      await tester.pump();
      expect(original.value, value);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('IME composing range survives rebuild and commits only once',
      (tester) async {
    await open(tester);
    await tester.showKeyboard(field('Model'));
    const composing = TextEditingValue(
      text: 'qwen3-ttsff',
      selection: TextSelection.collapsed(offset: 11),
      composing: TextRange(start: 9, end: 11),
    );
    tester.testTextInput.updateEditingValue(composing);
    await tester.pump();
    expect(controller(tester, 'Model').value, composing);
    final committed = composing.copyWith(composing: TextRange.empty);
    tester.testTextInput.updateEditingValue(committed);
    await tester.pump();
    expect(controller(tester, 'Model').value, committed);
    expect(config['model'], 'qwen3-ttsff');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'numeric empty and leading-zero drafts are not normalized on echo',
      (tester) async {
    await open(tester);
    await tester.enterText(field('Count'), '');
    await tester.pump();
    expect(controller(tester, 'Count').text, '');
    expect(config['count'], 0);
    await tester.enterText(field('Count'), '007');
    await tester.pump();
    expect(controller(tester, 'Count').text, '007');
    expect(config['count'], 7);
  });

  testWidgets('password visibility leaves controller and selection intact',
      (tester) async {
    await open(tester);
    final original = controller(tester, 'Key');
    original.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump();
    expect(controller(tester, 'Key'), same(original));
    expect(original.selection,
        const TextSelection(baseOffset: 1, extentOffset: 3));
    expect(tester.widget<TextField>(field('Key')).obscureText, isFalse);
  });

  testWidgets('external restore and field changes update without stale text',
      (tester) async {
    await open(tester);
    rebuild(() => config = {'model': 'restored', 'key': '', 'count': 3});
    await tester.pump();
    expect(controller(tester, 'Model').text, 'restored');
    expect(controller(tester, 'Key').text, '');
    expect(controller(tester, 'Count').text, '3');
    rebuild(() => items = [
          items[2],
          items[0],
          ConfigItem(
              key: 'url',
              label: 'URL',
              type: ConfigItemType.text,
              defaultValue: 'https://example.test'),
        ]);
    await tester.pump();
    expect(controller(tester, 'Model').text, 'restored');
    expect(controller(tester, 'URL').text, 'https://example.test');
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
