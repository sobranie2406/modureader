import 'dart:io';
import 'dart:async';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/knowledge/book_embedding_preferences.dart';
import 'package:anx_reader/service/knowledge/embedding_provider.dart';
import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final book = Book.mock().copyWith(filePath: 'file/one.epub');
  final other = book.copyWith(id: 2, filePath: 'file/two.epub');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('unset and reset choices follow changing global defaults', () async {
    expect(BookEmbeddingPreferences.choiceFor(book), isNull);
    expect(
        EmbeddingProviderFactory.fromBook(book)?.modelId, 'bge-small-zh-v1.5');
    Prefs().vectorLocalModelId = 'all-MiniLM-L6-v2';
    expect(
        EmbeddingProviderFactory.fromBook(book)?.modelId, 'all-MiniLM-L6-v2');
    await BookEmbeddingPreferences.save(book, 'local:bge-small-en-v1.5');
    await BookEmbeddingPreferences.save(book, null);
    expect(
        EmbeddingProviderFactory.fromBook(book)?.modelId, 'all-MiniLM-L6-v2');
  });

  test('each of four local models overrides only its own book and persists',
      () async {
    for (final model in LocalEmbeddingModels.all) {
      await BookEmbeddingPreferences.save(book, 'local:${model.id}');
      await Prefs().initPrefs();
      final provider = EmbeddingProviderFactory.fromBook(book)!;
      expect(provider.modelId, model.id);
      expect(provider.configuredDimension, model.dimensions);
      expect(EmbeddingProviderFactory.fromBook(other)?.modelId,
          'bge-small-zh-v1.5');
      expect(Prefs().vectorLocalModelId, 'bge-small-zh-v1.5');
    }
  });

  test('file identity survives row remapping without leaking to a reused id',
      () async {
    await BookEmbeddingPreferences.save(book, 'local:multilingual-e5-small');
    expect(BookEmbeddingPreferences.choiceFor(book.copyWith(id: 99)),
        'local:multilingual-e5-small');
    expect(BookEmbeddingPreferences.choiceFor(other.copyWith(id: book.id)),
        isNull);
  });

  test(
      'remote references current settings; per-book data contains no credentials',
      () async {
    await Prefs().saveVectorModelConfig(
        {'modelId': 'remote-one', 'apiKey': 'fixture-only'});
    await BookEmbeddingPreferences.save(book, 'remote');
    final provider = EmbeddingProviderFactory.fromBook(book)!;
    expect(provider.mode, 'remote');
    expect(provider.modelId, 'remote-one');
    provider.close();
    expect(Prefs().prefs.getString(BookEmbeddingPreferences.keyFor(book)),
        'remote');
    await Prefs().saveVectorModelConfig({'modelId': 'remote-two'});
    final changed = EmbeddingProviderFactory.fromBook(book)!;
    expect(changed.modelId, 'remote-two');
    changed.close();
  });

  test('global off stays off even with explicit per-book choice', () async {
    await BookEmbeddingPreferences.save(book, 'local:all-MiniLM-L6-v2');
    Prefs().vectorModelEnabled = false;
    expect(EmbeddingProviderFactory.fromBook(book), isNull);
  });

  test('unknown selection does not silently substitute a different model',
      () async {
    await expectLater(BookEmbeddingPreferences.save(book, 'local:missing'),
        throwsArgumentError);
    await Prefs()
        .prefs
        .setString(BookEmbeddingPreferences.keyFor(book), 'local:missing');
    expect(() => EmbeddingProviderFactory.fromBook(book), throwsStateError);
  });

  test('same dimension but different model or mode cannot query an old index',
      () async {
    await BookEmbeddingPreferences.save(book, 'local:all-MiniLM-L6-v2');
    final provider = EmbeddingProviderFactory.fromBook(book)!;
    bool matches(String? id, {String mode = 'builtin', int size = 384}) =>
        matchesEmbeddingIndex(provider,
            modelId: id, mode: mode, dimensions: size);
    expect(matches('all-MiniLM-L6-v2'), isTrue);
    expect(matches('bge-small-en-v1.5'), isFalse);
    expect(matches('all-MiniLM-L6-v2', mode: 'remote'), isFalse);
    expect(matches('all-MiniLM-L6-v2', size: 512), isFalse);
    expect(matches(null), isFalse);
  });

  test('queue builder, reader builder and AI query all resolve per-book models',
      () {
    for (final path in [
      'lib/service/knowledge/book_knowledge_index_service.dart',
      'lib/page/book_player/epub_player.dart',
      'lib/providers/ai_chat.dart'
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('EmbeddingProviderFactory.fromBook(book)'));
      expect(source, isNot(contains('EmbeddingProviderFactory.fromPrefs()')));
    }
    expect(File('lib/widgets/bookshelf/book_item.dart').readAsStringSync(),
        matches(RegExp(r'showBookEmbeddingModelDialog\(\s*context,\s*book\)')));
  });

  test('queued books resolve different overrides without changing the default',
      () async {
    await BookEmbeddingPreferences.save(book, 'local:all-MiniLM-L6-v2');
    await BookEmbeddingPreferences.save(other, 'local:multilingual-e5-small');
    final firstGate = Completer<void>();
    final secondDone = Completer<void>();
    final models = <String>[];
    final queue =
        BookKnowledgeIndexQueue(worker: (current, progress, cancelled) async {
      models.add(EmbeddingProviderFactory.fromBook(current)!.modelId);
      if (current.id == book.id) {
        await firstGate.future;
      } else {
        secondDone.complete();
      }
      return const IndexBuildResult(status: IndexBuildStatus.completed);
    });
    queue.enqueue(book);
    queue.enqueue(other);
    expect(models, ['all-MiniLM-L6-v2']);
    firstGate.complete();
    await secondDone.future;
    await Future<void>.delayed(Duration.zero);
    expect(models, ['all-MiniLM-L6-v2', 'multilingual-e5-small']);
    expect(Prefs().vectorLocalModelId, 'bge-small-zh-v1.5');
    queue.dispose();
  });
}
