import 'dart:io';

import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/service/knowledge/knowledge_chapter_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chunks content without losing source locations', () {
    const content = '第一段内容。\n\n第二段内容。\n\n第三段内容。';
    final chunks = TextChunker(maxCharacters: 8).chunk(
      bookId: 'book-1',
      chapterId: 'chapter-1',
      content: content,
    );

    expect(chunks, hasLength(3));
    expect(chunks.every((chunk) => chunk.bookId == 'book-1'), isTrue);
    expect(chunks.every((chunk) => chunk.chapterId == 'chapter-1'), isTrue);
    expect(chunks.map((chunk) => chunk.startOffset), [0, 8, 16]);
  });

  test('hybrid search combines lexical and vector relevance', () {
    const chunks = [
      KnowledgeChunk(id: 'a', bookId: 'b', chapterId: 'c', text: '苹果和梨子'),
      KnowledgeChunk(id: 'b', bookId: 'b', chapterId: 'c', text: '火车穿过山谷'),
    ];
    final lexical = Bm25Index(chunks).search('苹果');
    final vector = VectorIndex([
      VectorEntry(chunk: chunks[1], vector: [1, 0]),
      VectorEntry(chunk: chunks[0], vector: [0, 1]),
    ]).search([1, 0]);
    final result = HybridSearch().merge(lexical, vector);

    expect(result.first.chunk.id, 'a');
    expect(result, hasLength(2));
  });

  test('local text embedding is deterministic and normalized', () {
    const embedding = LocalTextEmbedding();
    final first = embedding.encode('苹果和梨子');
    final second = embedding.encode('苹果和梨子');

    expect(first, second);
    expect(first, hasLength(256));
    final squaredNorm = first.fold<double>(0, (sum, x) => sum + x * x);
    expect(squaredNorm, closeTo(1, 0.000001));
  });

  test('knowledge service rebuilds by content hash and filters by book', () {
    final service = KnowledgeSearchService();
    final first = service.rebuild(
      bookId: 'book-1',
      chapters: const {
        'chapter-1': '苹果树在春天开花。',
        'chapter-2': '火车穿过山谷。',
      },
    );
    service.rebuild(
      bookId: 'book-2',
      chapters: const {'chapter-1': '苹果派需要烤箱。'},
    );

    expect(service.isCurrent('book-1', first.contentHash), isTrue);
    expect(service.isCurrent('book-1', 'changed'), isFalse);
    expect(service.search('苹果', bookId: 'book-1'), hasLength(1));
    expect(service.search('苹果', bookId: 'book-2'), hasLength(1));
  });

  test('knowledge index snapshots survive saving and restoring', () async {
    final file = File(
      '${Directory.systemTemp.path}/modu-knowledge-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });

    final source = KnowledgeSearchService();
    final snapshot = source.rebuild(
      bookId: 'book-1',
      chapters: const {'chapter-1': '这是一段可以恢复的内容。'},
    );
    final store = FileKnowledgeIndexStore(file);
    await store.save(snapshot);

    final restored = KnowledgeSearchService();
    expect(await restored.restore('book-1', store), isTrue);
    expect(restored.isCurrent('book-1', snapshot.contentHash), isTrue);
    expect(restored.search('恢复', bookId: 'book-1'), hasLength(1));
  });

  test('indexer reports progress and can cancel before persistence', () async {
    final directory = await Directory.systemTemp.createTemp('modu-indexer-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileKnowledgeIndexStore(
      File('${directory.path}/book.json'),
    );
    final service = KnowledgeSearchService();
    final progress = <String>[];
    final indexer = KnowledgeIndexer(service: service, store: store);

    final result = await indexer.build(
      bookId: 'book-1',
      chapters: const {
        'chapter-1': 'first chapter',
        'chapter-2': 'second chapter',
      },
      vectorize: (chunk) => const LocalTextEmbedding().encode(chunk.text),
      onProgress: (chapterId, completed, total) {
        progress.add('$chapterId:$completed/$total');
      },
    );

    expect(result.status, IndexBuildStatus.completed);
    expect(progress, ['chapter-1:1/2', 'chapter-2:2/2']);
    expect(await store.load('book-1'), isNotNull);
    final snapshot = result.snapshot!;
    expect(snapshot.vectors, hasLength(snapshot.chunks.length));

    final cancelled = await indexer.build(
      bookId: 'book-2',
      chapters: const {'chapter-1': 'cancel me'},
      isCancelled: () => true,
    );
    expect(cancelled.status, IndexBuildStatus.cancelled);
    expect(await store.load('book-2'), isNull);
  });

  test('indexer persists async embedding provenance', () async {
    final directory = await Directory.systemTemp.createTemp('modu-vector-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileKnowledgeIndexStore(File('${directory.path}/book.json'));
    final indexer = KnowledgeIndexer(
      service: KnowledgeSearchService(),
      store: store,
    );

    final result = await indexer.build(
      bookId: 'book-remote',
      chapters: const {'chapter-1': 'first\n\nsecond'},
      vectorizeBatch: (chunks) async => chunks
          .map((chunk) => [chunk.text.length.toDouble(), 1.0])
          .toList(growable: false),
      embeddingMode: 'remote',
      embeddingModelId: 'embedding-model',
      embeddingDimensions: 2,
    );

    final snapshot = result.snapshot!;
    expect(snapshot.vectors, hasLength(snapshot.chunks.length));
    expect(snapshot.embeddingMode, 'remote');
    expect(snapshot.embeddingModelId, 'embedding-model');
    expect(snapshot.embeddingDimensions, 2);
    final restored = await store.load('book-remote');
    expect(restored?.embeddingModelId, 'embedding-model');
  });

  test('chapter source flattens toc and loads content in reading order',
      () async {
    final source = KnowledgeChapterSource(
      const [
        KnowledgeChapterRef(id: 'one', title: '第一章', href: 'one.xhtml'),
        KnowledgeChapterRef(
          id: 'two',
          title: '第二章',
          href: 'two.xhtml',
          children: [
            KnowledgeChapterRef(id: 'two-a', title: '2.1', href: 'two-a.xhtml'),
          ],
        ),
      ],
      (href, {maxCharacters}) async => 'content:$href',
    );

    expect(await source.load(), {
      'one': 'content:one.xhtml',
      'two': 'content:two.xhtml',
      'two-a': 'content:two-a.xhtml',
    });
  });
}
