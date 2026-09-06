import 'dart:io';
import 'dart:async';
import 'package:anx_reader/service/feedback/crash_diagnostics.dart';
import 'package:anx_reader/service/knowledge/index_build_marker.dart';
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

  Future<FileKnowledgeIndexStore> storeFor(Book book,
      {bool Function()? isCancelled}) async {
    final fingerprint = await sourceFingerprint(book);
    return FileKnowledgeIndexStore(indexFile(book.id),
        sourceFingerprint: fingerprint,
        isCancelled: isCancelled,
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
      if (await indexBuildMarker(indexFile(book.id)).exists()) return false;
      final source = await sourceFingerprint(book);
      final file = indexFile(book.id);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return false;
      final key =
          '${file.path}:$source:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
      if (_indexStatusCache.length > 64) _indexStatusCache.clear();
      return await (_indexStatusCache[key] ??=
          FileKnowledgeIndexStore(file, sourceFingerprint: source)
              .summary(book.id.toString())
              .then((summary) => summary != null));
    } on FileSystemException {
      return false;
    }
  }

  Future<BookKnowledgeIndexStatus> status(Book book) async {
    if (await indexBuildMarker(indexFile(book.id)).exists()) {
      return const BookKnowledgeIndexStatus(indexed: false);
    }
    final summary = await (await storeFor(book)).summary(book.id.toString());
    if (summary == null) {
      return const BookKnowledgeIndexStatus(indexed: false);
    }
    return BookKnowledgeIndexStatus(
      indexed: true,
      chunkCount: summary['chunkCount'] as int,
      vectorCount: summary['vectorCount'] as int,
    );
  }

  Future<IndexBuildResult> build(
    Book book, {
    IndexProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) =>
      withIndexBuildMarker(indexFile(book.id), () async {
        try {
          await CrashDiagnostics.recordIndexState(1);
          final result = await _build(book,
              onProgress: onProgress, isCancelled: isCancelled);
          await CrashDiagnostics.recordIndexState(
              result.status == IndexBuildStatus.cancelled ? 7 : 5);
          return result;
        } catch (_) {
          await CrashDiagnostics.recordIndexState(6);
          rethrow;
        }
      });

  Future<IndexBuildResult> _build(
    Book book, {
    IndexProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final store = await storeFor(book, isCancelled: isCancelled);
    var modelCode = 0;
    void progress(String stage, int done, int total) {
      final phase = stage.startsWith('@extract:')
          ? 1
          : stage.startsWith('@embedding')
              ? 3
              : 2;
      unawaited(CrashDiagnostics.recordIndexState(phase,
          done: done, total: total, model: modelCode));
      onProgress?.call(stage, done, total);
    }

    final chapters = await _chapterRepository.extractChaptersForIndex(
      book,
      onProgress: (chapterId, completed, total) {
        progress('@extract:$chapterId', completed, total);
      },
      isCancelled: isCancelled,
    );
    if (isCancelled?.call() ?? false) {
      return const IndexBuildResult(status: IndexBuildStatus.cancelled);
    }
    final embedding = EmbeddingProviderFactory.fromPrefs();
    modelCode = const {
          'all-MiniLM-L6-v2': 1,
          'bge-small-en-v1.5': 2,
          'bge-small-zh-v1.5': 3,
          'multilingual-e5-small': 4
        }[embedding?.modelId] ??
        0;
    try {
      return await KnowledgeIndexer(
        service: KnowledgeSearchService(),
        store: _DiagnosticIndexStore(store, modelCode),
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
        onProgress: progress,
        isCancelled: isCancelled,
        beforeSave: () async => await embedding?.release(),
      );
    } finally {
      await embedding?.release();
    }
  }

  Future<void> deleteIndex(Book book) async {
    final file = indexFile(book.id);
    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
    for (final suffix in ['.summary', '.summary.tmp']) {
      final metadata = File('${file.path}$suffix');
      if (await metadata.exists()) await metadata.delete();
    }
    final marker = indexBuildMarker(file);
    if (await marker.exists()) await marker.delete();
  }
}

class _DiagnosticIndexStore implements KnowledgeIndexStore {
  const _DiagnosticIndexStore(this.delegate, this.model);
  final KnowledgeIndexStore delegate;
  final int model;
  @override
  Future<KnowledgeIndexSnapshot?> load(String bookId) => delegate.load(bookId);
  @override
  Future<void> save(KnowledgeIndexSnapshot snapshot) async {
    await CrashDiagnostics.recordIndexState(4,
        done: snapshot.vectors.length,
        total: snapshot.chunks.length,
        model: model);
    await delegate.save(snapshot);
  }
}
