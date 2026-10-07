import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/utils/color_scheme.dart';
import 'package:anx_reader/widgets/bookshelf/spining_sync_icon.dart';
import 'package:anx_reader/widgets/page_router/reading_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  test('motion overrides do not rewrite saved reading preferences', () {
    Prefs().openBookAnimation = true;
    Prefs().eInkMode = true;
    expect(AppMotion.duration(const Duration(seconds: 1)), Duration.zero);
    expect(AppMotion.style, AnimationStyle.noAnimation);
    final route = readingRoute(builder: (_) => const SizedBox(), animate: true)
        as PageRoute;
    expect(route.transitionDuration, Duration.zero);
    route.dispose();
    Prefs().eInkMode = false;
    expect(Prefs().openBookAnimation, true);
    expect(AppMotion.duration(const Duration(seconds: 1)),
        const Duration(seconds: 1));
    expect(AppMotion.style, null);
  });
  testWidgets('theme and Cupertino routes enter and exit immediately',
      (tester) async {
    Prefs().eInkMode = true;
    late BuildContext home;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      home = context;
      return const Text('home');
    })));
    final theme = colorSchema(Prefs(), home, Brightness.light);
    for (final platform in TargetPlatform.values) {
      expect(theme.pageTransitionsTheme.builders[platform]!.transitionDuration,
          Duration.zero);
    }
    final route =
        MotionCupertinoPageRoute<void>(builder: (_) => const Text('page'));
    bool closed = false;
    Navigator.of(home).push(route).then((_) => closed = true);
    await tester.pump();
    expect(find.text('page'), findsOneWidget);
    expect(route.transitionDuration, Duration.zero);
    Navigator.of(home).pop();
    await tester.pumpAndSettle();
    expect(closed, true);
  });
  testWidgets(
      'indefinite progress and sync indicators stop and resume without freezing app',
      (tester) async {
    Widget app(bool eink) => MaterialApp(
        builder: (_, child) => EinkMotionScope(enabled: eink, child: child!),
        home: const Scaffold(
            body: Column(children: [
          EinkStaticIndicator(child: CircularProgressIndicator()),
          SpiningSyncIcon()
        ])));
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    final context = tester.element(find.byType(CircularProgressIndicator));
    expect(MediaQuery.disableAnimationsOf(context), true);
    expect(TickerMode.of(context), false);
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });
  testWidgets(
      'dialog and bottom sheet close without an animation future deadlock',
      (tester) async {
    Prefs().eInkMode = true;
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    final dialog = showDialog<void>(
        context: context,
        animationStyle: AppMotion.style,
        builder: (_) => const AlertDialog(content: Text('dialog')));
    await tester.pump();
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    await dialog;
    final sheet = showModalBottomSheet<void>(
        context: context,
        sheetAnimationStyle: AppMotion.style,
        builder: (_) => const Text('sheet'));
    await tester.pump();
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    await sheet;
    expect(tester.takeException(), isNull);
  });
}
