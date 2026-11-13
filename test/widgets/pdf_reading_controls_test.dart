import 'dart:async';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/widgets/reading_page/reader_menu_group.dart';
import 'package:modu_reader/models/pdf_reading_view.dart';
import 'package:modu_reader/models/document_display_options.dart';
import 'package:modu_reader/widgets/reading_page/pdf_reading_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

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
                    save: (v) async => saved.add(v))))));
    expect(find.byType(ReaderMenuGroup), findsNWidgets(3));
    await tester.ensureVisible(find.text('Page turning and options'));
    await tester.tap(find.text('Page turning and options'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Page border'));
    await tester.tap(find.text('Page border'));
    await tester.pumpAndSettle();
    expect(saved.last.display.border, isTrue);
    expect(
        find.text('Hide named watermark layers (display only)'), findsNothing);
    expect(find.text('Automatic page turning'), findsNothing);
    expect(find.text('Move viewport'), findsNothing);
    expect(find.text('Swipe up for menu'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('Swipe navigation'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('fit, rotation and reset work without duplicate zoom controls',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final saved = <PdfReadingView>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: PdfReadingControls(
                    initial: const PdfReadingView(),
                    save: (value) async => saved.add(value))))));
    await tester.tap(find.text('Page fit').first);
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsNothing);
    expect(find.byTooltip('Zoom in'), findsNothing);
    await tester.tap(find.text('Fit width'));
    await tester.pumpAndSettle();
    expect(saved.last.fit, 'width');
    expect(saved.last.zoom, 1);
    await tester.ensureVisible(find.text('Rotation').first);
    await tester.tap(find.text('Rotation').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Rotate left'));
    await tester.tap(find.byTooltip('Rotate left'));
    await tester.pumpAndSettle();
    expect(saved.last.rotation, 270);
    await tester.ensureVisible(find.text('Page turning and options'));
    await tester.tap(find.text('Page turning and options'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Move down'), findsNothing);
    expect(find.byType(Slider), findsNothing);
    await tester.ensureVisible(find.text('Reset view'));
    await tester.tap(find.text('Reset view'));
    await tester.pumpAndSettle();
    expect(saved.last.toJson(), const PdfReadingView().toJson());
    await tester.ensureVisible(find.text('Continuous scroll'));
    await tester.tap(find.text('Continuous scroll'));
    await tester.pumpAndSettle();
    expect(saved.last.mode, 'scroll');
    await tester.ensureVisible(find.text('Reset view'));
    await tester.tap(find.text('Reset view'));
    await tester.pumpAndSettle();
    expect(saved.last.mode, 'scroll');
    await tester.ensureVisible(find.text('Single page'));
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
            body: SingleChildScrollView(
                child: PdfReadingControls(
                    initial: const PdfReadingView(),
                    save: (_) => pending.future)))));
    await tester.tap(find.text('Page fit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fit width'));
    await tester.pump();
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Fit width'))
            .onSelected,
        isNull);
    pending.completeError(StateError('injected'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Fit screen'))
            .selected,
        isTrue);
    expect(find.text('Could not apply. Please retry.'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Fit width'))
            .onSelected,
        isNotNull);
    expect(tester.takeException(), isNull);
  });
}
