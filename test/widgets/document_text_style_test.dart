import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/ocr/document_text_style.dart';
import 'package:modu_reader/service/book_player/pdf_reading_state_store.dart';
import 'package:modu_reader/widgets/reading_page/document_text_style_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  test('shared settings round trip and legacy controls remain compatible', () {
    final old =
        DocumentTextStyle.fromJson({'verticalMargin': 26, 'justify': false});
    expect(
        old.padding, const EdgeInsets.symmetric(horizontal: 20, vertical: 26));
    final current = DocumentTextStyle.fromJson({
      ...old.toJson(),
      'topMargin': 40,
      'bottomMargin': 80,
      'margin': 288,
      'spacing': -3,
      'textAlignment': 'center',
    });
    final restored = DocumentTextStyle.fromJson(current.toJson());
    expect(restored.padding, const EdgeInsets.fromLTRB(288, 40, 288, 80));
    expect(restored.spacing, -3);
    expect(restored.alignment, TextAlign.center);
    expect(restored.withValue('justify', true).alignment, TextAlign.justify);
    expect(restored.withValue('verticalMargin', 10).padding,
        const EdgeInsets.fromLTRB(288, 10, 288, 10));
    expect(restored.withValue('size', 28).textAlignment, 'center');
  });
  test('style round trip is book-local and does not toggle original-page mode',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = DocumentTextStyleStore(prefs);
    final style = const DocumentTextStyle(
        size: 28,
        height: 2,
        weight: 1.7,
        spacing: 2,
        margin: 30,
        verticalMargin: 26,
        paragraphSpacing: .5,
        serif: true,
        justify: true);
    await store.save('a', style);
    expect(DocumentTextStyleStore(prefs).read('a').toJson(), style.toJson());
    expect(store.read('b').toJson(), const DocumentTextStyle().toJson());
    expect(store.read('a').textStyle.fontFamily, 'SourceHanSerif');
    expect(store.read('a').textStyle.letterSpacing, 2);
    expect(store.read('a').alignment, TextAlign.justify);
    expect(PdfReadingStateStore(prefs).hasSavedMode('a'), false);
    expect(prefs.getKeys(), {DocumentTextStyleStore.key});
    final invalid = DocumentTextStyle.fromJson({
      'size': 999,
      'height': double.nan,
      'weight': -3,
      'verticalMargin': -1,
      'paragraphSpacing': 99,
      'font': '../bad.ttf'
    });
    expect(invalid.size, 40);
    expect(invalid.height, 1.6);
    expect(invalid.weight, .5);
    expect(invalid.verticalMargin, 0);
    expect(invalid.paragraphSpacing, 3);
    expect(invalid.font, '');
    final imported = style.withValue('font', '宋体.ttf');
    expect(DocumentTextStyle.fromJson(imported.toJson()).textStyle.fontFamily,
        '宋体.ttf');
    expect(style.buildTextSpan('第一段\n\n第二段').toPlainText(), '第一段\n\n第二段');
  });

  for (final size in [
    const Size(320, 740),
    const Size(844, 390),
    const Size(1440, 900)
  ]) {
    testWidgets('style auto-saves on release and reset at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = <DocumentTextStyle>[];
      await tester.pumpWidget(MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<DocumentTextStyle>(
                          context: context,
                          builder: (_) => DocumentTextStyleDialog(
                              initial: const DocumentTextStyle(),
                              save: (s) async {
                                saved.add(s);
                              })),
                      child: const Text('Open'))))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      for (final change in {
        'size': 28.0,
        'height': 2.0,
        'weight': 1.8,
        'spacing': 2.0,
        'margin': 30.0,
        'verticalMargin': 26.0,
        'paragraphSpacing': .5,
      }.entries) {
        tester
            .widget<Slider>(find.byKey(ValueKey('ocr-style-${change.key}')))
            .onChanged!(change.value);
        await tester.pumpAndSettle();
        tester
            .widget<Slider>(find.byKey(ValueKey('ocr-style-${change.key}')))
            .onChangeEnd!(change.value);
        await tester.pumpAndSettle();
      }
      final preview =
          tester.widget<Text>(find.byKey(const ValueKey('ocr-style-preview')));
      expect(preview.style!.fontSize, 28);
      expect(preview.style!.height, 2);
      expect(preview.style!.fontWeight, FontWeight.w700);
      expect(saved.length, 7);
      expect(saved.last.size, 28);
      expect(saved.last.margin, 30);
      expect(find.text('Apply'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(saved.length, 7);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      tester
          .widget<Slider>(find.byKey(const ValueKey('ocr-style-size')))
          .onChanged!(32);
      await tester.pump();
      await tester.tap(find.text('Restore defaults'));
      await tester.pumpAndSettle();
      expect(saved.last.toJson(), const DocumentTextStyle().toJson());
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed save keeps editor available for retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(MaterialApp(
        home: DocumentTextStyleDialog(
            initial: const DocumentTextStyle(),
            save: (_) async {
              attempts++;
              throw StateError('failed');
            })));
    tester
        .widget<Slider>(find.byKey(const ValueKey('ocr-style-size')))
        .onChanged!(28);
    await tester.pump();
    tester
        .widget<Slider>(find.byKey(const ValueKey('ocr-style-size')))
        .onChangeEnd!(28);
    await tester.pumpAndSettle();
    expect(find.text('Could not save. Please retry.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });
}
