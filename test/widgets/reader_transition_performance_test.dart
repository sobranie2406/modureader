import 'dart:math' as math;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/widgets/page_router/reading_route.dart';
import 'package:anx_reader/widgets/page_router/reader_cover_hero.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('cover flight does not duplicate or reparent reader',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final readerKey = GlobalKey();
    var mounts = 0;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: Scaffold(
        body: SizedBox(
            width: 100,
            height: 150,
            child: Hero(
                tag: 'cover',
                createRectTween: readerCoverRectTween,
                child: const Text('shelf cover'))),
      ),
    ));
    navigator.currentState!.push(readingRoute<void>(
      animate: true,
      builder: (_) => ReaderCoverHero(
        tag: 'cover',
        cover: const Text('flight cover'),
        child: SizedBox.expand(
            key: readerKey, child: _MountCounter(onMount: () => mounts++)),
      ),
    ));
    await tester.pump();
    final original = readerKey.currentContext;
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('flight cover'), findsOneWidget);
    expect(mounts, 1);
    expect(readerKey.currentContext, same(original));
    await tester.pump(const Duration(milliseconds: 400));
    final turning = tester.widget<Transform>(
        find.byKey(const ValueKey('reader-cover-spine-turn')));
    expect(turning.transform.entry(0, 0), inExclusiveRange(0, 1));
    expect(mounts, 1);
    await tester.pumpAndSettle();
    expect(find.text('flight cover'), findsNothing);
    expect(readerKey.currentContext, same(original));
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('flight cover'), findsOneWidget);
    expect(mounts, 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.all());

  testWidgets('opening mounts the reader before cover expansion and turn',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    var mounts = 0;
    await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Text('library')));
    final route = readingRoute<void>(
      animate: true,
      builder: (_) => _MountCounter(onMount: () => mounts++),
    );
    expect(route, isA<PageRoute<void>>());
    expect((route as PageRoute).transitionDuration,
        const Duration(milliseconds: 720));
    navigator.currentState!.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(mounts, 1);
    expect(route.animation!.status, AnimationStatus.forward);
    await tester.pumpAndSettle();
    expect(mounts, 1);
    expect(find.text('reader'), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (widget) => widget is HeroMode && !widget.enabled),
        findsNothing);
    // A popup and its reverse transition must not recreate the native reader.
    final context = tester.element(find.text('reader'));
    showReaderPopup(context, builder: (_) => const Text('AI'));
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(mounts, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('library'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.all());

  test('cover grows completely before turning, closes before shrinking', () {
    const shelf = Rect.fromLTWH(30, 100, 100, 150);
    const reader = Rect.fromLTWH(0, 0, 400, 800);
    final opening = ReaderCoverRectTween(begin: shelf, end: reader);
    final closing = ReaderCoverRectTween(begin: reader, end: shelf);
    expect(opening.lerp(0), shelf);
    expect(opening.lerp(0.3)!.width, inExclusiveRange(100, 400));
    expect(opening.lerp(0.55), reader);
    expect(opening.lerp(0.9), reader);
    expect(closing.lerp(0.3), reader);
    expect(closing.lerp(1), shelf);
    for (final t in [0.0, 0.2, 0.55, 0.8, 1.0]) {
      expect(
          closing.lerp(1 - t)!.left, closeTo(opening.lerp(t)!.left, 0.00001));
    }
  });

  testWidgets(
      'window resize during flight preserves the reader and final layout',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final navigator = GlobalKey<NavigatorState>();
    final readerKey = GlobalKey();
    var mounts = 0;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(
            body: SizedBox(
                width: 100,
                height: 150,
                child: Hero(tag: 'resize', child: Text('shelf'))))));
    navigator.currentState!.push(readingRoute<void>(
        animate: true,
        builder: (_) => ReaderCoverHero(
            tag: 'resize',
            cover: const Text('cover'),
            child: SizedBox.expand(
                key: readerKey,
                child: _MountCounter(onMount: () => mounts++)))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final original = readerKey.currentContext;
    tester.view.physicalSize = const Size(1200, 700);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(mounts, 1);
    expect(readerKey.currentContext, same(original));
    expect(tester.getSize(find.byKey(readerKey)), const Size(1200, 700));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('shelf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.all());

  testWidgets('cover turns from spine and reverses without changing its child',
      (tester) async {
    final progress = AnimationController(vsync: tester, value: 0.3);
    addTearDown(progress.dispose);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ReaderCoverTurn(
          animation: progress, child: const Text('cached cover')),
    ));
    Transform cover() => tester.widget<Transform>(
        find.byKey(const ValueKey('reader-cover-spine-turn')));
    expect(cover().transform.entry(0, 0), 1);
    progress.value = 0.775;
    await tester.pump();
    expect(cover().alignment, Alignment.centerLeft);
    // The free edge comes out of the page, not into the reader.
    expect(cover().transform.entry(2, 0), lessThan(0));
    expect(
        cover().transform.entry(0, 0),
        closeTo(math.cos(math.pi / 2 * Curves.easeInOutCubic.transform(0.5)),
            0.001));
    progress.value = 1;
    await tester.pump();
    expect(find.text('cached cover'), findsNothing);
    progress.value = 0.55;
    await tester.pump();
    expect(find.text('cached cover'), findsOneWidget);
    expect(cover().transform.entry(0, 0), 1);
  });

  testWidgets('iOS edge swipe cancels or closes the cover without remounting',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    final readerKey = GlobalKey();
    var mounts = 0;
    await tester.pumpWidget(CupertinoApp(
      navigatorKey: navigator,
      home: const CupertinoPageScaffold(
          child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                  width: 100,
                  height: 150,
                  child: Hero(
                      tag: 'swipe',
                      transitionOnUserGestures: true,
                      child: Text('shelf'))))),
    ));
    final route = readingRoute<void>(
        animate: true,
        builder: (_) => ReaderCoverHero(
              tag: 'swipe',
              cover: const Text('flight cover'),
              child: SizedBox.expand(
                  key: readerKey,
                  child: _MountCounter(onMount: () => mounts++)),
            )) as PageRoute<void>;
    navigator.currentState!.push(route);
    await tester.pumpAndSettle();
    final original = readerKey.currentContext;
    expect(route.popGestureEnabled, isTrue);
    // A short, slow swipe cancels; the reader remains mounted throughout.
    final cancel = await tester.startGesture(const Offset(1, 300));
    await cancel.moveBy(const Offset(180, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(route.popGestureInProgress, isTrue);
    expect(find.text('flight cover'), findsOneWidget);
    expect(readerKey.currentContext, same(original));
    expect(tester.getTopLeft(find.byKey(readerKey)), Offset.zero);
    await tester.pump(const Duration(milliseconds: 500));
    await cancel.up();
    await tester.pumpAndSettle();
    expect(route.isCurrent, isTrue);
    expect(find.text('flight cover'), findsNothing);
    expect(mounts, 1);
    expect(readerKey.currentContext, same(original));
    // A long swipe completes the pop with the same cover animation.
    final close = await tester.startGesture(const Offset(1, 300));
    await close.moveBy(const Offset(650, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await close.up();
    await tester.pumpAndSettle();
    expect(find.text('reader'), findsNothing);
    expect(find.text('shelf'), findsOneWidget);
    expect(mounts, 1);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('closing during opening does not recreate the reader',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    var mounts = 0;
    await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Text('library')));
    navigator.currentState!.push(readingRoute<void>(
      animate: true,
      builder: (_) => _MountCounter(onMount: () => mounts++),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(mounts, 1);
    expect(find.text('reader'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.all());

  for (final eink in [false, true]) {
    testWidgets('no delay for disabled opening animation (eink=$eink)',
        (tester) async {
      Prefs().eInkMode = eink;
      final navigator = GlobalKey<NavigatorState>();
      var mounts = 0;
      await tester.pumpWidget(
          MaterialApp(navigatorKey: navigator, home: const Text('library')));
      final route = readingRoute<void>(
        animate: eink,
        builder: (_) => _MountCounter(onMount: () => mounts++),
      );
      expect((route as PageRoute).transitionDuration, Duration.zero);
      navigator.currentState!.push(route);
      await tester.pump();
      expect(mounts, 1);
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.all());
  }

  for (final size in [const Size(400, 900), const Size(900, 400)]) {
    testWidgets('popup consumes keyboard inset once at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final controller = TextEditingController(text: 'keep draft');
      addTearDown(controller.dispose);
      var childBuilds = 0;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showReaderPopup(context,
                        builder: (_) => Builder(builder: (context) {
                              childBuilds++;
                              expect(
                                  MediaQuery.viewInsetsOf(context).bottom, 0);
                              return Scaffold(
                                  body: Column(children: [
                                const Expanded(child: Text('messages')),
                                SizedBox(
                                    height: 48,
                                    key: const ValueKey('composer'),
                                    child: TextField(controller: controller)),
                              ]));
                            })),
                    child: const Text('open'),
                  ),
                )),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final initialBuilds = childBuilds;
      for (final inset in [80.0, 160.0, 220.0, 100.0, 0.0]) {
        tester.view.viewInsets = FakeViewPadding(bottom: inset);
        await tester.pump();
        await tester.pump();
        expect(tester.getBottomRight(find.byKey(const ValueKey('composer'))).dy,
            closeTo(size.height - inset, 1));
        expect(controller.text, 'keep draft');
        expect(tester.takeException(), isNull);
      }
      // Keyboard metrics relayout the panel without rebuilding its content
      // through an inherited, already-consumed viewInsets subscription.
      expect(childBuilds, initialBuilds);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _MountCounter extends StatefulWidget {
  const _MountCounter({required this.onMount});
  final VoidCallback onMount;
  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('reader');
}
