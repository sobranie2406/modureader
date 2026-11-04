import 'package:anx_reader/widgets/reading_page/document_comparison_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

class _Reader extends StatefulWidget {
  const _Reader({super.key});
  @override
  State<_Reader> createState() => _ReaderState();
}

class _ReaderState extends State<_Reader> {
  int value = 0;
  @override
  Widget build(BuildContext context) => SizedBox.expand(
      child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => value++),
          child: Text('$value')));
}

void main() {
  testWidgets(
      'portrait and landscape split evenly, retain both readers and route input',
      (tester) async {
    final original = GlobalKey<_ReaderState>();
    final reflow = GlobalKey<_ReaderState>();
    var originalInput = 0, reflowInput = 0;
    Future<void> show(Size size,
        {bool compare = true, bool showReflow = true}) async {
      tester.view.reset();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: DocumentComparisonView(
          compare: compare,
          onOriginalInteraction: () => originalInput++,
          onReflowInteraction: () => reflowInput++,
          original: _Reader(key: original),
          reflow: showReflow ? _Reader(key: reflow) : null,
        ),
      )));
      await tester.pump();
    }

    addTearDown(tester.view.reset);
    await show(const Size(400, 800));
    final originalState = original.currentState;
    final reflowState = reflow.currentState;
    var a = tester.getRect(find.byKey(original));
    var b = tester.getRect(find.byKey(reflow));
    expect(a, const Rect.fromLTWH(0, 0, 400, 388));
    expect(b, const Rect.fromLTWH(0, 412, 400, 388));
    await tester.tapAt(a.center);
    await tester.tapAt(b.center);
    await tester.pump();
    expect(originalInput, 1);
    expect(reflowInput, 1);
    expect(originalState!.value, 1);
    expect(reflowState!.value, 1);

    await show(const Size(800, 400));
    a = tester.getRect(find.byKey(original));
    b = tester.getRect(find.byKey(reflow));
    expect(a, const Rect.fromLTWH(0, 0, 388, 400));
    expect(b, const Rect.fromLTWH(412, 0, 388, 400));
    expect(original.currentState, same(originalState));
    expect(reflow.currentState, same(reflowState));

    await show(const Size(800, 400), compare: false);
    expect(tester.getRect(find.byKey(reflow)),
        const Rect.fromLTWH(0, 0, 800, 400));
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    expect(originalInput, 1);
    expect(reflowInput, 2);
    expect(original.currentState, same(originalState));
    expect(reflow.currentState, same(reflowState));

    await show(const Size(400, 800));
    expect(original.currentState!.value, 1);
    expect(reflow.currentState!.value, 2);
    await tester.sendEventToBinding(const PointerScrollEvent(
        position: Offset(100, 100), scrollDelta: Offset(0, 20)));
    expect(originalInput, 2);
    expect(reflowInput, 2);
    await show(const Size(400, 800), showReflow: false);
    expect(original.currentState, same(originalState));
    expect(tester.getRect(find.byKey(original)),
        const Rect.fromLTWH(0, 0, 400, 800));
    expect(tester.takeException(), isNull);
  });

  for (final horizontal in [false, true]) {
    testWidgets(
        '${horizontal ? 'horizontal' : 'vertical'} drag resizes without reader input, clamps and resets on exit',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize =
          horizontal ? const Size(800, 400) : const Size(400, 800);
      addTearDown(tester.view.reset);
      final original = GlobalKey<_ReaderState>();
      final reflow = GlobalKey<_ReaderState>();
      var input = 0;
      Future<void> show({bool compare = true, bool showReflow = true}) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: DocumentComparisonView(
              compare: compare,
              original: _Reader(key: original),
              reflow: showReflow ? _Reader(key: reflow) : null,
              onOriginalInteraction: () => input++,
              onReflowInteraction: () => input++,
            ),
          ),
        ));
      }

      double originalExtent() {
        final size = tester.getSize(find.byKey(original));
        return horizontal ? size.width : size.height;
      }

      final divider = find.byKey(const ValueKey('document-comparison-divider'));
      Future<void> drag(double delta) async {
        final gesture = await tester.startGesture(tester.getCenter(divider));
        // First movement wins the drag arena; the second resizes the panes.
        await gesture
            .moveBy(horizontal ? const Offset(25, 0) : const Offset(0, 25));
        await gesture.moveBy(horizontal ? Offset(delta, 0) : Offset(0, delta));
        await gesture.up();
        await tester.pump();
      }

      await show();
      final originalState = original.currentState;
      final reflowState = reflow.currentState;
      await drag(100);
      expect(originalExtent(), greaterThan(388));
      expect(originalExtent(), lessThan(776 * .8));
      expect(input, 0);
      expect(original.currentState, same(originalState));
      expect(reflow.currentState, same(reflowState));
      final resized = originalExtent();
      await show();
      expect(originalExtent(), resized);

      await drag(1000);
      expect(originalExtent(), closeTo(776 * .8, .01));
      await drag(-2000);
      expect(originalExtent(), closeTo(776 * .2, .01));
      expect(input, 0);

      await show(compare: false);
      expect(divider, findsNothing);
      await show();
      expect(originalExtent(), 388);
      await drag(100);
      await show(showReflow: false);
      await show();
      expect(originalExtent(), 388);

      await drag(100);
      await tester.pumpWidget(const SizedBox());
      await show();
      expect(originalExtent(), 388);
      expect(tester.takeException(), isNull);
    });
  }
}
