import 'package:anx_reader/widgets/reading_page/reading_battery_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final level in [0, 9, 80, 100]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('compact battery $level at text scale $scale',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    ReadingBatteryIndicator(level: level, color: Colors.black),
                    const SizedBox(width: 5),
                    const Text('22:20',
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(fontSize: 10, height: 1.2)),
                  ]),
                  const Text('正文',
                      key: ValueKey('body'), style: TextStyle(fontSize: 36)),
                ],
              ),
            ),
          ),
        ));
        final battery = find.byType(ReadingBatteryIndicator);
        expect(tester.getSize(battery), const Size(22, 10));
        expect(tester.getSize(find.byType(Row)).height, lessThanOrEqualTo(14));
        expect(
            tester.getRect(battery).bottom,
            lessThanOrEqualTo(
                tester.getRect(find.byKey(const ValueKey('body'))).top));
        expect(find.text('$level'), findsOneWidget);
        expect(tester.widget<Text>(find.text('$level')).textScaler,
            TextScaler.noScaling);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'extreme metadata sizes stay bounded and percentage remains accessible',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      for (final size in [0.0, 8.0, 16.0, 40.0, double.nan]) {
        await tester.pumpWidget(MaterialApp(
            home: Center(
          child: ReadingBatteryIndicator(
              level: 100, color: Colors.white, fontSize: size),
        )));
        final bounds = tester.getSize(find.byType(ReadingBatteryIndicator));
        expect(bounds.height, inInclusiveRange(8, 16));
        expect(find.bySemanticsLabel('100%'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    } finally {
      semantics.dispose();
    }
  });
}
