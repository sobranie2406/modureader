import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/service/tts/base_tts.dart';
import 'package:modu_reader/service/reader_toolbar_visibility.dart';
import 'package:modu_reader/widgets/reading_page/tts_quick_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ValueNotifier<TtsStateEnum> state;
  late List<String> actions;
  Finder key(String name) => find.byKey(ValueKey('tts-quick-$name'));

  setUpAll(() async {
    // Deferred locale libraries require real asynchronous loading, outside
    // the widget tests' fake clock, before exercising language changes.
    for (final language in ['zh', 'en', 'de', 'ar']) {
      await L10n.delegate.load(Locale(language));
    }
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({'readerMenuOpacityPercent': 60});
    await Prefs().initPrefs();
    state = ValueNotifier(TtsStateEnum.playing);
    actions = [];
  });
  tearDown(() => state.dispose());

  Future<void> mount(WidgetTester tester,
      {Locale locale = const Locale('zh'),
      double scale = 1,
      bool floating = false,
      ReaderToolbarVisibility? visibility,
      Future<void> Function()? previous,
      Future<void> Function()? readHere}) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        ...GlobalMaterialLocalizations.delegates
      ],
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(
              child: GestureDetector(
            onTap: () => actions.add('body'),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(key: ValueKey('reader-viewport')),
          )),
          Positioned(
            left: floating ? 0 : 12,
            right: floating ? 0 : 12,
            top: floating ? 0 : null,
            bottom: floating ? 0 : 24,
            child: Center(
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: floating ? double.infinity : 440),
                child: TtsQuickToolbar(
                  floating: floating,
                  visibility: visibility,
                  stateListenable: state,
                  onReturnToPosition: () async => actions.add('return'),
                  onReadHere: readHere ?? () async => actions.add('here'),
                  onPrevious: previous ?? () async => actions.add('previous'),
                  onNext: () async => actions.add('next'),
                  onPlay: () async {
                    actions.add('play');
                    state.value = TtsStateEnum.playing;
                  },
                  onPause: () async {
                    actions.add('pause');
                    state.value = TtsStateEnum.paused;
                  },
                  onStop: () async {
                    actions.add('stop');
                    state.value = TtsStateEnum.stopped;
                  },
                  onOpenSettings: () => actions.add('settings'),
                ),
              ),
            ),
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final playing in [true, false]) {
    testWidgets('all shortcuts are immediately usable when playing=$playing',
        (tester) async {
      state.value = playing ? TtsStateEnum.playing : TtsStateEnum.paused;
      await mount(tester);
      expect(find.text('回朗读页'), findsNothing);
      expect(find.text('此页朗读'), findsNothing);
      expect(find.byTooltip('回朗读页'), findsOneWidget);
      expect(find.byTooltip('此页朗读'), findsOneWidget);
      expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_lesson_outlined), findsOneWidget);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      final stopButton = tester.widget<IconButton>(key('stop'));
      final previousButton = tester.widget<IconButton>(key('previous'));
      expect(stopButton.iconSize, previousButton.iconSize);
      expect(stopButton.color, previousButton.color);
      expect(stopButton.style?.backgroundColor?.resolve({}),
          previousButton.style?.backgroundColor?.resolve({}));
      await tester.tap(key('return'));
      await tester.pumpAndSettle();
      await tester.tap(key('read-here'));
      await tester.pumpAndSettle();
      await tester.tap(key('settings'));
      await tester.pumpAndSettle();
      await tester.tap(key('previous'));
      await tester.pumpAndSettle();
      await tester.tap(key('next'));
      await tester.pumpAndSettle();
      expect(actions, ['return', 'here', 'settings', 'previous', 'next']);
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.text('上一段'), findsNothing);
      expect(find.text('下一段'), findsNothing);
      expect(state.value, playing ? TtsStateEnum.playing : TtsStateEnum.paused);
      expect(find.byTooltip('停止朗读'), findsOneWidget);
      expect(tester.getRect(key('stop')).left,
          greaterThanOrEqualTo(tester.getRect(key('read-here')).right));
      await tester.tap(key('stop'));
      await tester.pumpAndSettle();
      expect(actions.last, 'stop');
      expect(state.value, TtsStateEnum.stopped);
      expect(key('toolbar'), findsNothing);
    });
  }

  testWidgets('pause and resume update directly without dismissing controls',
      (tester) async {
    await mount(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(key('play-pause'));
      await tester.pumpAndSettle();
      expect(state.value, TtsStateEnum.paused);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await tester.tap(key('play-pause'));
      await tester.pumpAndSettle();
      expect(state.value, TtsStateEnum.playing);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    }
    expect(actions, ['pause', 'play', 'pause', 'play', 'pause', 'play']);
    expect(key('return').hitTestable(), findsOneWidget);
  });

  testWidgets('stopped narration hides shortcuts and does not intercept taps',
      (tester) async {
    state.value = TtsStateEnum.stopped;
    await mount(tester);
    expect(key('toolbar'), findsNothing);
    await tester.tapAt(const Offset(400, 550));
    expect(actions, ['body']);
    state.value = TtsStateEnum.paused;
    await tester.pumpAndSettle();
    expect(key('toolbar'), findsOneWidget);
    state.value = TtsStateEnum.stopped;
    await tester.pumpAndSettle();
    expect(key('toolbar'), findsNothing);
  });

  testWidgets('360px phone fits one icon row with 44px touch targets',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await mount(tester, scale: 2);
    expect(tester.getSize(key('toolbar')).height, 44);
    for (final name in [
      'settings',
      'return',
      'previous',
      'play-pause',
      'next',
      'read-here',
      'stop'
    ]) {
      expect(tester.getSize(key(name)), const Size(44, 44));
      expect(key(name).hitTestable(), findsOneWidget);
    }
    await tester.longPress(key('stop'));
    await tester.pumpAndSettle();
    expect(find.text('停止朗读'), findsOneWidget);
    expect(actions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the compact bar intercepts taps; the book never reflows',
      (tester) async {
    await mount(tester);
    final viewport =
        tester.getRect(find.byKey(const ValueKey('reader-viewport')));
    expect(tester.getSize(key('toolbar')), const Size(440, 44));
    await tester.tapAt(const Offset(50, 100));
    expect(actions, ['body']);
    state.value = TtsStateEnum.stopped;
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('reader-viewport'))),
        viewport);
  });

  testWidgets('floating background ignores menu opacity and icons stay opaque',
      (tester) async {
    await mount(tester, floating: true);
    final material = tester.widget<Material>(find
        .descendant(of: key('toolbar'), matching: find.byType(Material))
        .first);
    expect(material.color!.a, closeTo(0.2, 0.005));
    for (final name in ['return', 'read-here', 'stop', 'play-pause']) {
      expect(tester.widget<IconButton>(key(name)).color!.a, 1);
    }
  });

  testWidgets('floating controls hide without stopping or blocking narration',
      (tester) async {
    final visibility = ReaderToolbarVisibility();
    addTearDown(visibility.dispose);
    await mount(tester, floating: true, visibility: visibility);
    final viewport =
        tester.getRect(find.byKey(const ValueKey('reader-viewport')));
    final bar = tester.getRect(key('toolbar'));
    await tester.pump(ReaderToolbarVisibility.hideDelay);
    expect(key('toolbar'), findsNothing);
    expect(state.value, TtsStateEnum.playing);
    expect(actions, isEmpty);
    expect(tester.getRect(find.byKey(const ValueKey('reader-viewport'))),
        viewport);
    await tester.tapAt(bar.center);
    expect(actions, ['body']);

    visibility.reveal();
    await tester.pump();
    expect(key('toolbar').hitTestable(), findsOneWidget);
    expect(tester.getRect(key('toolbar')), bar);
    await tester.tap(key('play-pause'));
    await tester.pumpAndSettle();
    expect(state.value, TtsStateEnum.paused);
    await tester.pump(ReaderToolbarVisibility.hideDelay);
    expect(key('toolbar'), findsNothing);
    state.value = TtsStateEnum.stopped;
    await tester.pump();
    expect(visibility.enabled, isFalse);
    visibility.reveal();
    await tester.pump();
    expect(key('toolbar'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final cancel in [false, true]) {
    testWidgets('pointer ${cancel ? 'cancel' : 'release'} restarts the timeout',
        (tester) async {
      await mount(tester, floating: true);
      final gesture = await tester.startGesture(
          tester.getTopLeft(key('toolbar')) + const Offset(4, 22));
      await tester.pump(const Duration(seconds: 10));
      expect(key('toolbar'), findsOneWidget);
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pump(const Duration(milliseconds: 4999));
      expect(key('toolbar'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(key('toolbar'), findsNothing);
      expect(actions, isEmpty);
    });
  }

  testWidgets('pending actions hold the floating controls until completion',
      (tester) async {
    final pending = Completer<void>();
    await mount(tester, floating: true, previous: () {
      actions.add('previous');
      return pending.future;
    });
    await tester.tap(key('previous'));
    await tester.pump(const Duration(seconds: 10));
    expect(key('toolbar'), findsOneWidget);
    expect(tester.widget<IconButton>(key('previous')).onPressed, isNull);
    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4999));
    expect(key('toolbar'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    expect(key('toolbar'), findsNothing);
    expect(state.value, TtsStateEnum.playing);
    expect(actions, ['previous']);
  });

  testWidgets('nonfloating controls do not enable or follow automatic hiding',
      (tester) async {
    final visibility = ReaderToolbarVisibility();
    addTearDown(visibility.dispose);
    await mount(tester, visibility: visibility);
    await tester.pump(const Duration(seconds: 20));
    expect(visibility.enabled, isFalse);
    expect(key('toolbar').hitTestable(), findsOneWidget);
    await tester.tap(key('play-pause'));
    await tester.pump();
    expect(state.value, TtsStateEnum.paused);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unmount disables but does not dispose an external controller',
      (tester) async {
    final visibility = ReaderToolbarVisibility();
    addTearDown(visibility.dispose);
    await mount(tester, floating: true, visibility: visibility);
    expect(visibility.enabled, isTrue);
    await tester.pumpWidget(const SizedBox());
    expect(visibility.enabled, isFalse);
    expect(visibility.visible, isFalse);
    await tester.pump(const Duration(seconds: 10));
    visibility.setEnabled(true);
    expect(visibility.visible, isTrue);
    visibility.setEnabled(false);
    expect(actions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dragging moves only the bar, never invokes a button or blocks the book',
      (tester) async {
    await mount(tester, floating: true);
    final viewport =
        tester.getRect(find.byKey(const ValueKey('reader-viewport')));
    final before = tester.getRect(key('toolbar'));
    await tester.drag(key('return'), const Offset(100, -180));
    await tester.pumpAndSettle();
    final moved = tester.getRect(key('toolbar'));
    expect(moved.left, greaterThan(before.left));
    expect(moved.top, lessThan(before.top - 100));
    expect(actions, isEmpty);
    expect(tester.getRect(find.byKey(const ValueKey('reader-viewport'))),
        viewport);
    await tester.tapAt(before.center);
    expect(actions, ['body']);
    await tester.tap(key('play-pause'));
    await tester.pumpAndSettle();
    expect(tester.getRect(key('toolbar')), moved);
    expect(actions.last, 'pause');
    await tester.tap(key('stop'));
    await tester.pumpAndSettle();
    await tester.tapAt(moved.center);
    expect(actions.last, 'body');
    expect(key('toolbar'), findsNothing);
  });

  testWidgets('drag and resize keep all controls inside the screen',
      (tester) async {
    await mount(tester, floating: true);
    await tester.drag(key('return'), const Offset(-2000, -2000));
    await tester.pumpAndSettle();
    expect(tester.getRect(key('toolbar')).topLeft, const Offset(12, 12));
    await tester.drag(key('return'), const Offset(4000, 4000));
    await tester.pumpAndSettle();
    expect(tester.getRect(key('toolbar')).bottomRight, const Offset(788, 576));
    tester.view.physicalSize = const Size(280, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
    final rect = tester.getRect(key('toolbar'));
    expect(rect.right, lessThanOrEqualTo(268));
    expect(rect.bottom, lessThanOrEqualTo(476));
    for (final name in [
      'settings',
      'return',
      'previous',
      'play-pause',
      'next',
      'read-here',
      'stop'
    ]) {
      expect(key(name).hitTestable(), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  for (final locale in [
    const Locale('en'),
    const Locale('de'),
    const Locale('ar')
  ]) {
    testWidgets('narrow screen and large localized text fit: $locale',
        (tester) async {
      tester.view.physicalSize = const Size(280, 560);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await mount(tester, locale: locale, scale: 2);
      for (final name in [
        'return',
        'read-here',
        'previous',
        'next',
        'play-pause',
        'settings',
        'stop',
      ]) {
        expect(key(name).hitTestable(), findsOneWidget,
            reason:
                '$name: ${tester.getRect(key(name))}, bar: ${tester.getRect(key('toolbar'))}');
        final rect = tester.getRect(key(name));
        expect(rect.left, greaterThanOrEqualTo(12));
        expect(rect.right, lessThanOrEqualTo(268));
      }
      expect(tester.getSize(key('toolbar')).height, 88);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'wide capsule orders arrows around playback; resizing stacks two rows',
      (tester) async {
    await mount(tester);
    final names = [
      'settings',
      'return',
      'previous',
      'play-pause',
      'next',
      'read-here',
      'stop',
    ];
    for (var i = 1; i < names.length; i++) {
      expect(tester.getRect(key(names[i])).left,
          greaterThanOrEqualTo(tester.getRect(key(names[i - 1])).right));
    }
    final viewport =
        tester.getRect(find.byKey(const ValueKey('reader-viewport')));
    tester.view.physicalSize = const Size(280, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
    expect(tester.getSize(key('toolbar')).height, 88);
    expect(tester.getRect(key('return')).bottom,
        lessThanOrEqualTo(tester.getRect(key('previous')).top));
    for (final name in names) {
      expect(key(name).hitTestable(), findsOneWidget);
    }
    expect(tester.getRect(key('stop')).left,
        greaterThanOrEqualTo(tester.getRect(key('next')).right));
    await tester.tap(key('stop'));
    await tester.pumpAndSettle();
    expect(actions, ['stop']);
    state.value = TtsStateEnum.stopped;
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('reader-viewport'))).size,
        const Size(280, 600));
    expect(viewport.size, const Size(800, 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending paragraph navigation cannot overlap another seek',
      (tester) async {
    final pending = Completer<void>();
    await mount(tester, previous: () {
      actions.add('previous');
      return pending.future;
    });
    await tester.tap(key('previous'));
    await tester.pump();
    await tester.tap(key('next'));
    expect(actions, ['previous']);
    for (final name in ['previous', 'next', 'play-pause', 'settings', 'stop']) {
      expect(tester.widget<IconButton>(key(name)).onPressed, isNull);
    }
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(key('next')).onPressed, isNotNull);
  });

  testWidgets('pending restart cannot be submitted twice', (tester) async {
    final pending = Completer<void>();
    await mount(tester, readHere: () {
      actions.add('here');
      return pending.future;
    });
    await tester.tap(key('read-here'));
    await tester.pump();
    await tester.tap(key('read-here'));
    expect(actions, ['here']);
    expect(tester.widget<IconButton>(key('return')).onPressed, isNull);
    // Stopping/starting the engine mid-operation preserves the busy guard.
    state.value = TtsStateEnum.stopped;
    await tester.pump();
    state.value = TtsStateEnum.playing;
    await tester.pump();
    expect(tester.widget<IconButton>(key('read-here')).onPressed, isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(key('read-here')).onPressed, isNotNull);
  });

  testWidgets('errors are reported and controls remain usable', (tester) async {
    await mount(tester, readHere: () async => throw StateError('failed'));
    await tester.tap(key('read-here'));
    await tester.pumpAndSettle();
    expect(find.text('朗读操作失败，请重试'), findsOneWidget);
    expect(tester.widget<IconButton>(key('read-here')).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving during a pending action does not update disposed state',
      (tester) async {
    final pending = Completer<void>();
    await mount(tester, readHere: () => pending.future);
    await tester.tap(key('read-here'));
    await tester.pumpWidget(const SizedBox());
    pending.completeError(StateError('late'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
