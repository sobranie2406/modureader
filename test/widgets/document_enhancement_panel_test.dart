import 'dart:async';
import 'package:anx_reader/models/document_enhancement.dart';
import 'package:anx_reader/models/pdf_reading_view.dart';
import 'package:anx_reader/widgets/reading_page/document_enhancement_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'pdf_region_preview_test.dart' as fixture;

Future<void> open(WidgetTester tester,
    {required Future<void> Function(DocumentEnhancement) save,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>)? render,
    bool settle = true}) async {
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  child: const Text('Open'),
                  onPressed: () => showDialog<DocumentEnhancement>(
                      context: context,
                      builder: (_) => DocumentEnhancementPanel(
                          initial: const DocumentEnhancement(),
                          cancelRender: () {},
                          render:
                              render ?? (_) async => {'dataUrl': fixture.pixel},
                          save: save)))))));
  await tester.tap(find.text('Open'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void change(WidgetTester tester, String key, double value) => tester
    .widget<Slider>(find.byKey(ValueKey('enhancement-$key')))
    .onChanged!(value);
void main() {
  test('settings round trip, defaults and bounds are strict', () {
    const value = DocumentEnhancement(
        ink: 15, contrast: -30, darken: 60, whiten: 170, sharpen: 40);
    final view =
        PdfReadingView.fromJson(PdfReadingView(enhancement: value).toJson());
    expect(view.enhancement.toJson(), value.toJson());
    expect(
        PdfReadingView.fromJson(const PdfReadingView().toJson())
            .enhancement
            .enabled,
        false);
    for (final entry in DocumentEnhancement.limits.entries) {
      expect(
          () => DocumentEnhancement.fromJson({entry.key: entry.value.$2 + 1}),
          throwsFormatException);
    }
  });
  testWidgets(
      'editing previews without saving, compare keeps draft, confirmation saves',
      (tester) async {
    final requests = <Map<String, dynamic>>[], saved = <DocumentEnhancement>[];
    await open(tester,
        save: (value) async => saved.add(value),
        render: (request) async {
          requests.add(request);
          return {'dataUrl': fixture.pixel};
        });
    change(tester, 'ink', 8);
    change(tester, 'contrast', 20);
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(requests.last['enhancement']['ink'], 8);
    await tester.tap(find.text('Compare original'));
    await tester.pumpAndSettle();
    expect(requests.last['enhancement']['ink'], 0);
    await tester.tap(find.text('Show enhanced'));
    await tester.pumpAndSettle();
    expect(requests.last['enhancement']['ink'], 8);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(saved.single.ink, 8);
    expect(saved.single.contrast, 20);
    expect(find.text('Open'), findsOneWidget);
  });
  testWidgets('cancel never saves and late render is ignored', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    var saves = 0;
    await open(tester, save: (_) async {
      saves++;
    });
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    await open(tester,
        save: (_) async {
          saves++;
        },
        render: (_) => pending.future,
        settle: false);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    pending.complete({'dataUrl': fixture.pixel});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(saves, 0);
  });
  testWidgets(
      'failed save keeps controls and permits retry; small screens do not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0;
    await open(tester, save: (_) async {
      if (++attempts == 1) throw StateError('injected');
    });
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Preview or save failed. Retry'), findsOneWidget);
    await tester.tap(find.text('Preview or save failed. Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
}
