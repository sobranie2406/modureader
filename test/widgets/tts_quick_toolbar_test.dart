import 'dart:async';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/widgets/reading_page/tts_quick_toolbar.dart';
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

  setUp(() {
    state = ValueNotifier(TtsStateEnum.playing);
    actions = [];
  });
  tearDown(() => state.dispose());

  Future<void> mount(WidgetTester tester,
      {Locale locale = const Locale('zh'),
      double scale = 1,
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
            left: 12,
            right: 12,
            bottom: 24,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: TtsQuickToolbar(
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
      expect(find.text('回朗读页'), findsOneWidget);
      expect(find.text('此页开始'), findsOneWidget);
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
        'settings'
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
      'read-here'
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
    for (final name in ['previous', 'next', 'play-pause', 'settings']) {
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
    expect(tester.widget<TextButton>(key('return')).onPressed, isNull);
    // Stopping/starting the engine mid-operation preserves the busy guard.
    state.value = TtsStateEnum.stopped;
    await tester.pump();
    state.value = TtsStateEnum.playing;
    await tester.pump();
    expect(tester.widget<TextButton>(key('read-here')).onPressed, isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(key('read-here')).onPressed, isNotNull);
  });

  testWidgets('errors are reported and controls remain usable', (tester) async {
    await mount(tester, readHere: () async => throw StateError('failed'));
    await tester.tap(key('read-here'));
    await tester.pumpAndSettle();
    expect(find.text('朗读操作失败，请重试'), findsOneWidget);
    expect(tester.widget<TextButton>(key('read-here')).onPressed, isNotNull);
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
