import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/page/settings_page/appearance.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/utils/color_scheme.dart';
import 'package:modu_reader/widgets/bookshelf/spining_sync_icon.dart';
import 'package:modu_reader/widgets/page_router/reading_route.dart';
import 'package:modu_reader/widgets/page_router/page_dismiss_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    for (final locale in [const Locale('en'), const Locale('zh', 'CN')]) {
      for (final delegate in L10n.localizationsDelegates) {
        if (delegate.isSupported(locale)) await delegate.load(locale);
      }
    }
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
  test('E-Ink animation choice persists and never applies outside E-Ink',
      () async {
    final prefs = Prefs();
    final pageStyle = prefs.pageTurnStyle;
    prefs.openBookAnimation = true;
    expect(prefs.eInkDisableAnimations, true);
    for (final eink in [false, true]) {
      for (final disable in [false, true]) {
        prefs.eInkMode = eink;
        prefs.eInkDisableAnimations = disable;
        expect(AppMotion.disabled, eink && disable);
        expect(AppMotion.duration(const Duration(seconds: 1)),
            eink && disable ? Duration.zero : const Duration(seconds: 1));
        final route =
            MotionCupertinoPageRoute<void>(builder: (_) => const SizedBox());
        expect(route.transitionDuration == Duration.zero, eink && disable);
        route.dispose();
      }
    }
    prefs.eInkDisableAnimations = false;
    await prefs.initPrefs();
    expect(prefs.eInkDisableAnimations, false);
    expect(prefs.eInkMode, true);
    expect(AppMotion.disabled, false);
    expect(prefs.openBookAnimation, true);
    expect(prefs.pageTurnStyle, pageStyle);
  });
  for (final language in ['en', 'zh-CN']) {
    testWidgets('$language animation switch is disabled outside E-Ink',
        (tester) async {
      await Prefs().saveLocaleToPrefs(language);
      await tester.pumpWidget(MaterialApp(
          locale: Prefs().locale,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(body: AppearanceSetting())));
      await tester.pumpAndSettle();
      final mode = find.descendant(
          of: find.byKey(const ValueKey('eink-mode')),
          matching: find.byType(Switch));
      final animations = find.descendant(
          of: find.byKey(const ValueKey('eink-disable-animations')),
          matching: find.byType(Switch));
      await tester.ensureVisible(animations);
      await tester.pump();
      expect(tester.widget<Switch>(animations).onChanged, isNull);
      expect(tester.widget<Switch>(animations).value, true);
      expect(find.text(language == 'en' ? 'Disable all animations' : '关闭所有动画'),
          findsOneWidget);
      await tester.tap(animations, warnIfMissed: false);
      expect(Prefs().eInkDisableAnimations, true);
      await tester.ensureVisible(mode);
      await tester.pump();
      await tester.tap(mode);
      await tester.pumpAndSettle();
      // The theme-mode selector now lives on the theme colour page; E-Ink
      // disables it there (covered by the theme colour page tests).
      await tester.ensureVisible(animations);
      await tester.pump();
      expect(tester.widget<Switch>(animations).onChanged, isNotNull);
      await tester.tap(animations);
      await tester.pumpAndSettle();
      expect(Prefs().eInkDisableAnimations, false);
      expect(AppMotion.disabled, false);
      await tester.ensureVisible(mode);
      await tester.pump();
      await tester.tap(mode);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(animations).onChanged, isNull);
      expect(tester.widget<Switch>(animations).value, false);
      await tester.ensureVisible(mode);
      await tester.pump();
      await tester.tap(mode);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(animations).value, false);
      expect(AppMotion.disabled, false);
      expect(tester.takeException(), isNull);
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
        'E-Ink palette stays pure black/white with animations on: dark=$dark',
        (tester) async {
      Prefs().eInkMode = true;
      Prefs().eInkDisableAnimations = false;
      await Prefs().saveThemeModeToPrefs(dark ? 'dark' : 'light');
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
        context = c;
        return const SizedBox();
      })));
      final theme = colorSchema(Prefs(), context, Brightness.dark);
      const foreground = Colors.black;
      const background = Colors.white;
      expect(theme.colorScheme.primary, foreground);
      expect(theme.colorScheme.onSurface, foreground);
      expect(theme.colorScheme.onSurfaceVariant, foreground);
      expect(theme.textTheme.bodyMedium!.color, foreground);
      expect(theme.scaffoldBackgroundColor, background);
      expect(theme.colorScheme.surface, background);
      expect(theme.colorScheme.surfaceContainer, background);
      expect(theme.dialogTheme.backgroundColor, background);
      expect(theme.bottomSheetTheme.backgroundColor, background);
      expect(theme.brightness, Brightness.light);
      expect(theme.splashFactory, isNot(NoSplash.splashFactory));
      for (final platform in TargetPlatform.values) {
        expect(theme.pageTransitionsTheme.builders[platform],
            isNot(isA<NoMotionPageTransitionsBuilder>()));
      }
      expect(AppMotion.style, isNull);
    });
  }
  testWidgets(
      'mounted drag controller resumes and stops motion with the switch',
      (tester) async {
    Prefs().eInkMode = true;
    final controller = PageDismissController(vsync: tester);
    addTearDown(controller.dispose);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    controller.updateDrag(DragUpdateDetails(
        delta: const Offset(0, -50), globalPosition: Offset.zero));
    await controller.endDrag(DragEndDetails(), context);
    expect(controller.state, DismissalState.idle);
    Prefs().eInkDisableAnimations = false;
    controller.updateDrag(DragUpdateDetails(
        delta: const Offset(0, -50), globalPosition: Offset.zero));
    final settling = controller.endDrag(DragEndDetails(), context);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.state, DismissalState.animatingBack);
    expect(controller.currentOffset.dy, greaterThan(-50));
    expect(controller.currentOffset.dy, lessThan(0));
    await tester.pump(const Duration(milliseconds: 300));
    await settling;
    expect(controller.state, DismissalState.idle);
    Prefs().eInkDisableAnimations = true;
    controller.updateDrag(DragUpdateDetails(
        delta: const Offset(0, -50), globalPosition: Offset.zero));
    await controller.endDrag(DragEndDetails(), context);
    expect(controller.state, DismissalState.idle);
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
    expect(TickerMode.valuesOf(context).enabled, false);
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
