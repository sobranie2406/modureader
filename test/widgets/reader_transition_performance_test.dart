import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/widgets/page_router/reading_route.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('Android transition mounts the reader only after animation ends',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    var mounts = 0;
    await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Text('library')));
    final route = readingRoute<void>(
      animate: true,
      deferReaderUntilTransition: true,
      openingPlaceholder: const Text('cover'),
      builder: (_) => _MountCounter(onMount: () => mounts++),
    );
    navigator.currentState!.push(route);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(mounts, 0);
    expect(find.text('cover'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(mounts, 1);
    expect(find.text('reader'), findsOneWidget);
    expect(tester.widget<HeroMode>(find.byType(HeroMode).last).enabled, false);
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
  });

  testWidgets('closing during opening never creates a late reader',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    var mounts = 0;
    await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Text('library')));
    navigator.currentState!.push(readingRoute<void>(
      animate: true,
      deferReaderUntilTransition: true,
      builder: (_) => _MountCounter(onMount: () => mounts++),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(mounts, 0);
    expect(tester.takeException(), isNull);
  });

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
        deferReaderUntilTransition: true,
        builder: (_) => _MountCounter(onMount: () => mounts++),
      );
      expect((route as PageRoute).transitionDuration, Duration.zero);
      navigator.currentState!.push(route);
      await tester.pump();
      expect(mounts, 1);
      await tester.pumpAndSettle();
    });
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
