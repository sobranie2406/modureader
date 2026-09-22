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
    expect(c.level, 0.2);
    expect(c.dimOpacity, closeTo(0.8, 0.001));
    c.setLevel(double.nan);
    expect(c.level, 0.2);
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
    c.setLevel(0.45);
    await c.save();
    final restored = AppBrightness(nativeWindow: false);
    addTearDown(restored.dispose);
    await restored.initialize(await SharedPreferences.getInstance());
    expect(restored.followSystem, isFalse);
    expect(restored.level, 0.45);
    final invalid = await create(settings: {
      AppBrightness.levelKey: 'bad value',
      AppBrightness.followSystemKey: 'bad value',
    });
    expect(invalid.followSystem, isTrue);
    expect(invalid.level, 0.6);
  });

  test(
      'Android sets window brightness and null restores system, without dimming',
      () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AppBrightness.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(AppBrightness.channel, null));
    final c = await create(nativeWindow: true);
    expect(calls.single.arguments['brightness'], isNull);
    c.setLevel(0.4);
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.method, 'setBrightness');
    expect(calls.last.arguments['brightness'], 0.4);
    expect(c.dimOpacity, 0);
    c.setFollowSystem(true);
    await c.save();
    await Future<void>.delayed(Duration.zero);
    expect(calls.last.arguments['brightness'], isNull);
  });

  test('missing native bridge safely falls back to app dimming', () async {
    final c = await create(nativeWindow: true);
    c.setLevel(0.4);
    await Future<void>.delayed(Duration.zero);
    expect(c.usesWindowBrightness, isFalse);
    expect(c.dimOpacity, closeTo(0.6, 0.001));
  });

  testWidgets(
      'slider adjusts immediately, saves on release, and reset is accessible',
      (tester) async {
    final c = await create();
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
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
    expect(c.followSystem, isFalse);
    expect(c.level, 0.6);
    expect(refreshes, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dimming preserves input and does not rebuild content',
      (tester) async {
    final c = await create();
    var taps = 0;
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
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

  testWidgets('macOS dimming never paints Flutter over the native reader',
      (tester) async {
    final calls = <MethodCall>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AppBrightness.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(AppBrightness.channel, null));
    final c = await create(nativeDimming: true, settings: {
      AppBrightness.levelKey: 0.35,
      AppBrightness.followSystemKey: false,
    });
    expect(calls.single.arguments['brightness'], 0.35);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var taps = 0, keys = 0, builds = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => AppBrightnessLayer(controller: c, child: child!),
      home: Builder(builder: (_) {
        builds++;
        return Focus(
          focusNode: focus,
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent) keys++;
            return KeyEventResult.handled;
          },
          child:
              GestureDetector(onTap: () => taps++, child: const Text('Reader')),
        );
      }),
    ));
    await tester.pump();
    final initialBuilds = builds;
    for (final value in [0.2, 0.6, 1.0]) {
      c.setLevel(value);
      await tester.pump();
      expect(calls.last.arguments['brightness'], value);
      expect(c.dimOpacity, 0);
      expect(find.byKey(const ValueKey('app-flutter-brightness-dimmer')),
          findsNothing);
      final layer =
          tester.widget<AppBrightnessLayer>(find.byType(AppBrightnessLayer));
      expect(layer.build(tester.element(find.byType(AppBrightnessLayer))),
          same(layer.child));
      await tester.tap(find.text('Reader'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      expect(focus.hasPrimaryFocus, isTrue);
    }
    expect(taps, 3);
    expect(keys, 3);
    expect(builds, initialBuilds);
    c.setFollowSystem(true);
    await tester.pump();
    expect(calls.last.arguments['brightness'], isNull);
    expect(c.nativeDimmingUnavailable, isFalse);
  });

  test('macOS bridge failure never restores an input-blocking Flutter overlay',
      () async {
    final c = await create(nativeDimming: true);
    c.setLevel(0.2);
    await Future<void>.delayed(Duration.zero);
    expect(c.nativeDimmingUnavailable, isTrue);
    expect(c.paintsFlutterDimming, isFalse);
    expect(c.dimOpacity, 0);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        AppBrightness.channel, (_) async => null);
    addTearDown(
        () => messenger.setMockMethodCallHandler(AppBrightness.channel, null));
    c.setLevel(0.5);
    await Future<void>.delayed(Duration.zero);
    expect(c.nativeDimmingUnavailable, isFalse);
    expect(c.dimOpacity, 0);
  });
}
