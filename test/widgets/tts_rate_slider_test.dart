import 'package:anx_reader/widgets/reading_page/tts_rate_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mimo in [false, true]) {
    testWidgets('fine steps below 2x, then only 3x and 4x: MiMo=$mimo',
        (tester) async {
      var rate = 1.0;
      final previews = <double>[];
      final commits = <double>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
          return TtsRateSlider(
            rate: rate,
            isMimo: mimo,
            onChanged: (value) {
              previews.add(value);
              setState(() => rate = value);
            },
            onChangeEnd: commits.add,
          );
        })),
      ));
      Slider slider() => tester.widget<Slider>(find.byType(Slider));
      final last = slider().divisions!;
      for (final index in [last - 2, last - 1, last]) {
        slider().onChanged!(index.toDouble());
        await tester.pump();
        slider().onChangeEnd!(index.toDouble());
        expect(slider().value, index.toDouble());
      }
      expect(previews, [2.0, 3.0, 4.0]);
      expect(commits, [2.0, 3.0, 4.0]);
      expect(slider().label, '4.0×');
      expect(slider().max - (last - 2), 2); // Only two high-speed intervals.
      slider().onChanged!((last - 3).toDouble());
      await tester.pump();
      expect(rate, mimo ? 1.9 : 1.8);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('drag previews without committing; releasing at the end saves 4x',
      (tester) async {
    var rate = 1.0;
    final commits = <double>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: Center(child: StatefulBuilder(builder: (context, setState) {
      return SizedBox(
        width: 360,
        child: TtsRateSlider(
          rate: rate,
          isMimo: true,
          onChanged: (value) => setState(() => rate = value),
          onChangeEnd: commits.add,
        ),
      );
    })))));
    final rect = tester.getRect(find.byType(Slider));
    final gesture =
        await tester.startGesture(Offset(rect.left + 100, rect.center.dy));
    await gesture.moveTo(Offset(rect.right, rect.center.dy));
    await tester.pump();
    expect(rate, 4.0);
    expect(commits, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(commits, [4.0]);
  });

  testWidgets('saved 3x and 4x reopen at their correct index', (tester) async {
    for (final rate in [3.0, 4.0]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TtsRateSlider(
        rate: rate,
        isMimo: true,
        onChanged: (_) {},
        onChangeEnd: (_) {},
      ))));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, rate == 3 ? slider.max - 1 : slider.max);
      expect(slider.label, '${rate.toStringAsFixed(1)}×');
    }
  });

  testWidgets('legacy fractional rates survive until the user changes them',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TtsRateSlider(
      rate: 0.7,
      onChanged: (_) => fail('must not silently rewrite saved speed'),
      onChangeEnd: (_) => fail('must not silently rewrite saved speed'),
    ))));
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, closeTo(3.5, 0.00001));
    expect(slider.label, '0.7×');
  });

  testWidgets('system speech retains its original rate range', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TtsRateSlider(
      rate: 0.6,
      isOnline: false,
      onChanged: (_) {},
      onChangeEnd: (_) {},
    ))));
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.max, 10);
    expect(slider.label, '0.6');
  });

  testWidgets('invalid or out-of-range saved rates cannot break the slider',
      (tester) async {
    for (final rate in [double.nan, double.infinity, -1.0, 9.0]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TtsRateSlider(
        rate: rate,
        isMimo: true,
        onChanged: (_) {},
        onChangeEnd: (_) {},
      ))));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, inInclusiveRange(slider.min, slider.max));
      expect(tester.takeException(), isNull);
    }
  });
}
