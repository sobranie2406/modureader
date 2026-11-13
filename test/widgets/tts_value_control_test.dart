import 'package:modu_reader/widgets/reading_page/tts_value_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:flutter_test/flutter_test.dart';

const input = ValueKey('tts-rate-input');
const increase = ValueKey('tts-rate-increase');
const decrease = ValueKey('tts-rate-decrease');

Future<void> showControl(WidgetTester tester, List<double> commits,
    {double initial = 0.8, double width = 280, double scale = 1}) async {
  var rate = initial;
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
        body: Center(child: StatefulBuilder(builder: (context, setState) {
      return MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: SizedBox(
            width: width,
            child: TtsValueControl(
              value: rate,
              onChanged: (value) {
                commits.add(value);
                setState(() => rate = value);
              },
            )),
      );
    }))),
  ));
  await tester.pumpAndSettle();
}

String value(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(input)).controller!.text;

void main() {
  setUpAll(() async => L10n.delegate.load(const Locale('en')));
  testWidgets('every tenth from 0.1 to 4.0 is reachable without floating drift',
      (tester) async {
    final commits = <double>[];
    await showControl(tester, commits, initial: 0.1);
    expect(tester.widget<IconButton>(find.byKey(decrease)).onPressed, isNull);
    for (var tick = 2; tick <= 40; tick++) {
      await tester.tap(find.byKey(increase));
      await tester.pump();
      expect(commits.last, tick / 10);
      expect(value(tester), (tick / 10).toStringAsFixed(1));
    }
    expect(commits.length, 39);
    expect(
        tester.getSize(find.byKey(const ValueKey('tts-rate-control'))).height,
        48);
    expect(tester.getSize(find.byKey(const ValueKey('tts-rate-border'))).height,
        28);
    expect(tester.widget<TextField>(find.byKey(input)).textAlign,
        TextAlign.center);
    expect(tester.widget<IconButton>(find.byKey(increase)).onPressed, isNull);
    await tester.tap(find.byKey(decrease));
    await tester.pump();
    expect(commits.last, 3.9);
  });

  testWidgets('typing waits for confirmation and submit plus blur commits once',
      (tester) async {
    final commits = <double>[];
    await showControl(tester, commits);
    for (final text in ['2', '2.', '2.3']) {
      await tester.enterText(find.byKey(input), text);
      await tester.pump();
      expect(commits, isEmpty);
    }
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(commits, [2.3]);
    expect(value(tester), '2.3');
    await tester.enterText(find.byKey(input), '2.3');
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(commits, [2.3]);
  });

  testWidgets(
      'buttons apply a draft once and outside tap confirms rounded input',
      (tester) async {
    final commits = <double>[];
    await showControl(tester, commits);
    await tester.enterText(find.byKey(input), '1.2');
    await tester.tap(find.byKey(increase));
    await tester.pump();
    expect(commits, [1.3]);
    await tester.enterText(find.byKey(input), '0,84');
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(commits, [1.3, 0.8]);
    expect(value(tester), '0.8');
  });

  testWidgets('invalid input keeps the saved speed and can be corrected',
      (tester) async {
    final commits = <double>[];
    await showControl(tester, commits);
    for (final text in [
      '',
      'abc',
      'NaN',
      'Infinity',
      '0',
      '0.09',
      '-1',
      '4.1'
    ]) {
      await tester.enterText(find.byKey(input), text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(commits, isEmpty);
      expect(find.byKey(const ValueKey('tts-rate-error')), findsOneWidget);
    }
    await tester.enterText(find.byKey(input), '4.0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(commits, [4.0]);
    expect(find.byKey(const ValueKey('tts-rate-error')), findsNothing);
  });

  testWidgets('narrow layout and large text retain input and touch targets',
      (tester) async {
    await showControl(tester, [], width: 244, scale: 2);
    expect(value(tester), '0.8');
    expect(
        tester.getSize(find.byKey(increase)).width, greaterThanOrEqualTo(48));
    expect(
        tester.getSize(find.byKey(decrease)).height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });

  for (final spec in [(280.0, 1.0), (600.0, 1.0), (280.0, 2.0)]) {
    testWidgets('pitch and speed share equal columns at $spec', (tester) async {
      var pitch = 1.0, rate = 0.6;
      final pitchChanges = <double>[], rateChanges = <double>[];
      await tester.pumpWidget(MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
              body: Center(
                  child: StatefulBuilder(
                      builder: (context, setState) => MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(textScaler: TextScaler.linear(spec.$2)),
                          child: SizedBox(
                              width: spec.$1,
                              child: TtsVoiceControls(
                                pitch: pitch,
                                rate: rate,
                                onPitchChanged: (value) {
                                  pitchChanges.add(value);
                                  setState(() => pitch = value);
                                },
                                onRateChanged: (value) {
                                  rateChanges.add(value);
                                  setState(() => rate = value);
                                },
                              ))))))));
      await tester.pumpAndSettle();
      final left = tester.getRect(find.byKey(const ValueKey('tts-pitch-half')));
      final right = tester.getRect(find.byKey(const ValueKey('tts-rate-half')));
      expect(left.width, right.width);
      expect(left.right, right.left);
      if (spec.$1 < 480 * spec.$2) {
        expect(
            tester
                .getCenter(find.byKey(const ValueKey('tts-pitch-control')))
                .dx,
            left.center.dx);
        expect(
            tester.getCenter(find.byKey(const ValueKey('tts-rate-control'))).dx,
            right.center.dx);
        expect(
            tester.getRect(find.text('Pitch')).bottom,
            lessThanOrEqualTo(tester
                .getRect(find.byKey(const ValueKey('tts-pitch-control')))
                .top));
      } else {
        expect(
            tester.getCenter(find.text('Pitch')).dy,
            tester
                .getCenter(find.byKey(const ValueKey('tts-pitch-control')))
                .dy);
      }
      expect(tester.takeException(), isNull);
      await tester.enterText(
          find.byKey(const ValueKey('tts-pitch-input')), '1.6');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(pitchChanges, [1.6]);
      expect(rateChanges, isEmpty);
      expect(value(tester), '0.6');
      await tester.enterText(
          find.byKey(const ValueKey('tts-pitch-input')), '4.0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(pitchChanges, [1.6]);
      expect(find.byKey(const ValueKey('tts-pitch-error')), findsOneWidget);
      for (final endpoint in ['0.5', '2.0']) {
        await tester.enterText(
            find.byKey(const ValueKey('tts-pitch-input')), endpoint);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(pitch, double.parse(endpoint));
        expect(
            tester
                .widget<IconButton>(find.byKey(ValueKey(endpoint == '0.5'
                    ? 'tts-pitch-decrease'
                    : 'tts-pitch-increase')))
                .onPressed,
            isNull);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets('complete numeric value and suffix fit at scale $scale',
        (tester) async {
      await showControl(tester, [], initial: 1.4, width: 300, scale: scale);
      for (final text in ['0.6', '1.4', '4.0']) {
        await tester.enterText(find.byKey(input), text);
        await tester.pump();
        final RenderEditable editable = tester
            .state<EditableTextState>(find.descendant(
                of: find.byKey(input), matching: find.byType(EditableText)))
            .renderEditable;
        final first =
            editable.getLocalRectForCaret(const TextPosition(offset: 0));
        final last =
            editable.getLocalRectForCaret(TextPosition(offset: text.length));
        expect(first.left, greaterThanOrEqualTo(0));
        expect(last.right, lessThanOrEqualTo(editable.size.width));
        final suffix = tester.getRect(find.text('×'));
        final field = tester.getRect(find.byKey(input));
        expect(suffix.left, greaterThanOrEqualTo(field.left));
        expect(suffix.right, lessThanOrEqualTo(field.right));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('saved fractional and invalid rates open safely without writes',
      (tester) async {
    for (final rate in [
      0.7,
      3.9,
      4.0,
      0.0,
      double.nan,
      double.infinity,
      -1.0,
      9.0
    ]) {
      await tester.pumpWidget(const SizedBox());
      final commits = <double>[];
      await showControl(tester, commits, initial: rate);
      final displayed = double.parse(value(tester));
      expect(displayed, inInclusiveRange(0.1, 4.0));
      if (rate >= 0.1 && rate <= 4) expect(displayed, rate);
      expect(commits, isEmpty);
      expect(tester.takeException(), isNull);
    }
  });
}
