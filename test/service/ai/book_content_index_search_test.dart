import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/ai/tools/book_content_search_tool.dart';
import 'package:anx_reader/service/ai/tools/input/book_content_search_input.dart';
import 'package:anx_reader/service/ai/tools/repository/book_content_search_repository.dart';
import 'package:anx_reader/service/ai/tools/repository/books_repository.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_retriever.dart';
import 'package:flutter_test/flutter_test.dart';

import '../knowledge/book_knowledge_retriever_test.dart'
    show TestEmbedding, testSnapshot;

class _Books extends BooksRepository {
  @override
  Future<Map<int, Book>> fetchByIds(Iterable<int> ids) async =>
      {1: Book.mock()};
}

class _FallbackRepository extends BookContentSearchRepository {
  _FallbackRepository(BookKnowledgeRetriever retriever)
      : super(booksRepository: _Books(), knowledgeRetriever: retriever);

  int fallbackCalls = 0;
  @override
  Future<Map<String, dynamic>> searchFullText(
      Book book, BookContentSearchInput input) async {
    fallbackCalls++;
    return {'source': 'full_text', 'bookId': book.id, 'keyword': input.keyword};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('AI tool uses semantic index without opening reader/WebView', () async {
    final embedding = TestEmbedding();
    final tool = BookContentSearchTool(BookContentSearchRepository(
        booksRepository: _Books(),
        knowledgeRetriever: BookKnowledgeRetriever(
            loadSnapshot: (_) async => testSnapshot(),
            embeddingFactory: (_) => embedding)));
    final response = await tool.run(const BookContentSearchInput(
        bookId: 1, keyword: 'photosynthesis', maxResults: 1, maxSnippets: 1));
    expect(response['source'], 'local_index');
    expect(response['bookId'], 1);
    expect(response['completed'], true);
    final results = response['results'] as List;
    expect(results, hasLength(1));
    expect(results.single['chapterId'], 'chapter-a');
    expect(results.single['snippets'].single['text'], contains('sunlight'));
    expect(embedding.calls, 1);
  });

  test('AI tool rejects an unknown book before accessing another index',
      () async {
    final tool = BookContentSearchTool(BookContentSearchRepository(
        booksRepository: _Books(),
        knowledgeRetriever: BookKnowledgeRetriever(
            loadSnapshot: (_) => throw StateError('must not load'))));
    await expectLater(
        tool.run(const BookContentSearchInput(bookId: 99, keyword: 'x')),
        throwsStateError);
  });

  test('missing, broken or nonmatching index falls back to same book full text',
      () async {
    for (final KnowledgeSnapshotLoader loader in [
      (_) async => null,
      (_) async => throw const FormatException('broken'),
      (_) async => testSnapshot(),
    ]) {
      final repository = _FallbackRepository(BookKnowledgeRetriever(
          loadSnapshot: loader, embeddingFactory: (_) => null));
      final response = await BookContentSearchTool(repository)
          .run(const BookContentSearchInput(bookId: 1, keyword: 'no-match'));
      expect(response['source'], 'full_text');
      expect(response['bookId'], 1);
      expect(repository.fallbackCalls, 1);
    }
  });
}
