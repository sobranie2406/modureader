import 'package:modu_reader/widgets/common/app_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScrollbarPainter painter(WidgetTester tester, Finder bar) => tester
      .widgetList<CustomPaint>(
          find.descendant(of: bar, matching: find.byType(CustomPaint)))
      .map((w) => w.foregroundPainter)
      .whereType<ScrollbarPainter>()
      .first;
  Widget app(Widget child,
          {TargetPlatform platform = TargetPlatform.android,
          bool reduceMotion = false}) =>
      MaterialApp(
        theme: ThemeData(platform: platform),
        scrollBehavior: const AppScrollBehavior(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: child!),
        home: Scaffold(body: child),
      );

  for (final platform in TargetPlatform.values) {
    testWidgets('$platform shows on scroll, drags, then hides', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var changed = false;
      await tester.pumpWidget(app(
          ListView.builder(
              controller: controller,
              itemCount: 100,
              itemExtent: 60,
              itemBuilder: (_, i) => SwitchListTile(
                  value: false,
                  title: Text('Row $i'),
                  onChanged: (_) => changed = true)),
          platform: platform));
      final bar = find.byType(RawScrollbar);
      expect(bar, findsOneWidget);
      final paint = painter(tester, bar);
      expect(paint.fadeoutOpacityAnimation.value, 0);
      final config = tester.widget<RawScrollbar>(bar);
      expect(config.thumbColor!.a, closeTo(.46, .01));
      expect(config.thumbVisibility, false);
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(paint.fadeoutOpacityAnimation.value, greaterThan(0));
      final rect = tester.getRect(bar);
      Offset? thumb;
      for (var y = 4.0; y < rect.height; y += 2) {
        final point = Offset(rect.width - 6, y);
        if (paint.hitTestOnlyThumbInteractive(
            point, PointerDeviceKind.stylus)) {
          thumb = rect.topLeft + point;
          break;
        }
      }
      expect(thumb, isNotNull);
      final before = controller.offset;
      final gesture =
          await tester.startGesture(thumb!, kind: PointerDeviceKind.stylus);
      await tester.pump();
      await gesture.moveBy(const Offset(0, 130));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(controller.offset, greaterThan(before + 100));
      expect(changed, false);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 200));
      expect(paint.fadeoutOpacityAnimation.value, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('nested and dialog lists each use their own controller',
      (tester) async {
    await tester.pumpWidget(app(Builder(
        builder: (context) => ListView(children: [
              TextButton(
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                          content: SizedBox(
                              height: 200,
                              width: 300,
                              child: ListView(
                                  children: List.generate(
                                      40, (i) => Text('Dialog $i')))))),
                  child: const Text('Open')),
              SizedBox(
                  height: 200,
                  child: ListView(
                      children: List.generate(40, (i) => Text('Inner $i')))),
              const SizedBox(height: 1500),
            ]))));
    await tester.drag(find.byType(ListView).last, const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final bars =
        tester.widgetList<RawScrollbar>(find.byType(RawScrollbar)).toList();
    expect(bars.length, 3);
    expect(bars.map((b) => b.controller).toSet().length, 3);
    await tester.drag(find.byType(ListView).last, const Offset(0, -70));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'horizontal lists still scroll without bars; page views have none',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(Column(children: [
      SizedBox(
          height: 100,
          child: ListView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              children: const [SizedBox(width: 1600)])),
      Expanded(child: PageView(children: const [Text('A'), Text('B')])),
    ])));
    expect(find.byType(RawScrollbar), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    expect(find.byType(RawScrollbar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('side-by-side primary lists do not share scrollbar gestures',
      (tester) async {
    await tester.pumpWidget(app(Row(children: [
      for (var i = 0; i < 2; i++)
        Expanded(
            child: ListView(children: List.generate(80, (j) => Text('$i-$j')))),
    ])));
    await tester.drag(find.byType(ListView).first, const Offset(0, -80));
    await tester.pumpAndSettle();
    final bars =
        tester.widgetList<RawScrollbar>(find.byType(RawScrollbar)).toList();
    expect(bars.first.controller!.offset, greaterThan(0));
    expect(bars.last.controller!.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'E-Ink has no fade animation and short content has no visible thumb',
      (tester) async {
    await tester.pumpWidget(
        app(ListView(children: const [Text('Short')]), reduceMotion: true));
    final bar = find.byType(RawScrollbar);
    expect(tester.widget<RawScrollbar>(bar).fadeDuration, Duration.zero);
    await tester.pumpAndSettle();
    expect(
        painter(tester, bar)
            .hitTestInteractive(const Offset(790, 20), PointerDeviceKind.touch),
        false);
    expect(tester.takeException(), isNull);
  });
}
