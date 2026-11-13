import 'dart:async';

import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/knowledge/book_knowledge_retriever.dart';
import 'package:modu_reader/service/knowledge/embedding_provider.dart';
import 'package:modu_reader/service/knowledge/knowledge_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class TestEmbedding extends EmbeddingProvider {
  TestEmbedding({this.modelId = 'test-model', this.fail = false});
  @override
  final String modelId;
  final bool fail;
  int calls = 0;
  int releases = 0;
  List<String>? inputs;
  @override
  String get mode => 'local';
  @override
  int get configuredDimension => 2;
  @override
  Future<List<List<double>>> embedBatch(List<String> inputs) async {
    this.inputs = inputs;
    calls++;
    if (fail) throw StateError('unavailable');
    return inputs.map((_) => [1.0, 0.0]).toList();
  }

  @override
  Future<void> release() async {
    releases++;
  }
}

class BuiltinEmbedding extends TestEmbedding {
  @override
  String get mode => 'builtin';
}

class SlowEmbedding extends TestEmbedding {
  final pending = Completer<List<List<double>>>();
  final released = Completer<void>();
  bool closed = false;

  @override
  Future<List<List<double>>> embedBatch(List<String> inputs) => pending.future;

  @override
  void close() => closed = true;

  @override
  Future<void> release() async {
    releases++;
    released.complete();
  }
}

KnowledgeIndexSnapshot testSnapshot() {
  const relevant = KnowledgeChunk(
      id: '1:chapter-a:0',
      bookId: '1',
      chapterId: 'chapter-a',
      text: 'Plants convert sunlight into energy.');
  const other = KnowledgeChunk(
      id: '1:chapter-b:0',
      bookId: '1',
      chapterId: 'chapter-b',
      text: 'Historical events in winter.');
  return KnowledgeIndexSnapshot(
      bookId: '1',
      contentHash: 'test',
      chunks: [relevant, other],
      vectors: [
        VectorEntry(chunk: relevant, vector: [1, 0]),
        VectorEntry(chunk: other, vector: [0, 1]),
      ],
      embeddingMode: 'local',
      embeddingModelId: 'test-model',
      embeddingDimensions: 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('local vector preprocessing is bounded but lexical query stays complete',
      () async {
    final provider = BuiltinEmbedding();
    final original = testSnapshot();
    final snapshot = KnowledgeIndexSnapshot(
        bookId: original.bookId,
        contentHash: original.contentHash,
        chunks: original.chunks,
        vectors: original.vectors,
        embeddingMode: 'builtin',
        embeddingModelId: provider.modelId,
        embeddingDimensions: 2);
    final query = '${List.filled(5000, '😀').join()} winter';
    final results = await BookKnowledgeRetriever(
        loadSnapshot: (_) async => snapshot,
        embeddingFactory: (_) => provider).search(Book.mock(), query);
    expect(provider.inputs!.single.runes.length, 4096);
    expect(provider.inputs!.single, List.filled(4096, '😀').join());
    expect(results.first.chunk.chapterId, 'chapter-b');
  });
  test('slow index times out without starting late embedding', () async {
    final pending = Completer<KnowledgeIndexSnapshot?>();
    final provider = TestEmbedding();
    final retriever = BookKnowledgeRetriever(
        loadSnapshot: (_) => pending.future, embeddingFactory: (_) => provider);
    expect(
        await retriever.search(Book.mock(), 'sunlight',
            timeBudget: const Duration(milliseconds: 10)),
        isEmpty);
    pending.complete(testSnapshot());
    await Future<void>.delayed(Duration.zero);
    expect(provider.calls, 0);
    expect(provider.releases, 0);
  });

  test('slow embedding is cancelled and released after retrieval deadline',
      () async {
    final provider = SlowEmbedding();
    final retriever = BookKnowledgeRetriever(
        loadSnapshot: (_) async => testSnapshot(),
        embeddingFactory: (_) => provider);
    expect(
        await retriever.search(Book.mock(), 'sunlight',
            timeBudget: const Duration(milliseconds: 10)),
        isEmpty);
    await provider.released.future.timeout(const Duration(seconds: 2));
    expect(provider.closed, isTrue);
    expect(provider.releases, 1);
    provider.pending.completeError(StateError('late network failure'));
    await Future<void>.delayed(Duration.zero);
  });

  test('cancelled request never reads index', () async {
    final retriever = BookKnowledgeRetriever(
        loadSnapshot: (_) => throw StateError('must not load'));
    expect(
        await retriever.search(Book.mock(), 'sunlight',
            isCancelled: () => true),
        isEmpty);
  });
  test('semantic-only query uses stored vectors and releases query provider',
      () async {
    final provider = TestEmbedding();
    final retriever = BookKnowledgeRetriever(
        loadSnapshot: (_) async => testSnapshot(),
        embeddingFactory: (_) => provider);
    final results = await retriever.search(Book.mock(), 'photosynthesis');
    expect(results.single.chunk.chapterId, 'chapter-a');
    expect(provider.calls, 1);
    expect(provider.releases, 1);
    final context = knowledgeContextFor(results)!;
    expect(context, contains('Plants convert sunlight'));
    expect(context, contains('chapter-a'));
    expect(context, isNot(contains('Historical events')));
    expect(context, contains('不代表完整章节或全书'));
  });

  test('different model with equal dimensions uses lexical results only',
      () async {
    final provider = TestEmbedding(modelId: 'different-model');
    final retriever = BookKnowledgeRetriever(
        loadSnapshot: (_) async => testSnapshot(),
        embeddingFactory: (_) => provider);
    expect(
        (await retriever.search(Book.mock(), 'winter')).single.chunk.chapterId,
        'chapter-b');
    expect(await retriever.search(Book.mock(), 'photosynthesis'), isEmpty);
    expect(provider.calls, 0);
    expect(provider.releases, 0);
  });

  test('unavailable model falls back to lexical evidence', () async {
    final provider = TestEmbedding(fail: true);
    final results = await BookKnowledgeRetriever(
        loadSnapshot: (_) async => testSnapshot(),
        embeddingFactory: (_) => provider).search(Book.mock(), 'winter');
    expect(results.single.chunk.chapterId, 'chapter-b');
    expect(provider.releases, 1);
  });

  test('missing/corrupt/foreign index cannot fabricate evidence', () async {
    for (final KnowledgeSnapshotLoader loader in [
      (_) async => null,
      (_) async => throw const FormatException('invalid index'),
      (_) async => testSnapshot(),
    ]) {
      final retriever = BookKnowledgeRetriever(
          loadSnapshot: loader,
          embeddingFactory: (_) => throw StateError('must not create a model'));
      expect(await retriever.search(Book.mock().copyWith(id: 2), 'sunlight'),
          isEmpty);
    }
    expect(knowledgeContextFor([]), isNull);
  });

  test('deleted books and blank queries never load private index data',
      () async {
    final retriever = BookKnowledgeRetriever(
        loadSnapshot: (_) => throw StateError('must not load'));
    expect(await retriever.search(Book.mock().copyWith(isDeleted: true), 'a'),
        isEmpty);
    expect(await retriever.search(Book.mock(), ' '), isEmpty);
  });
}
