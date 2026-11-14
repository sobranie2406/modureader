import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/reader_auto_scroll.dart';
import 'package:modu_reader/service/reader_toolbar_visibility.dart';
import 'package:modu_reader/widgets/reading_page/auto_scroll_toolbar.dart';
import 'package:modu_reader/widgets/reading_page/document_comparison_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'full reader toolbar stays usable beside a 20 percent reflow pane',
      (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    var starts = 0, stops = 0;
    final controller = ReaderAutoScroll(
        startReader: (_) async {
          starts++;
          return true;
        },
        stopReader: () => stops++);
    final visibility = ReaderToolbarVisibility()..setEnabled(true);
    addTearDown(controller.dispose);
    addTearDown(visibility.dispose);
    const original = ValueKey('comparison-original');
    const reflow = ValueKey('comparison-reflow');
    Finder control(String name) => find.byKey(ValueKey('auto-scroll-$name'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Stack(children: [
      Positioned.fill(
          child: DocumentComparisonView(
              compare: true,
              original: const SizedBox.expand(key: original),
              reflow: const SizedBox.expand(key: reflow),
              onOriginalInteraction: () {},
              onReflowInteraction: () {})),
      Positioned.fill(
          child: AutoScrollToolbar(
              controller: controller,
              visibility: visibility,
              onStart: () => unawaited(controller.start()),
              onClose: () {
                controller.stop();
                visibility.setEnabled(false);
              })),
    ]))));
    await tester.pump();
    await tester.drag(find.byKey(const ValueKey('document-comparison-divider')),
        const Offset(1000, 0));
    await tester.pump();
    final reflowRect = tester.getRect(find.byKey(reflow));
    expect(reflowRect.width, closeTo((800 - 24) * .2, .01));
    final toolbarRect = tester.getRect(control('toolbar'));
    expect(toolbarRect.width, 340);
    for (final name in ['play-pause', 'decrease', 'increase', 'close']) {
      expect(tester.getSize(control(name)), const Size(44, 44));
      expect(control(name).hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.tap(control('play-pause'));
    await tester.pump();
    expect(controller.running, isTrue);
    expect(starts, 1);
    expect(tester.getRect(find.byKey(reflow)), reflowRect);
    await tester.tap(control('increase'));
    await tester.pump();
    expect(controller.speed, 1.1);
    expect(controller.running, isTrue);
    expect(tester.getRect(control('toolbar')), toolbarRect);
    await tester.pump(ReaderToolbarVisibility.hideDelay);
    expect(control('toolbar'), findsNothing);
    expect(controller.running, isTrue);
    visibility.reveal();
    await tester.pump();
    expect(tester.getRect(control('toolbar')), toolbarRect);
    await tester.tap(control('close'));
    await tester.pump();
    expect(controller.running, isFalse);
    expect(stops, 1);
    expect(control('toolbar'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(ReaderToolbarVisibility.hideDelay);
    expect(tester.takeException(), isNull);
  });
}
