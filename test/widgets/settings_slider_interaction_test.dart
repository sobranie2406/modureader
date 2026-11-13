import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/utils/color_scheme.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final mode in ['light', 'dark', 'eink']) {
    for (final width in [320.0, 800.0]) {
      testWidgets('$mode settings at $width only change by dragging the thumb',
          (tester) async {
        tester.view.physicalSize = Size(width, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await Prefs().saveThemeModeToPrefs(mode == 'dark' ? 'dark' : 'light');
        Prefs().eInkMode = mode == 'eink';
        final scroll = ScrollController();
        addTearDown(scroll.dispose);
        double value = 50;
        var changes = 0;
        await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
          return Theme(
              data: colorSchema(Prefs(), context, Brightness.light),
              child: Scaffold(
                  body: SingleChildScrollView(
                      controller: scroll,
                      child: Column(children: [
                        const SizedBox(height: 200),
                        StatefulBuilder(builder: (context, setState) {
                          return StyleSlider(
                              icon: Icons.space_bar,
                              label: 'Margin',
                              value: value,
                              min: 0,
                              max: 100,
                              divisions: 100,
                              labelFormatter: (v) => '$v',
                              onChanged: (v) => setState(() {
                                    changes++;
                                    value = v;
                                  }));
                        }),
                        const SizedBox(height: 1000),
                      ]))));
        })));
        await tester.pumpAndSettle();
        final slider = find.byType(Slider);
        expect(Theme.of(tester.element(slider)).sliderTheme.allowedInteraction,
            SliderInteraction.slideThumb);
        final rect = tester.getRect(slider);
        final track = Offset(rect.left + rect.width * .8, rect.center.dy);
        await tester.tapAt(track);
        await tester.pumpAndSettle();
        await tester.dragFrom(track, const Offset(-30, 0));
        await tester.pumpAndSettle();
        expect(value, 50);
        expect(changes, 0);

        // Both track and thumb must allow scrolling the containing page.
        for (final start in [track, rect.center]) {
          await tester.dragFrom(start, const Offset(0, -100));
          await tester.pumpAndSettle();
          expect(scroll.offset, greaterThan(0));
          expect(value, 50);
          scroll.jumpTo(0);
          await tester.pumpAndSettle();
        }

        await tester.dragFrom(rect.center, const Offset(40, 0));
        await tester.pumpAndSettle();
        expect(value, greaterThan(50));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
