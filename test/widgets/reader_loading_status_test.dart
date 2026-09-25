import 'package:anx_reader/widgets/reading_page/reader_loading_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('normal and prolonged loading stay silent without blocking input',
      (tester) async {
    var retries = 0;
    var backgroundTaps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Stack(fit: StackFit.expand, children: [
      Positioned.fill(
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => backgroundTaps++,
              child: const SizedBox.expand())),
      ReaderLoadingStatus(failed: false, onRetry: () => retries++),
    ]))));
    for (final delay in [Duration.zero, const Duration(seconds: 31)]) {
      await tester.pump(delay);
      expect(find.byType(Card), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(TextButton), findsNothing);
      expect(find.textContaining('Loading'), findsNothing);
      await tester.tapAt(const Offset(400, 300));
    }
    expect(backgroundTaps, 2);
    expect(retries, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('real font failure is distinguished and can be retried',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ReaderLoadingStatus(
                failed: true, fontFailed: true, onRetry: () => retries++))));
    expect(find.textContaining('font failed'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });
  for (final failed in [true]) {
    testWidgets('failure status stays visible without blocking input: $failed',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox.expand(),
              ),
            ),
            ReaderLoadingStatus(failed: failed),
          ]),
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('loading failed'), findsOneWidget);
      await tester.tapAt(tester.getCenter(find.byType(Card)));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
