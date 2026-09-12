import 'dart:async';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/knowledge/book_embedding_preferences.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/widgets/bookshelf/book_embedding_model_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final book = Book.mock().copyWith(filePath: 'file/dialog.epub');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  Future<void> open(WidgetTester tester,
      {BookKnowledgeIndexQueue? queue}) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        BookEmbeddingModelDialog(book: book, queue: queue)),
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('choose a local model, save, reopen and reset to default',
      (tester) async {
    await open(tester);
    expect(
        tester
            .widget<RadioListTile<String>>(
                find.byType(RadioListTile<String>).first)
            .groupValue,
        '');
    await tester.tap(find.text('all-MiniLM-L6-v2'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(BookEmbeddingPreferences.choiceFor(book), 'local:all-MiniLM-L6-v2');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用默认模型'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(BookEmbeddingPreferences.choiceFor(book), isNull);
  });
  testWidgets('cancel leaves both per-book and global settings unchanged',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('all-MiniLM-L6-v2'));
    await tester.pump();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(BookEmbeddingPreferences.choiceFor(book), isNull);
    expect(Prefs().vectorLocalModelId, 'bge-small-zh-v1.5');
  });
  testWidgets(
      'job starting while dialog is open disables model changes and save',
      (tester) async {
    final gate = Completer<void>();
    final queue = BookKnowledgeIndexQueue(worker: (_, __, ___) async {
      await gate.future;
      return const IndexBuildResult(status: IndexBuildStatus.completed);
    });
    await open(tester, queue: queue);
    queue.enqueue(book);
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNull);
    for (final radio in tester.widgetList<RadioListTile<String>>(
        find.byType(RadioListTile<String>))) {
      expect(radio.onChanged, isNull);
    }
    gate.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    queue.dispose();
  });
}
