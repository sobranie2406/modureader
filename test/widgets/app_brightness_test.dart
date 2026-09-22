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
      Map<String, Object> settings = const {}}) async {
    SharedPreferences.setMockInitialValues(settings);
    final controller = AppBrightness(nativeWindow: nativeWindow);
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
      home: Scaffold(body: Center(child: BrightnessWidget(controller: c))),
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
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(c.followSystem, isTrue);
    expect(c.dimOpacity, 0);
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
}
