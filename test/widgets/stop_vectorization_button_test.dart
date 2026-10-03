import 'dart:async';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/widgets/bookshelf/stop_vectorization_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final compact in [false, true]) {
    testWidgets('stop entry compact=$compact cancels and waits for cleanup',
        (tester) async {
      final gate = Completer<void>();
      late bool Function() cancelled;
      final queue =
          BookKnowledgeIndexQueue(worker: (book, progress, isCancelled) async {
        cancelled = isCancelled;
        await gate.future;
        return const IndexBuildResult(status: IndexBuildStatus.cancelled);
      });
      addTearDown(queue.dispose);
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: StopVectorizationButton(
            compact: compact,
            queue: queue,
            onStop: () {
              taps++;
              return queue.cancelAll();
            }),
      )));
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      expect(taps, 0);
      queue.enqueue(Book.mock());
      await tester.pump();
      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await tester.pump();
      expect(taps, 1);
      expect(cancelled(), isTrue);
      if (compact) {
        expect(find.byTooltip('Stopping…'), findsOneWidget);
      } else {
        expect(find.text('Stopping…'), findsOneWidget);
      }
      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      expect(taps, 1);
      gate.complete();
      await tester.pumpAndSettle();
      expect(queue.activeItems, isEmpty);
      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
