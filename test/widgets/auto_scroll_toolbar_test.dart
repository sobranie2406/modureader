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
    controller.stop();
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
      await tester.tap(key('timer'));
      await tester.pumpAndSettle();
      expect(find.text('0 (No limit)'), findsOneWidget);
      expect(find.text('120 min'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
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

  testWidgets('timer opens a zero to 120 minute slider and applies either end',
      (tester) async {
    await mount(tester);
    expect(controller.timeLimit, isNull);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    await tester.tap(key('timer'));
    await tester.pumpAndSettle();
    final slider = key('timer-slider');
    final control = tester.widget<Slider>(slider);
    expect(control.min, 0);
    expect(control.max, 120);
    expect(control.divisions, 120);
    expect(control.value, 0);
    expect(find.text('No limit'), findsOneWidget);
    expect(find.text('0 (No limit)'), findsOneWidget);
    expect(find.text('120 min'), findsOneWidget);
    await tester.drag(slider, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, 120);
    expect(find.text('120 min'), findsNWidgets(2));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(controller.timeLimit, const Duration(minutes: 120));
    expect(find.text('120:00'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);

    await tester.tap(key('timer'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, 120);
    await tester.drag(slider, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, 0);
    expect(find.text('No limit'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(controller.timeLimit, isNull);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('canceling timer edits preserves the previous limit',
      (tester) async {
    controller.setTimeLimit(const Duration(minutes: 15));
    await mount(tester);
    expect(find.text('15:00'), findsOneWidget);
    await tester.tap(key('timer'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(key('timer-slider')).value, 15);
    await tester.drag(key('timer-slider'), const Offset(2000, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.timeLimit, const Duration(minutes: 15));
    expect(find.text('15:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets('timer button follows countdown, pause and automatic stopping',
      (tester) async {
    controller.setTimeLimit(const Duration(seconds: 3));
    await mount(tester);
    expect(find.text('00:03'), findsOneWidget);
    await controller.start();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:02'), findsOneWidget);
    controller.stop();
    await tester.pump(const Duration(seconds: 10));
    visibility.reveal();
    await tester.pump();
    expect(find.text('00:02'), findsOneWidget);
    await controller.start();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:00'), findsOneWidget);
    expect(controller.active, isFalse);
    expect(stops, 2);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await controller.start();
    await tester.pump();
    expect(find.text('00:03'), findsOneWidget);
    controller.setTimeLimit(null);
    await tester.pump();
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
    expect(controller.running, isTrue);
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final width in [200.0, 280.0]) {
    testWidgets('timer fits a $width pixel comparison pane with large text',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      controller.setTimeLimit(const Duration(minutes: 120));
      await mount(tester, scale: 2.5);
      final bar = tester.getRect(key('toolbar'));
      expect(bar.height, 44);
      expect(bar.left, greaterThanOrEqualTo(0));
      expect(bar.right, lessThanOrEqualTo(width));
      expect(key('increase'), findsNothing);
      expect(key('decrease'), findsNothing);
      for (final name in ['play-pause', 'speed', 'timer', 'close']) {
        expect(key(name).hitTestable(), findsOneWidget);
        final rect = tester.getRect(key(name));
        expect(rect.width, greaterThanOrEqualTo(44));
        expect(rect.left, greaterThanOrEqualTo(bar.left));
        expect(rect.right, lessThanOrEqualTo(bar.right));
      }
      expect(find.text('120:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

  for (final confirm in [false, true]) {
    testWidgets(
        '${confirm ? 'confirming' : 'canceling'} timer edits waits for the route before resuming',
        (tester) async {
      final changes = <bool>[];
      final limitsAfterEditing = <Duration?>[];
      var resume = false;
      controller.setTimeLimit(const Duration(minutes: 15));
      await controller.start();
      await mount(tester, onEditingChanged: (editing) {
        changes.add(editing);
        if (editing) {
          resume = controller.running;
          controller.stop();
        } else {
          expect(key('timer-slider'), findsNothing);
          limitsAfterEditing.add(controller.timeLimit);
          if (resume) unawaited(controller.start());
        }
      });
      await tester.tap(key('timer'));
      await tester.pumpAndSettle();
      expect(changes, [true]);
      expect(controller.active, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(visibility.visible, isTrue);
      tester.widget<Slider>(key('timer-slider')).onChanged!(30);
      await tester.pump();
      await tester.tap(find.text(confirm ? 'OK' : 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(changes, [true]);
      expect(controller.active, isFalse);
      expect(key('timer-slider'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(changes, [true, false]);
      expect(controller.running, isTrue);
      expect(limitsAfterEditing, [Duration(minutes: confirm ? 30 : 15)]);
      await tester.pump(const Duration(seconds: 1));
      expect(changes, [true, false]);
      expect(starts, 2);
      expect(stops, 1);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  }

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
