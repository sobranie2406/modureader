import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/widgets/page_router/reading_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('animation switch persists and preserves the existing default',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    expect(Prefs().openBookAnimation, isTrue);
    Prefs().openBookAnimation = false;
    expect((await SharedPreferences.getInstance()).getBool('openBookAnimation'),
        false);
    expect(Prefs().openBookAnimation, false);
    Prefs().openBookAnimation = true;
    expect(Prefs().openBookAnimation, true);
  });
  testWidgets(
      'disabled route opens immediately, suppresses Hero and closes immediately',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
        CupertinoApp(navigatorKey: key, home: const Text('Library')));
    final route = readingRoute<void>(
        animate: false, builder: (_) => const Text('Reader'));
    expect((route as PageRoute).transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    key.currentState!.push(route);
    await tester.pumpAndSettle();
    expect(find.text('Reader'), findsOneWidget);
    expect(tester.widget<HeroMode>(find.byType(HeroMode).last).enabled, false);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Library'), findsOneWidget);
  });
  test('enabled iOS route retains Cupertino gesture support with cover timing',
      () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final route =
        readingRoute<void>(animate: true, builder: (_) => const Text('Reader'));
    expect(route, isA<CupertinoPageRoute<void>>());
    expect((route as PageRoute).transitionDuration,
        const Duration(milliseconds: 720));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 620));
  });
  test('enabled Android route uses the stationary reader cover transition', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final route =
        readingRoute<void>(animate: true, builder: (_) => const Text('Reader'));
    expect(route, isA<PageRouteBuilder<void>>());
    expect((route as PageRoute).transitionDuration,
        const Duration(milliseconds: 720));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 620));
  });
}
