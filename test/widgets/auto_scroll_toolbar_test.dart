import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/service/reader_auto_scroll.dart';
import 'package:modu_reader/service/reader_toolbar_visibility.dart';
import 'package:modu_reader/widgets/reading_page/auto_scroll_toolbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ReaderAutoScroll controller;
  late ReaderToolbarVisibility visibility;
  late int starts, stops, closes, bodyTaps;
  Finder key(String name) => find.byKey(ValueKey('auto-scroll-$name'));

  setUpAll(() async => L10n.delegate.load(const Locale('en')));
  setUp(() async {
    SharedPreferences.setMockInitialValues({'readerMenuOpacityPercent': 60});
    await Prefs().initPrefs();
    starts = stops = closes = bodyTaps = 0;
    controller = ReaderAutoScroll(
      startReader: (_) async {
        starts++;
        return true;
      },
      stopReader: () => stops++,
    );
    visibility = ReaderToolbarVisibility();
  });
  tearDown(() {
    controller.dispose();
    visibility.dispose();
  });

  Future<void> mount(WidgetTester tester,
      {double scale = 1, ValueChanged<bool>? onEditingChanged}) async {
    visibility.setEnabled(true);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: Stack(children: [
        Positioned.fill(
            child: GestureDetector(
                onTap: () => bodyTaps++,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(key: ValueKey('reader-viewport')))),
        Positioned.fill(
            child: AutoScrollToolbar(
                controller: controller,
                visibility: visibility,
                onEditingChanged: onEditingChanged,
                onStart: () => unawaited(controller.start()),
                onClose: () {
                  closes++;
                  controller.stop();
                  visibility.setEnabled(false);
                })),
      ])),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    visibility.setEnabled(false);
    await tester.pumpWidget(const SizedBox());
  }

  for (final scale in [1.0, 2.5]) {
    testWidgets('fits 390 pixels with 44 pixel controls at scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await mount(tester, scale: scale);
      expect(find.text('1.0×'), findsOneWidget);
      expect(tester.getSize(key('toolbar')), const Size(340, 44));
      for (final name in ['play-pause', 'decrease', 'increase', 'close']) {
        expect(tester.getSize(key(name)), const Size(44, 44));
        expect(key(name).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

  testWidgets('play and pause control scrolling; close disables the toolbar',
      (tester) async {
    await mount(tester);
    await tester.tap(key('play-pause'));
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(controller.running, isTrue);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    await tester.tap(key('play-pause'));
    await tester.pumpAndSettle();
    expect(stops, 1);
    expect(controller.active, isFalse);
    await tester.tap(key('play-pause'));
    await tester.pumpAndSettle();
    await tester.tap(key('close'));
    await tester.pumpAndSettle();
    expect(closes, 1);
    expect(stops, 2);
    expect(visibility.enabled, isFalse);
    expect(key('toolbar'), findsNothing);
    await unmount(tester);
  });

  testWidgets('step buttons change tenths and disable at either bound',
      (tester) async {
    await mount(tester);
    await tester.tap(key('increase'));
    await tester.pump();
    expect(controller.speed, 1.1);
    expect(find.text('1.1×'), findsOneWidget);
    await tester.tap(key('decrease'));
    await tester.pump();
    expect(controller.speed, 1);
    controller.setSpeed(.1);
    await tester.pump();
    expect(tester.widget<IconButton>(key('decrease')).onPressed, isNull);
    expect(tester.widget<IconButton>(key('increase')).onPressed, isNotNull);
    controller.setSpeed(4);
    await tester.pump();
    expect(tester.widget<IconButton>(key('increase')).onPressed, isNull);
    expect(tester.widget<IconButton>(key('decrease')).onPressed, isNotNull);
    await unmount(tester);
  });

  testWidgets('manual speed validates input and holds visibility while editing',
      (tester) async {
    await mount(tester);
    await tester.tap(key('speed'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(visibility.visible, isTrue);
    final input = key('speed-input');
    for (final invalid in ['wrong', 'NaN', 'Infinity', '0', '4.1']) {
      await tester.enterText(input, invalid);
      await tester.tap(find.text('OK'));
      await tester.pump();
      expect(find.text('Enter 0.1–4.0'), findsOneWidget);
      expect(controller.speed, 1);
    }
    await tester.enterText(input, ' 1,26 ');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(controller.speed, 1.3);
    expect(find.text('1.3×'), findsOneWidget);
    await tester.pump(ReaderToolbarVisibility.hideDelay);
    expect(key('toolbar'), findsNothing);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('canceling manual speed leaves the current multiplier',
      (tester) async {
    await mount(tester);
    await tester.tap(key('speed'));
    await tester.pumpAndSettle();
    await tester.enterText(key('speed-input'), '2.4');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.speed, 1);
    expect(find.text('1.0×'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final confirm in [false, true]) {
    testWidgets(
        '${confirm ? 'confirming' : 'canceling'} reports editing until the route is removed',
        (tester) async {
      final changes = <bool>[];
      final speedsAfterEditing = <double>[];
      var resume = false;
      await controller.start();
      await mount(tester, onEditingChanged: (editing) {
        changes.add(editing);
        if (editing) {
          resume = controller.running;
          controller.stop();
        } else {
          expect(key('speed-input'), findsNothing);
          speedsAfterEditing.add(controller.speed);
          if (resume) unawaited(controller.start());
        }
      });
      expect(controller.running, isTrue);
      await tester.tap(key('speed'));
      await tester.pumpAndSettle();
      expect(changes, [true]);
      expect(controller.active, isFalse);
      await tester.enterText(key('speed-input'), '2.4');
      final input = tester.widget<TextField>(key('speed-input')).controller!;
      await tester.tap(find.text(confirm ? 'OK' : 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(changes, [true]);
      expect(controller.active, isFalse);
      expect(key('speed-input'), findsOneWidget);
      void listener() {}
      input.addListener(listener);
      input.removeListener(listener);
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(changes, [true, false]);
      expect(controller.running, isTrue);
      expect(speedsAfterEditing, [confirm ? 2.4 : 1]);
      await tester.pump(const Duration(seconds: 1));
      expect(changes, [true, false]);
      expect(starts, 2);
      expect(stops, 1);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

  testWidgets('pending start cannot be submitted twice', (tester) async {
    final pending = Completer<bool>();
    controller.dispose();
    controller = ReaderAutoScroll(
      startReader: (_) {
        starts++;
        return pending.future;
      },
      stopReader: () => stops++,
    );
    await mount(tester);
    await tester.tap(key('play-pause'));
    await tester.pump();
    expect(controller.active, isTrue);
    expect(tester.widget<IconButton>(key('play-pause')).onPressed, isNull);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(controller.running, isTrue);
    await unmount(tester);
  });

  testWidgets('automatic hiding preserves scrolling and allows book taps',
      (tester) async {
    await mount(tester);
    await controller.start();
    await tester.pump();
    final viewport =
        tester.getRect(find.byKey(const ValueKey('reader-viewport')));
    final bar = tester.getRect(key('toolbar'));
    await tester.pump(ReaderToolbarVisibility.hideDelay);
    expect(key('toolbar'), findsNothing);
    expect(controller.running, isTrue);
    expect(stops, 0);
    await tester.tapAt(bar.center);
    expect(bodyTaps, 1);
    visibility.reveal();
    await tester.pump();
    expect(tester.getRect(key('toolbar')), bar);
    expect(tester.getRect(find.byKey(const ValueKey('reader-viewport'))),
        viewport);
    await unmount(tester);
  });

  testWidgets('dragging keeps the bar visible and does not invoke controls',
      (tester) async {
    await mount(tester);
    final before = tester.getRect(key('toolbar'));
    final drag =
        await tester.startGesture(before.topLeft + const Offset(12, 22));
    await drag.moveBy(const Offset(60, -120));
    await tester.pump(const Duration(seconds: 10));
    expect(key('toolbar'), findsOneWidget);
    await drag.up();
    await tester.pump();
    final moved = tester.getRect(key('toolbar'));
    expect(moved.left, greaterThan(before.left));
    expect(moved.top, lessThan(before.top));
    expect(starts, 0);
    expect(closes, 0);
    await tester.tapAt(before.center);
    expect(bodyTaps, 1);
    await tester.pump(ReaderToolbarVisibility.hideDelay);
    expect(key('toolbar'), findsNothing);
    await unmount(tester);
  });

  testWidgets('floating background remains translucent with opaque controls',
      (tester) async {
    await mount(tester);
    final material = tester.widget<Material>(key('toolbar'));
    expect(material.color!.a, closeTo(.2, .005));
    expect(tester.widget<IconButton>(key('play-pause')).color!.a, 1);
    expect(tester.widget<IconButton>(key('close')).color!.a, 1);
    await unmount(tester);
  });
}
