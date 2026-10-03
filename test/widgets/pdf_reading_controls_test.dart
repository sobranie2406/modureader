import 'dart:async';
import 'package:anx_reader/models/pdf_reading_view.dart';
import 'package:anx_reader/models/document_display_options.dart';
import 'package:anx_reader/widgets/reading_page/pdf_reading_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'document display options round trip, defaults and mutually exclusive gestures',
      () {
    expect(
        PdfReadingView.fromJson({'zoom': 1, 'fit': 'screen', 'rotation': 0})
            .display
            .autoSeconds,
        0);
    const display = DocumentDisplayOptions(
        border: true, autoSeconds: 30, swipe: 'vertical', swipeMenu: true);
    final view = PdfReadingView.fromJson(
        const PdfReadingView(display: display).toJson());
    expect(view.display.border, isTrue);
    expect(view.display.swipeMenu, isFalse);
    for (final bad in [1, -1, 601, double.nan]) {
      expect(() => DocumentDisplayOptions.fromJson({'autoSeconds': bad}),
          throwsFormatException);
    }
    expect(() => DocumentDisplayOptions.fromJson({'border': 'yes'}),
        throwsFormatException);
  });
  testWidgets(
      'more controls save display options and hide unavailable watermark action',
      (tester) async {
    final saved = <PdfReadingView>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: PdfReadingControls(
                    initial: const PdfReadingView(),
                    save: (v) async => saved.add(v),
                    pan: (_, __) async {})))));
    await tester.ensureVisible(find.text('More original-page settings'));
    await tester.tap(find.text('More original-page settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Page border'));
    await tester.tap(find.text('Page border'));
    await tester.pumpAndSettle();
    expect(saved.last.display.border, isTrue);
    expect(
        find.text('Hide named watermark layers (display only)'), findsNothing);
    await tester.ensureVisible(find.text('Automatic page turning'));
    await tester.tap(find.text('Automatic page turning'));
    await tester.pumpAndSettle();
    expect(saved.last.display.autoSeconds, 30);
    expect(tester.takeException(), isNull);
  });
  testWidgets('zoom, fit, rotation, pan and reset operate at mobile width',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final saved = <PdfReadingView>[];
    final pans = <Offset>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: PdfReadingControls(
                    initial: const PdfReadingView(),
                    save: (value) async => saved.add(value),
                    pan: (x, y) async => pans.add(Offset(x, y)))))));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(saved.last.zoom, 1.25);
    await tester.tap(find.text('Fit width'));
    await tester.pumpAndSettle();
    expect(saved.last.fit, 'width');
    expect(saved.last.zoom, 1);
    await tester.tap(find.byTooltip('Rotate left'));
    await tester.pumpAndSettle();
    expect(saved.last.rotation, 270);
    await tester.tap(find.byTooltip('Move down'));
    await tester.pumpAndSettle();
    expect(pans, [const Offset(0, 160)]);
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(15);
    slider.onChangeEnd!(15);
    await tester.pumpAndSettle();
    expect(saved.last.zoom, 15);
    expect(find.text('1500%'), findsOneWidget);
    await tester.tap(find.text('Reset view'));
    await tester.pumpAndSettle();
    expect(saved.last.toJson(), const PdfReadingView().toJson());
    await tester.tap(find.text('Continuous scroll'));
    await tester.pumpAndSettle();
    expect(saved.last.mode, 'scroll');
    await tester.tap(find.text('Reset view'));
    await tester.pumpAndSettle();
    expect(saved.last.mode, 'scroll');
    await tester.tap(find.text('Single page'));
    await tester.pumpAndSettle();
    expect(saved.last.mode, 'single');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'failed writes restore displayed settings and pending writes disable controls',
      (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PdfReadingControls(
                initial: const PdfReadingView(),
                save: (_) => pending.future,
                pan: (_, __) async {}))));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    pending.completeError(StateError('injected'));
    await tester.pumpAndSettle();
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Could not apply. Please retry.'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
