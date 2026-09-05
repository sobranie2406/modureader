import 'dart:io';
import 'package:anx_reader/service/knowledge/book_source_fingerprint.dart';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/ai/tools/repository/book_content_search_repository.dart';
import 'package:anx_reader/service/knowledge/embedding_provider.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';

class BookKnowledgeIndexStatus {
  const BookKnowledgeIndexStatus({
    required this.indexed,
    this.chunkCount = 0,
    this.vectorCount = 0,
  });

  final bool indexed;
  final int chunkCount;
  final int vectorCount;
}

/// Builds and inspects persisted hybrid-search indexes for bookshelf books.
class BookKnowledgeIndexService {
  BookKnowledgeIndexService({BookContentSearchRepository? chapterRepository})
      : _chapterRepository = chapterRepository ?? BookContentSearchRepository();

  final BookContentSearchRepository _chapterRepository;
  static final _indexStatusCache = <String, Future<bool>>{};

  File indexFile(int bookId) => File(getBasePath('knowledge/$bookId.json'));

  Future<String> sourceFingerprint(Book book) => bookSourceFingerprint(book);

  Future<FileKnowledgeIndexStore> storeFor(Book book) async {
    final fingerprint = await sourceFingerprint(book);
    return FileKnowledgeIndexStore(indexFile(book.id),
        sourceFingerprint: fingerprint,
        isSourceCurrent: () async =>
            await sourceFingerprint(book) == fingerprint);
  }

  Future<KnowledgeIndexSnapshot?> loadSnapshot(Book book) async {
    try {
      return await (await storeFor(book)).load(book.id.toString());
    } on FileSystemException {
      return null;
    }
  }

  Future<bool> hasIndex(Book book) async {
    try {
      final source = await sourceFingerprint(book);
      final file = indexFile(book.id);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return false;
      final key =
          '${file.path}:$source:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
      if (_indexStatusCache.length > 64) _indexStatusCache.clear();
      return await (_indexStatusCache[key] ??=
          FileKnowledgeIndexStore(file, sourceFingerprint: source)
              .load(book.id.toString())
              .then((snapshot) => snapshot != null));
    } on FileSystemException {
      return false;
    }
  }

  Future<BookKnowledgeIndexStatus> status(Book book) async {
    final snapshot = await loadSnapshot(book);
    if (snapshot == null) {
      return const BookKnowledgeIndexStatus(indexed: false);
    }
    return BookKnowledgeIndexStatus(
      indexed: true,
      chunkCount: snapshot.chunks.length,
      vectorCount: snapshot.vectors.length,
    );
  }

  Future<IndexBuildResult> build(
    Book book, {
    IndexProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final store = await storeFor(book);
    final chapters = await _chapterRepository.extractChaptersForIndex(
      book,
      onProgress: (chapterId, completed, total) {
        onProgress?.call('@extract:$chapterId', completed, total);
      },
      isCancelled: isCancelled,
    );
    if (isCancelled?.call() ?? false) {
      return const IndexBuildResult(status: IndexBuildStatus.cancelled);
    }
    final embedding = EmbeddingProviderFactory.fromPrefs();
    try {
      return await KnowledgeIndexer(
        service: KnowledgeSearchService(),
        store: store,
      ).build(
        bookId: book.id.toString(),
        chapters: chapters,
        vectorizeBatch: embedding == null
            ? null
            : (chunks) => embedding.embedBatchCancellable(
                  chunks.map((chunk) => chunk.text).toList(growable: false),
                  isCancelled: isCancelled,
                ),
        embeddingMode: embedding?.mode,
        embeddingModelId: embedding?.modelId,
        embeddingDimensions: embedding?.configuredDimension,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } finally {
      embedding?.close();
    }
  }

  Future<void> deleteIndex(Book book) async {
    final file = indexFile(book.id);
    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
  }
}
