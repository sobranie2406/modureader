import 'package:anx_reader/service/ocr/document_text_style.dart';
import 'package:anx_reader/service/book_player/pdf_reading_state_store.dart';
import 'package:anx_reader/widgets/reading_page/document_text_style_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
    final invalid = DocumentTextStyle.fromJson(
        {'size': 999, 'height': double.nan, 'weight': -3});
    expect(invalid.size, 40);
    expect(invalid.height, 1.6);
    expect(invalid.weight, .5);
  });

  for (final size in [
    const Size(320, 740),
    const Size(844, 390),
    const Size(1440, 900)
  ]) {
    testWidgets('style preview/save/cancel/reset at $size', (tester) async {
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
        'margin': 30.0
      }.entries) {
        tester
            .widget<Slider>(find.byKey(ValueKey('ocr-style-${change.key}')))
            .onChanged!(change.value);
        await tester.pumpAndSettle();
      }
      final preview =
          tester.widget<Text>(find.byKey(const ValueKey('ocr-style-preview')));
      expect(preview.style!.fontSize, 28);
      expect(preview.style!.height, 2);
      expect(preview.style!.fontWeight, FontWeight.w700);
      expect(saved, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      tester
          .widget<Slider>(find.byKey(const ValueKey('ocr-style-size')))
          .onChanged!(32);
      await tester.pump();
      await tester.tap(find.text('Restore defaults'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(saved.single.toJson(), const DocumentTextStyle().toJson());
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
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Could not save. Please retry.'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });
}
