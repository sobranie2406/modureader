import 'dart:async';
import 'package:anx_reader/models/document_enhancement.dart';
import 'package:anx_reader/models/pdf_reading_view.dart';
import 'package:anx_reader/widgets/reading_page/document_enhancement_panel.dart';
import 'package:anx_reader/widgets/reading_page/document_panel_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'pdf_region_preview_test.dart' as fixture;

Future<void> open(WidgetTester tester,
    {required Future<void> Function(DocumentEnhancement) save,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>)? render,
    bool bottomPanel = false,
    bool settle = true}) async {
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  child: const Text('Open'),
                  onPressed: () => showDialog<DocumentEnhancement>(
                      context: context,
                      builder: (_) => DocumentEnhancementPanel(
                          bottomPanel: bottomPanel,
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
  testWidgets('every row previews, increments, decrements, resets and saves',
      (tester) async {
    final requests = <Map<String, dynamic>>[], saved = <DocumentEnhancement>[];
    await open(tester,
        bottomPanel: true,
        save: (v) async => saved.add(v),
        render: (request) async {
          requests.add(request);
          return {'dataUrl': fixture.pixel};
        });
    for (final key in DocumentEnhancement.limits.keys) {
      final slider = find.byKey(ValueKey('enhancement-$key'));
      await tester.scrollUntilVisible(slider, 80,
          scrollable: find.descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable)));
      final row =
          find.ancestor(of: slider, matching: find.byType(DocumentControlRow));
      change(tester, key, 5);
      await tester.pumpAndSettle();
      expect(requests.last['enhancement'][key], 5);
      await tester
          .tap(find.descendant(of: row, matching: find.byTooltip('Increase')));
      await tester.pumpAndSettle();
      expect(requests.last['enhancement'][key], 6);
      await tester
          .tap(find.descendant(of: row, matching: find.byTooltip('Decrease')));
      await tester.pumpAndSettle();
      expect(requests.last['enhancement'][key], 5);
      final resetIcon =
          find.descendant(of: row, matching: find.byIcon(Icons.restart_alt));
      await tester.tap(resetIcon.evaluate().isNotEmpty
          ? resetIcon
          : find.descendant(of: row, matching: find.byType(OutlinedButton)));
      await tester.pumpAndSettle();
      expect(requests.last['enhancement'][key], 0);
      change(tester, key, 7);
      await tester.pumpAndSettle();
    }
    expect(saved, isEmpty);
    expect(requests.last['enhancement'].values, everyElement(7));
    await tester.tap(find.text('Reset all'));
    await tester.pumpAndSettle();
    expect(requests.last['enhancement'].values, everyElement(0));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(saved.single.enabled, false);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 740),
    const Size(844, 390),
    const Size(1024, 1366),
    const Size(1440, 900),
  ]) {
    testWidgets('bottom enhancement keeps page visible at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = <DocumentEnhancement>[];
      await open(tester, bottomPanel: true, save: (v) async => saved.add(v));
      final material = find
          .descendant(of: find.byType(Dialog), matching: find.byType(Material))
          .first;
      expect(tester.getTopLeft(material).dy, greaterThan(0));
      final previewSize =
          tester.getSize(find.byKey(const ValueKey('enhancement-preview')));
      expect(previewSize.height,
          greaterThanOrEqualTo(size.height < 480 ? 72 : size.height * .20));
      expect(previewSize.width, lessThanOrEqualTo(size.width));
      change(tester, 'ink', 3);
      await tester.pumpAndSettle();
      for (final key in DocumentEnhancement.limits.keys) {
        final slider = find.byKey(ValueKey('enhancement-$key'));
        await tester.scrollUntilVisible(slider, 80,
            scrollable: find.descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable)));
        expect(slider, findsOneWidget);
      }
      await tester.tap(find.byTooltip('Back to layout'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);
      expect(find.byType(DocumentEnhancementPanel), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  test('settings round trip, defaults and bounds are strict', () {
    expect(DocumentEnhancement.fromJson({'ink': 4, 'whiten': 50}).watermark, 0);
    const value = DocumentEnhancement(
        ink: 15,
        contrast: -30,
        darken: 60,
        whiten: 170,
        sharpen: 40,
        watermark: 65);
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
      'scan watermark slider saves strength and compare/reset preserves source',
      (tester) async {
    final requests = <Map<String, dynamic>>[], saved = <DocumentEnhancement>[];
    await open(tester,
        save: (v) async => saved.add(v),
        render: (r) async {
          requests.add(r);
          return {'dataUrl': fixture.pixel};
        });
    final slider = find.byKey(const ValueKey('enhancement-watermark'));
    await tester.scrollUntilVisible(slider, 80,
        scrollable: find.descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable)));
    expect(find.text('Scan watermark fading'), findsOneWidget);
    change(tester, 'watermark', 70);
    await tester.pumpAndSettle();
    expect(requests.last['enhancement']['watermark'], 70);
    await tester.tap(find.text('Compare original'));
    await tester.pumpAndSettle();
    expect(requests.last['enhancement']['watermark'], 0);
    await tester.tap(find.text('Show enhanced'));
    await tester.pumpAndSettle();
    expect(requests.last['enhancement']['watermark'], 70);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(saved.single.watermark, 70);
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
    final zoom = tester.widget<InteractiveViewer>(
        find.byKey(const ValueKey('enhancement-preview-zoom')));
    expect(zoom.maxScale, 4);
    zoom.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
    await tester.pump();
    await tester.tap(find.text('Compare original'));
    await tester.pumpAndSettle();
    expect(requests.last['enhancement']['ink'], 0);
    expect(zoom.transformationController!.value.getMaxScaleOnAxis(), 2);
    await tester.tap(find.text('Show enhanced'));
    await tester.pumpAndSettle();
    expect(requests.last['enhancement']['ink'], 8);
    expect(zoom.transformationController!.value.getMaxScaleOnAxis(), 2);
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
