import 'package:anx_reader/widgets/reading_page/reader_loading_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final failed in [false, true]) {
    testWidgets('loading status stays visible without blocking input: $failed',
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
      expect(find.byType(CircularProgressIndicator),
          failed ? findsNothing : findsOneWidget);
      expect(find.textContaining(failed ? 'timed out' : 'Opening book'),
          findsOneWidget);
      await tester.tapAt(tester.getCenter(find.byType(Card)));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
