import 'dart:async';
import 'package:modu_reader/service/battery_level.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reader shares one read across slots and repeated rebuilds',
      (tester) async {
    var reads = 0;
    final battery = ReadingBatteryLevel(loader: () async => 70 - reads++);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Widget slots() => Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
            children: List.generate(
                3,
                (_) => ValueListenableBuilder<int?>(
                    valueListenable: battery,
                    builder: (_, level, __) => Text('$level')))));
    await tester.pumpWidget(slots());
    await tester.pump();
    expect(reads, 1);
    for (var i = 0; i < 20; i++) {
      await tester.pumpWidget(slots());
    }
    expect(reads, 1);
    expect(find.text('70'), findsNWidgets(3));
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(reads, 2);
    expect(find.text('69'), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
    expect(reads, 2);
    battery.dispose();
  });

  testWidgets(
      'reader pauses battery polling in background and refreshes on resume',
      (tester) async {
    var reads = 0;
    final battery = ReadingBatteryLevel(loader: () async => ++reads);
    void listener() {}
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    battery.addListener(listener);
    await tester.pump();
    expect(reads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 3));
    expect(reads, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(reads, 2);
    battery.removeListener(listener);
    battery.dispose();
  });

  testWidgets('slow battery reads do not overlap or notify after disposal',
      (tester) async {
    final pending = Completer<int>();
    var reads = 0;
    final battery = ReadingBatteryLevel(loader: () {
      reads++;
      return pending.future;
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    battery.addListener(() => fail('disposed battery notified a listener'));
    await tester.pump(const Duration(minutes: 3));
    expect(reads, 1);
    battery.dispose();
    pending.complete(80);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('readBatteryLevelSafely', () {
    test('returns a valid battery percentage', () async {
      expect(
        await readBatteryLevelSafely(loader: () async => 73),
        73,
      );
    });

    test('returns null when the platform reports no battery', () async {
      expect(
        await readBatteryLevelSafely(
          loader: () async => throw TypeError(),
        ),
        isNull,
      );
    });

    test('rejects out-of-range platform values', () async {
      expect(
        await readBatteryLevelSafely(loader: () async => -1),
        isNull,
      );
      expect(
        await readBatteryLevelSafely(loader: () async => 101),
        isNull,
      );
    });
  });
}
