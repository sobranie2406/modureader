import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/widgets/ai/tool_tiles/mindmap_step_tile.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphview/GraphView.dart';
import 'package:shared_preferences/shared_preferences.dart';

MindmapNodeData node(String id, [List<MindmapNodeData> children = const []]) =>
    MindmapNodeData(id: id, label: id, children: children);

MindmapPayload fixture() => MindmapPayload(
    title: '测试导图',
    outline: '',
    root: node('root', [
      node('branch', [
        node('nested', [node('leaf')])
      ]),
      node('sibling')
    ]));

Widget app(MindmapPayload payload) => MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        ...GlobalMaterialLocalizations.delegates
      ],
      home: Scaffold(body: SafeArea(child: MindmapViewer(payload: payload))),
    );

Finder key(String value) => find.byKey(ValueKey(value));
TransformationController transform(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!;
GraphView graph(WidgetTester tester) =>
    tester.widget<GraphView>(find.byType(GraphView));

void expectFits(WidgetTester tester) {
  final viewRect = tester.getRect(key('mindmap-canvas'));
  final bounds = graph(tester).graph.calculateGraphBounds();
  expect(bounds.topLeft, Offset.zero,
      reason: 'left branches must remain inside the hit-testable render box');
  final transformed =
      MatrixUtils.transformRect(transform(tester).value, bounds);
  expect(transformed.left, greaterThanOrEqualTo(15));
  expect(transformed.top, greaterThanOrEqualTo(15));
  expect(transformed.right, lessThanOrEqualTo(viewRect.width - 15));
  expect(transformed.bottom, lessThanOrEqualTo(viewRect.height - 15));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    final fatal = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = fatal);
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test(
      'folding filters only the visible graph, preserving the full source tree',
      () {
    final payload = fixture();
    final folded =
        MindmapGraphBundle.fromPayload(payload, collapsedIds: {'branch'});
    expect(folded.lookup.keys, unorderedEquals(['root', 'branch', 'sibling']));
    expect(folded.lookup['branch']!.children.single.id, 'nested');
    expect(MindmapGraphBundle.fromPayload(payload).lookup.length, 5);
    expect(
        MindmapGraphBundle.fromPayload(payload, collapsedIds: {'root'})
            .lookup
            .keys,
        ['root']);
  });

  testWidgets(
      'only one gesture surface; zoom buttons preserve the viewport center',
      (tester) async {
    await tester.pumpWidget(app(fixture()));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expectFits(tester);
    final center = tester.getSize(key('mindmap-canvas')).center(Offset.zero);
    final before = transform(tester).toScene(center);
    final scale = transform(tester).value.getMaxScaleOnAxis();
    await tester.tap(key('mindmap-zoom-in'));
    await tester.pumpAndSettle();
    expect(transform(tester).value.getMaxScaleOnAxis(),
        closeTo(scale * 1.25, 0.00001));
    expect(
        (transform(tester).toScene(center) - before).distance, lessThan(.001));
    await tester.tap(key('mindmap-zoom-out'));
    await tester.pumpAndSettle();
    expect(transform(tester).value.getMaxScaleOnAxis(), closeTo(scale, .00001));
    await tester.tap(key('mindmap-fit'));
    await tester.pumpAndSettle();
    expectFits(tester);
  });

  testWidgets(
      'branch taps collapse and expand, preserving nested collapse and tap position',
      (tester) async {
    await tester.pumpWidget(app(fixture()));
    await tester.pumpAndSettle();
    await tester.tap(key('mindmap-node-nested'));
    await tester.pumpAndSettle();
    expect(find.text('leaf'), findsNothing);
    final center = tester.getCenter(key('mindmap-node-branch'));
    await tester.tap(key('mindmap-node-branch'));
    await tester.pumpAndSettle();
    expect(find.text('nested'), findsNothing);
    expect(find.text('sibling'), findsOneWidget);
    expect((tester.getCenter(key('mindmap-node-branch')) - center).distance,
        lessThan(1));
    await tester.tap(key('mindmap-node-branch'));
    await tester.pumpAndSettle();
    expect(find.text('nested'), findsOneWidget);
    expect(find.text('leaf'), findsNothing);
    await tester.tap(key('mindmap-expand-all'));
    await tester.pumpAndSettle();
    expect(find.text('leaf'), findsOneWidget);
    await tester.tap(key('mindmap-collapse-all'));
    await tester.pumpAndSettle();
    expect(graph(tester).graph.nodeCount(), 1);
    await tester.tap(key('mindmap-node-root'));
    await tester.pumpAndSettle();
    expect(find.text('branch'), findsOneWidget);
    expect(find.text('nested'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'mouse drag, wheel and two-finger pinch manipulate the same transform',
      (tester) async {
    await tester.pumpWidget(app(fixture()));
    await tester.pumpAndSettle();
    final canvas = tester.getRect(key('mindmap-canvas'));
    final start = canvas.topLeft + const Offset(30, 30);
    final before = transform(tester).value.clone();
    final mouse =
        await tester.startGesture(start, kind: PointerDeviceKind.mouse);
    await mouse.moveBy(const Offset(25, 0));
    await tester.pump();
    await mouse.moveBy(const Offset(90, 40));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(transform(tester).value, isNot(before));
    final scale = transform(tester).value.getMaxScaleOnAxis();
    await tester.sendEventToBinding(PointerScrollEvent(
        position: canvas.center,
        scrollDelta: const Offset(0, -80),
        kind: PointerDeviceKind.mouse));
    await tester.pumpAndSettle();
    expect(transform(tester).value.getMaxScaleOnAxis(), greaterThan(scale));
    final wheelScale = transform(tester).value.getMaxScaleOnAxis();
    final one = await tester.startGesture(canvas.center - const Offset(40, 0),
        pointer: 1);
    final two = await tester.startGesture(canvas.center + const Offset(40, 0),
        pointer: 2);
    await tester.pump();
    await one.moveBy(const Offset(-50, 0));
    await two.moveBy(const Offset(50, 0));
    await tester.pump();
    await one.moveBy(const Offset(-30, 0));
    await two.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(
        transform(tester).value.getMaxScaleOnAxis(), greaterThan(wheelScale));
    await one.up();
    await two.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'full screen shares folds but owns layout; Escape returns without losing the map',
      (tester) async {
    await tester.pumpWidget(app(fixture()));
    await tester.pumpAndSettle();
    final inlineGraph = graph(tester).graph;
    await tester.tap(key('mindmap-node-branch'));
    await tester.pumpAndSettle();
    await tester.tap(key('mindmap-fullscreen'));
    await tester.pumpAndSettle();
    expect(key('mindmap-fullscreen-page'), findsOneWidget);
    expect(key('mindmap-fullscreen'), findsNothing);
    expect(find.text('nested'), findsNothing);
    expect(graph(tester).graph, isNot(same(inlineGraph)));
    expectFits(tester);
    await tester.tap(key('mindmap-expand-all'));
    await tester.pumpAndSettle();
    expect(find.text('leaf'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(key('mindmap-fullscreen-page'), findsNothing);
    expect(find.text('leaf'), findsOneWidget);
    await tester.tap(key('mindmap-fullscreen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'no disposed/shared controller after reopening');
  });

  testWidgets(
      'large map fits after phone/tablet rotation with no toolbar overflow',
      (tester) async {
    final payload = MindmapPayload(
        title: 'large',
        outline: '',
        root: node('root',
            List.generate(20, (i) => node('branch$i', [node('leaf$i')]))));
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(app(payload));
    for (final size in [
      const Size(320, 640),
      const Size(1280, 800),
      const Size(800, 1280)
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expectFits(tester);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'new payload resets stale folds and pending callbacks are safe on disposal',
      (tester) async {
    await tester.pumpWidget(app(fixture()));
    await tester.pumpAndSettle();
    await tester.tap(key('mindmap-collapse-all'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(fixture()));
    await tester.pumpAndSettle();
    expect(find.text('leaf'), findsOneWidget);
    await tester.tap(key('mindmap-node-root'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('zoom limits stay finite and a single-node map remains usable',
      (tester) async {
    await tester.pumpWidget(
        app(MindmapPayload(title: 'single', outline: '', root: node('root'))));
    await tester.pumpAndSettle();
    expectFits(tester);
    transform(tester).value = Matrix4.diagonal3Values(5, 5, 5);
    await tester.tap(key('mindmap-zoom-in'));
    await tester.pumpAndSettle();
    expect(transform(tester).value.getMaxScaleOnAxis(), 5);
    transform(tester).value = Matrix4.diagonal3Values(.01, .01, .01);
    await tester.tap(key('mindmap-zoom-out'));
    await tester.pumpAndSettle();
    expect(transform(tester).value.getMaxScaleOnAxis(), .01);
    await tester.tap(key('mindmap-fit'));
    await tester.pumpAndSettle();
    expectFits(tester);
    await tester.tap(key('mindmap-node-root'));
    await tester.pumpAndSettle();
    expect(graph(tester).graph.nodeCount(), 1);
    expect(tester.takeException(), isNull);
  });
}
