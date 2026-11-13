import 'dart:ui' as ui;

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/page/settings_page/settings_page.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/utils/color_scheme.dart';
import 'package:modu_reader/widgets/app_route_surface.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final dark in [false, true]) {
    for (final sheet in [false, true]) {
      testWidgets(
          'opaque themed backing throughout ${sheet ? "sheet" : "settings"} '
          'push and pop, dark=$dark', (tester) async {
        await Prefs().saveThemeModeToPrefs(dark ? 'dark' : 'light');
        final nav = GlobalKey<NavigatorState>();
        final boundary = GlobalKey();
        late ThemeData theme;
        await tester.pumpWidget(Builder(builder: (context) {
          theme = colorSchema(
              Prefs(), context, dark ? Brightness.dark : Brightness.light);
          return RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              navigatorKey: nav,
              theme: theme.copyWith(platform: TargetPlatform.macOS),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              builder: (context, child) => AppRouteSurface(child: child!),
              home: const Scaffold(body: SizedBox.expand()),
            ),
          );
        }));
        await tester.pumpAndSettle();

        Future<void> checkFrame() async {
          final render = boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage();
            final bytes =
                (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
            // These corners are exposed by the route's slide/scale/rounding.
            // Text and the sheet's intentional scrim do not cover them.
            for (final point in [
              const Offset(1, 1),
              Offset(image.width - 2, 1),
            ]) {
              final index =
                  (point.dy.toInt() * image.width + point.dx.toInt()) * 4;
              expect(bytes.getUint8(index + 3), 255,
                  reason: 'No frame may reveal the native window');
              final color = theme.scaffoldBackgroundColor;
              for (final channel in [color.r, color.g, color.b].indexed) {
                final expected = (channel.$2 * 255).round();
                final actual = bytes.getUint8(index + channel.$1);
                if (sheet) {
                  expect(actual, closeTo(expected, 2));
                } else {
                  // A sliding page casts its intentional edge shadow.
                  expect(
                      actual, inInclusiveRange(expected * .70, expected + 2));
                }
              }
            }
            image.dispose();
          });
          expect(tester.takeException(), isNull);
        }

        if (sheet) {
          showCupertinoSheet<void>(
            context: nav.currentContext!,
            scrollableBuilder: (_, __) =>
                const Scaffold(body: SizedBox.expand()),
          );
        } else {
          final route = MotionCupertinoPageRoute<void>(
            builder: (_) => const SettingsPageBody(
              title: 'Lookup settings',
              isMobile: true,
              sections: Material(
                type: MaterialType.transparency,
                child: SizedBox.expand(),
              ),
            ),
          );
          nav.currentState!.push(route);
          expect(route.transitionDuration, greaterThan(Duration.zero));
          expect(route.reverseTransitionDuration, greaterThan(Duration.zero));
        }
        await tester.pump();
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await checkFrame();
        }
        await tester.pumpAndSettle();
        await checkFrame();
        nav.currentState!.pop();
        await tester.pump();
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await checkFrame();
        }
        await tester.pumpAndSettle();
        await checkFrame();
      });
    }
  }
}
