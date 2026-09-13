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
}
