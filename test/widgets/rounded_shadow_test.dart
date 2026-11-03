import 'dart:io';
import 'dart:ui' as ui;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/color_scheme.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:anx_reader/widgets/reading_page/reader_menu_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('shadow fades outward without a second lower rim',
      (tester) async {
    final previous = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await Prefs().saveThemeModeToPrefs('light');
      const boundaryKey = ValueKey('shadow-preview');
      late ThemeData theme;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        theme = colorSchema(Prefs(), context, Brightness.light);
        return Theme(
          data: theme,
          child: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: ColoredBox(
                color: theme.colorScheme.surface,
                child: const SizedBox(
                  width: 520,
                  height: 250,
                  child: Row(children: [
                    SizedBox(width: 30),
                    FilledContainer(
                      width: 210,
                      height: 160,
                      child: Center(
                          child: Text('Settings',
                              style: TextStyle(
                                  inherit: false,
                                  color: Color(0xFF283633),
                                  fontSize: 14))),
                    ),
                    SizedBox(width: 30),
                    SizedBox(
                      width: 210,
                      height: 160,
                      child: ReaderMenuGroup(
                        margin: EdgeInsets.zero,
                        child: Center(
                            child: Text('Reading menu',
                                style: TextStyle(
                                    inherit: false,
                                    color: Color(0xFF283633),
                                    fontSize: 14))),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );
      })));
      await tester.pumpAndSettle();
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        final origin = tester.getTopLeft(find.byKey(boundaryKey));
        final box = tester.getRect(find
            .descendant(
                of: find.byType(FilledContainer),
                matching: find.byType(DecoratedBox))
            .first);
        final x = (box.center.dx - origin.dx).round();
        final bottom = (box.bottom - origin.dy).round();
        int redAt(int y) => bytes.getUint8((y * image.width + x) * 4);
        final samples = [
          for (var y = bottom + 1; y <= bottom + 18; y++) redAt(y)
        ];
        expect(samples.first, lessThan(samples.last),
            reason:
                'Shadow must be visible near the edge and fade into the page.');
        for (var i = 1; i < samples.length; i++) {
          expect(samples[i], greaterThanOrEqualTo(samples[i - 1]),
              reason:
                  'A displaced outer-blur cutout creates a second dark rim.');
        }
        // The panel keeps the theme surface exactly; the preset canvas decides
        // that colour, so read it instead of assuming the old near-white.
        final expectedInterior =
            (theme.colorScheme.surface.r * 255).round();
        expect(redAt((box.center.dy - origin.dy - 25).round()),
            expectedInterior,
            reason: 'The interior must retain the exact page background.');
        final menu = tester.getRect(find
            .descendant(
                of: find.byType(ReaderMenuGroup),
                matching: find.byType(Material))
            .first);
        final menuX = (menu.center.dx - origin.dx).round();
        final menuBottom = (menu.bottom - origin.dy).round();
        final menuSamples = [
          for (var y = menuBottom + 1; y <= menuBottom + 18; y++)
            bytes.getUint8((y * image.width + menuX) * 4)
        ];
        expect(menuSamples.last - menuSamples.first, greaterThanOrEqualTo(4),
            reason: 'Reader group shadows must be visible on the page colour.');
        for (var i = 1; i < menuSamples.length; i++) {
          expect(menuSamples[i], greaterThanOrEqualTo(menuSamples[i - 1]));
        }
        const preview = String.fromEnvironment('SHADOW_PREVIEW');
        if (preview.isNotEmpty) {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(preview).writeAsBytes(png!.buffer.asUint8List());
        }
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    } finally {
      debugDisableShadows = previous;
    }
  });
}
