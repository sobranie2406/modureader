import 'dart:ui' as ui;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/app_brightness.dart';
import 'package:anx_reader/widgets/reading_page/reader_content_brightness.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    AppBrightness.instance.setLevel(0);
  });
  tearDown(() => AppBrightness.instance.setFollowSystem(true));

  for (final adjustable in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
          'content dims, nested menus do not: adjustable=$adjustable dark=$dark',
          (tester) async {
        Prefs().adjustableReaderPopups = adjustable;
        var builds = 0;
        await tester.pumpWidget(MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                        child: const Text('Open content'),
                        onPressed: () => showReaderPopup(context,
                            dimContent: true,
                            allowWindowAdjustment: true, builder: (context) {
                          builds++;
                          return Column(children: [
                            const Text('Query result'),
                            TextButton(
                                child: const Text('Settings'),
                                onPressed: () => showReaderPopup(context,
                                    builder: (_) => const Text('Menu'))),
                          ]);
                        }),
                      ))),
        ));
        await tester.tap(find.text('Open content'));
        await tester.pumpAndSettle();
        final surface = find.byType(ReaderContentBrightness);
        expect(surface, findsOneWidget);
        final opacity =
            find.descendant(of: surface, matching: find.byType(Opacity)).first;
        expect(tester.widget<Opacity>(opacity).opacity, closeTo(.05, .001));
        final initialBuilds = builds;
        AppBrightness.instance.setLevel(.4);
        await tester.pump();
        expect(tester.widget<Opacity>(opacity).opacity, closeTo(.4, .001));
        expect(builds, initialBuilds);
        // The darkest content window remains interactive; the new settings
        // route must not inherit its dimming, even when opened from that window.
        AppBrightness.instance.setLevel(0);
        await tester.pump();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(find.text('Menu'), findsOneWidget);
        expect(find.ancestor(of: find.text('Menu'), matching: surface),
            findsNothing);
        Navigator.of(tester.element(find.text('Menu'))).pop();
        await tester.pumpAndSettle();
        Navigator.of(tester.element(find.text('Query result'))).pop();
        await tester.pumpAndSettle();
        expect(surface, findsNothing);
        expect(find.text('Open content'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final alpha in [0.2, 1.0]) {
    testWidgets('dimming preserves popup background alpha $alpha',
        (tester) async {
      final c = AppBrightness(nativeWindow: false, nativeDimming: false);
      addTearDown(c.dispose);
      const boundaryKey = ValueKey('surface');
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
            child: RepaintBoundary(
                key: boundaryKey,
                child: ReaderContentBrightness(
                    controller: c,
                    backgroundColor: Colors.white.withValues(alpha: alpha),
                    child: const SizedBox(width: 100, height: 100)))),
      ));
      for (final level in [1.0, .5, 0.0]) {
        c.setLevel(level);
        await tester.pump();
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba))!;
          expect(bytes.getUint8(3), closeTo(alpha * 255, 2));
          expect(bytes.getUint8(0), closeTo(255 * (1 - c.dimOpacity), 3));
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
    });
  }
}
