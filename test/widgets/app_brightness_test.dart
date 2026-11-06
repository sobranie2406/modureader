import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/app_brightness.dart';
import 'package:anx_reader/widgets/reading_page/brightness_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppBrightness> create(
      {bool nativeWindow = false,
      bool nativeDimming = false,
      Map<String, Object> settings = const {}}) async {
    SharedPreferences.setMockInitialValues(settings);
    await Prefs().initPrefs();
    final controller =
        AppBrightness(nativeWindow: nativeWindow, nativeDimming: nativeDimming);
    await controller.initialize(await SharedPreferences.getInstance());
    addTearDown(controller.dispose);
    return controller;
  }

  test('defaults to system; adjustment is bounded and reset removes dimming',
      () async {
    final c = await create();
    expect(c.followSystem, isTrue);
    expect(c.dimOpacity, 0);
    c.setLevel(-1);
    expect(c.level, 0);
    expect(c.dimOpacity, closeTo(0.95, 0.001));
    c.setLevel(double.nan);
    expect(c.level, 0);
    c.setLevel(2);
    expect(c.level, 1);
    c.setLevel(0.5);
    c.setFollowSystem(true);
    expect(c.dimOpacity, 0);
    expect(c.level, 0.5);
    await c.save();
  });

  test('manual preference survives restart and malformed values are safe',
      () async {
    final c = await create();
    c.setLevel(0.05);
    await c.save();
    final restored = AppBrightness(nativeWindow: false);
    addTearDown(restored.dispose);
    await restored.initialize(await SharedPreferences.getInstance());
    expect(restored.followSystem, isFalse);
    expect(restored.level, 0.05);
    final invalid = await create(settings: {
      AppBrightness.levelKey: 'bad value',
      AppBrightness.followSystemKey: 'bad value',
    });
    expect(invalid.followSystem, isTrue);
    expect(invalid.level, 0.6);
  });

  for (final mac in [false, true]) {
    test('legacy ${mac ? 'macOS' : 'Android'} override is cleared once',
        () async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(AppBrightness.channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(AppBrightness.channel, null));
      final c = await create(nativeWindow: !mac, nativeDimming: mac, settings: {
        AppBrightness.levelKey: 0.01,
        AppBrightness.followSystemKey: false,
      });
      expect(calls.single.arguments['brightness'], isNull);
      for (final level in [0.0, 0.1, 0.4, 1.0]) {
        c.setLevel(level);
        await Future<void>.delayed(Duration.zero);
        expect(c.dimOpacity, closeTo((1 - level).clamp(0, .95), .001));
      }
      c.setFollowSystem(true);
      await c.save();
      expect(calls.length, 1);
    });
  }

  test('missing legacy bridge does not prevent book-only dimming', () async {
    final c = await create(nativeWindow: true);
    c.setLevel(.4);
    expect(c.dimOpacity, closeTo(.6, .001));
  });

  testWidgets(
      'slider adjusts immediately, saves on release, and reset is accessible',
      (tester) async {
    final c = await create();
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
          body: Center(
              child: BrightnessWidget(
        controller: c,
        onNightModeChanged: () {},
      ))),
    ));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 0);
    expect(slider.max, 100);
    expect(slider.divisions, 100);
    slider.onChanged!(1);
    await tester.pump();
    expect(c.level, 0.01);
    expect(find.text('1%'), findsOneWidget);
    c.setLevel(0.6);
    await tester.pump();
    await tester.drag(find.byType(Slider), const Offset(-50, 0));
    await tester.pumpAndSettle();
    expect(c.followSystem, isFalse);
    expect(c.level, lessThan(0.6));
    expect(
        (await SharedPreferences.getInstance())
            .getDouble(AppBrightness.levelKey),
        c.level);
    await tester.tap(find.byKey(const ValueKey('brightness-auto')));
    await tester.pumpAndSettle();
    expect(c.followSystem, isTrue);
    expect(c.dimOpacity, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'auto / slider / night stay ordered; night does not change brightness',
      (tester) async {
    final c = await create();
    await tester.binding.setSurfaceSize(const Size(280, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var refreshes = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
          body: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: BrightnessWidget(
            controller: c, onNightModeChanged: () => refreshes++),
      )),
    ));
    await tester.pumpAndSettle();
    final auto = find.byKey(const ValueKey('brightness-auto'));
    final night = find.byKey(const ValueKey('brightness-night'));
    expect(tester.getCenter(auto).dx,
        lessThan(tester.getCenter(find.byType(Slider)).dx));
    expect(tester.getCenter(night).dx,
        greaterThan(tester.getCenter(find.byType(Slider)).dx));
    await tester.tap(night);
    await tester.pumpAndSettle();
    expect(Prefs().readingNightMode, isTrue);
    expect(Prefs().themeMode, ThemeMode.dark);
    expect(tester.widget<IconButton>(night).isSelected, isTrue);
    expect(c.followSystem, isTrue);
    expect(c.level, 0.6);
    expect(refreshes, 1);
    await tester.tap(auto);
    await tester.pumpAndSettle();
    expect(c.followSystem, isFalse);
    expect(Prefs().readingNightMode, isTrue);
    await tester.tap(night);
    await tester.pumpAndSettle();
    expect(Prefs().readingNightMode, isFalse);
    expect(Prefs().themeMode, ThemeMode.light);
    expect(c.followSystem, isFalse);
    expect(c.level, 0.6);
    expect(refreshes, 2);
    Prefs().readingNightMode = true;
    Prefs().eInkMode = true;
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(night).onPressed, isNull);
    expect(Prefs().themeMode, ThemeMode.light);
    expect(tester.widget<IconButton>(night).isSelected, isFalse);
    expect(Prefs().readingNightMode, isTrue);
    Prefs().eInkMode = false;
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(night).onPressed, isNotNull);
    expect(tester.widget<IconButton>(night).isSelected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moon updates the open app theme in both directions',
      (tester) async {
    final c = await create();
    final dayTheme = Prefs().readTheme;
    final autoReading = Prefs().autoAdjustReadingTheme;
    var refreshes = 0;
    await tester.pumpWidget(ListenableBuilder(
      listenable: Prefs(),
      builder: (context, _) => MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: Prefs().themeMode,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: BrightnessWidget(
            controller: c,
            onNightModeChanged: () => refreshes++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final moon = find.byKey(const ValueKey('brightness-night'));
    for (final dark in [true, false]) {
      await tester.tap(moon);
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(moon)).brightness,
          dark ? Brightness.dark : Brightness.light);
      expect(Prefs().prefs.getString('themeMode'), dark ? 'dark' : 'light');
      expect(Prefs().readingNightMode, dark);
      expect(Prefs().readTheme.backgroundColor, dayTheme.backgroundColor);
      expect(Prefs().readTheme.textColor, dayTheme.textColor);
      expect(Prefs().autoAdjustReadingTheme, autoReading);
      expect(c.followSystem, isTrue);
    }
    expect(refreshes, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dimming preserves input and does not rebuild content',
      (tester) async {
    final c = await create();
    var taps = 0;
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) =>
          AppBrightnessLayer(controller: c, child: child!),
      home: Builder(builder: (context) {
        builds++;
        return Scaffold(
            body: Center(
                child: TextButton(
                    onPressed: () => taps++, child: const Text('Tap'))));
      }),
    ));
    final initialBuilds = builds;
    c.setLevel(0.2);
    await tester.pump();
    await tester.tap(find.text('Tap'));
    expect(taps, 1);
    expect(builds, initialBuilds);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'minimum dims book content in both themes; menu and next route stay normal',
      (tester) async {
    final c = await create();
    c.setLevel(0);
    var taps = 0;
    Widget app(Brightness brightness) => MaterialApp(
          theme: brightness == Brightness.dark
              ? ThemeData.dark()
              : ThemeData.light(),
          home: Scaffold(
              body: Builder(
                  builder: (context) => Column(children: [
                        Expanded(
                            child: AppBrightnessLayer(
                                controller: c,
                                child: const Center(child: Text('Book')))),
                        TextButton(
                            onPressed: () => taps++,
                            child: const Text('Brightness menu')),
                        TextButton(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                    builder: (_) =>
                                        const Scaffold(body: Text('Shelf')))),
                            child: const Text('Exit')),
                      ]))),
        );
    final dimmer = find.byKey(const ValueKey('app-flutter-brightness-dimmer'));
    await tester.pumpWidget(app(Brightness.light));
    expect(tester.widget<ColoredBox>(dimmer).color.a, closeTo(.95, .001));
    await tester.pumpWidget(app(Brightness.dark));
    await tester.pumpAndSettle();
    expect(tester.widget<ColoredBox>(dimmer).color.a, closeTo(.95, .001));
    expect(tester.getRect(dimmer).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Brightness menu')).top));
    await tester.tap(find.text('Brightness menu'));
    expect(taps, 1);
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();
    expect(find.text('Shelf'), findsOneWidget);
    expect(dimmer, findsNothing);
    expect(c.level, 0);
  });

  testWidgets(
      'light mode enables brightness and auto controls as well as the moon',
      (tester) async {
    final c = await create();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
          body: BrightnessWidget(controller: c, onNightModeChanged: () {})),
    ));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('brightness-auto')))
            .onPressed,
        isNotNull);
    expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('brightness-night')))
            .onPressed,
        isNotNull);
  });
}
