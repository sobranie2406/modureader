import 'package:anx_reader/widgets/ai/ai_chat_scroll_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'output follows bottom but does not drag readers away from history',
      (tester) async {
    final controller = AiChatScrollController();
    var count = 30;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return NotificationListener<ScrollNotification>(
          onNotification: controller.handleNotification,
          child: ListView.builder(
              controller: controller,
              itemCount: count,
              itemExtent: 80,
              itemBuilder: (_, i) => Text('Message $i')));
    }))));
    controller.followAfterLayout(force: true);
    await tester.pumpAndSettle();
    expect(controller.position.extentAfter, 0);
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    final oldOffset = controller.offset;
    expect(controller.position.extentAfter, greaterThan(48));
    update(() => count += 10);
    controller.followAfterLayout();
    await tester.pumpAndSettle();
    expect(controller.offset, oldOffset);
    for (var i = 0; i < 10 && controller.position.extentAfter > 0; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
    }
    expect(controller.position.extentAfter, 0);
    update(() => count += 1);
    controller.followAfterLayout();
    controller.followAfterLayout();
    await tester.pumpAndSettle();
    expect(controller.position.extentAfter, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('a queued frame callback is safe after disposal', (tester) async {
    final controller = AiChatScrollController();
    controller.followAfterLayout(force: true);
    controller.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  Future<({AiChatScrollController controller, GlobalKey key})> mountReply(
      WidgetTester tester) async {
    final controller = AiChatScrollController();
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: NotificationListener<ScrollNotification>(
                onNotification: controller.handleNotification,
                child: ListView(controller: controller, children: [
                  const SizedBox(height: 300, child: Text('Previous messages')),
                  const SizedBox(height: 60, child: Text('Thinking and tools')),
                  SizedBox(
                      key: key, height: 1600, child: const Text('Reply start')),
                ])))));
    controller.followAfterLayout(force: true);
    await tester.pumpAndSettle();
    return (controller: controller, key: key);
  }

  testWidgets('completion reveals this reply, not the top of the conversation',
      (tester) async {
    final f = await mountReply(tester);
    expect(f.controller.position.extentAfter, 0);
    f.controller.followAfterLayout(); // Last token can already be queued.
    f.controller.returnToReplyStartAfterLayout(f.key);
    await tester.pumpAndSettle();
    expect(f.controller.offset, closeTo(360, 1));
    expect(tester.getTopLeft(find.byKey(f.key)).dy,
        closeTo(tester.getTopLeft(find.byType(ListView)).dy, 1));
    f.controller.followAfterLayout();
    await tester.pumpAndSettle();
    expect(f.controller.offset, closeTo(360, 1),
        reason:
            'late output must not pull the completed answer back to its end');
    await tester.pumpWidget(const SizedBox());
    f.controller.dispose();
  });

  testWidgets('completion preserves a reader who scrolled up during generation',
      (tester) async {
    final f = await mountReply(tester);
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    final offset = f.controller.offset;
    f.controller.returnToReplyStartAfterLayout(f.key);
    await tester.pumpAndSettle();
    expect(f.controller.offset, offset);
    await tester.pumpWidget(const SizedBox());
    f.controller.dispose();
  });

  testWidgets('starting another reply invalidates a queued completion jump',
      (tester) async {
    final f = await mountReply(tester);
    f.controller.returnToReplyStartAfterLayout(f.key);
    f.controller.followAfterLayout(force: true);
    await tester.pumpAndSettle();
    expect(f.controller.position.extentAfter, 0);
    await tester.pumpWidget(const SizedBox());
    f.controller.dispose();
  });

  testWidgets('missing anchors and disposed completion callbacks are safe',
      (tester) async {
    final f = await mountReply(tester);
    f.controller.returnToReplyStartAfterLayout(GlobalKey());
    await tester.pumpAndSettle();
    expect(f.controller.position.extentAfter, 0);
    f.controller.followAfterLayout(force: true);
    f.controller.returnToReplyStartAfterLayout(f.key);
    await tester.pumpWidget(const SizedBox());
    f.controller.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
