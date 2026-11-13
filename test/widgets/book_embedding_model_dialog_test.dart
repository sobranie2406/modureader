import 'dart:async';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/knowledge/book_embedding_preferences.dart';
import 'package:modu_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:modu_reader/service/knowledge/knowledge_engine.dart';
import 'package:modu_reader/widgets/bookshelf/book_embedding_model_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>).first)
            .groupValue,
        '');
    await tester.tap(find.text('all-MiniLM-L6-v2'));
    await tester.pumpAndSettle();
    expect(BookEmbeddingPreferences.choiceFor(book), 'local:all-MiniLM-L6-v2');
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用默认模型'));
    await tester.pumpAndSettle();
    expect(BookEmbeddingPreferences.choiceFor(book), isNull);
  });
  testWidgets(
      'closing preserves the book choice without changing global settings',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('all-MiniLM-L6-v2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(BookEmbeddingPreferences.choiceFor(book), 'local:all-MiniLM-L6-v2');
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
    expect(find.text('保存'), findsNothing);
    for (final radio in tester.widgetList<RadioListTile<String>>(
        find.byType(RadioListTile<String>))) {
      expect(radio.enabled, isFalse);
    }
    gate.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    queue.dispose();
  });
}
