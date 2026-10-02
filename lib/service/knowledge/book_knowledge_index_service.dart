import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:anx_reader/service/knowledge/book_index_lock.dart';
import 'package:anx_reader/service/feedback/crash_diagnostics.dart';
import 'package:anx_reader/service/knowledge/index_build_marker.dart';
import 'package:anx_reader/service/knowledge/book_source_fingerprint.dart';
import 'package:anx_reader/service/knowledge/local_book_requirement.dart';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/ai/tools/repository/book_content_search_repository.dart';
import 'package:anx_reader/service/knowledge/embedding_provider.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/service/knowledge/knowledge_index_stream.dart';
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
  static Future<void> _legacyRecoveryTail = Future<void>.value();

  File indexFile(int bookId) => File(getBasePath('knowledge/$bookId.json'));

  Future<String> sourceFingerprint(Book book) => bookSourceFingerprint(book);

  Future<FileKnowledgeIndexStore> storeFor(Book book,
      {bool Function()? isCancelled}) async {
    final fingerprint = await sourceFingerprint(book);
    final legacy = await legacyBookSourceFingerprint(book);
    return FileKnowledgeIndexStore(indexFile(book.id),
        sourceFingerprint: fingerprint,
        sourceFingerprintAliases: [if (legacy != null) legacy],
        isCancelled: isCancelled,
        isSourceCurrent: () async =>
            await sourceFingerprint(book) == fingerprint);
  }

  Future<KnowledgeIndexSnapshot?> loadSnapshot(Book book) async {
    try {
      if (!await indexFile(book.id).exists()) return null;
      final store = await storeFor(book);
      final snapshot = await store.load(book.id.toString());
      if (snapshot != null) return snapshot;
      if (!await _recoverLegacy(book, store)) return null;
      return await store.load(book.id.toString());
    } on FileSystemException {
      return null;
    }
  }

  Future<bool> hasIndex(Book book) async {
    try {
      if (await indexBuildMarker(indexFile(book.id)).exists()) return false;
      final file = indexFile(book.id);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return false;
      final source = await sourceFingerprint(book);
      final key =
          '${file.path}:$source:${stat.size}:${stat.modified.microsecondsSinceEpoch}:${stat.changed.microsecondsSinceEpoch}';
      if (_indexStatusCache.length > 64) _indexStatusCache.clear();
      final result = await (_indexStatusCache[key] ??=
          _summaryFor(book).then((summary) => summary != null));
      // A transient unavailable WebView/storage must not permanently cache a
      // failed legacy check for the rest of this application's lifetime.
      if (!result) _indexStatusCache.remove(key);
      return result;
    } on FileSystemException {
      return false;
    }
  }

  Future<BookKnowledgeIndexStatus> status(Book book) async {
    if (await indexBuildMarker(indexFile(book.id)).exists()) {
      return const BookKnowledgeIndexStatus(indexed: false);
    }
    final summary = await _summaryFor(book);
    if (summary == null) {
      return const BookKnowledgeIndexStatus(indexed: false);
    }
    return BookKnowledgeIndexStatus(
      indexed: true,
      chunkCount: summary['chunkCount'] as int,
      vectorCount: summary['vectorCount'] as int,
    );
  }

  Future<Map<String, dynamic>?> _summaryFor(Book book) async {
    // An unindexed bookshelf tile must not read/hash the entire book.
    if (!await indexFile(book.id).exists()) return null;
    final store = await storeFor(book);
    final summary = await store.summary(book.id.toString());
    if (summary != null) return summary;
    if (!await _recoverLegacy(book, store)) return null;
    return store.summary(book.id.toString());
  }

  Future<bool> _recoverLegacy(Book book, FileKnowledgeIndexStore store) =>
      withBookIndexLock(book.id, () async {
        final prior = _legacyRecoveryTail;
        final done = Completer<void>();
        _legacyRecoveryTail = done.future;
        await prior;
        try {
          if (await indexBuildMarker(store.file).exists()) return false;
          if (await store.summary(book.id.toString()) != null) return true;
          final metadata =
              await readKnowledgeIndexMetadata(store.file, book.id.toString());
          if (metadata == null ||
              (metadata['sourceFingerprint'] as String?)
                      ?.startsWith('sha256:') ==
                  true) {
            return false;
          }
          // Old timestamp/path fingerprints cannot prove a copied book's
          // identity. Compare its locally extracted canonical chapter text.
          // Serialize these short-lived readers to avoid opening one per tile.
          final chapters =
              await _chapterRepository.extractChaptersForIndex(book);
          final hash = await Isolate.run(() => knowledgeContentHash(chapters));
          if (hash != metadata['contentHash'] ||
              await sourceFingerprint(book) != store.sourceFingerprint) {
            return false;
          }
          return await store.adoptVerifiedLegacy(book.id.toString(), hash);
        } on Object {
          // Keep the old file for retry/recovery; never delete it or mark a
          // corrupt/mismatched index complete just to suppress the badge.
          return false;
        } finally {
          done.complete();
        }
      });

  Future<IndexBuildResult> build(
    Book book, {
    IndexProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) =>
      withBookIndexLock(
          book.id,
          () => _buildLocked(book,
              onProgress: onProgress, isCancelled: isCancelled));

  Future<IndexBuildResult> _buildLocked(
    Book book, {
    IndexProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) {
      return const IndexBuildResult(status: IndexBuildStatus.cancelled);
    }
    // Recheck at execution time as well as at the menu entry: a queued file
    // may have been removed. Do this before markers, model loading or extraction.
    await requireLocalBookForIndexing(book);
    // Revalidate queued work before touching a previous index/build marker.
    await EmbeddingProviderFactory.validateForBook(book);
    return withIndexBuildMarker(indexFile(book.id), () async {
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
  }

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

    final embedding = EmbeddingProviderFactory.requireForBook(book);
    try {
      // Fail before expensive EPUB extraction when the chosen local model is
      // missing. Indexing never silently downloads models or marks partial work complete.
      await embedding.ensureReady();
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
      modelCode = const {
            'all-MiniLM-L6-v2': 1,
            'bge-small-en-v1.5': 2,
            'bge-small-zh-v1.5': 3,
            'multilingual-e5-small': 4
          }[embedding.modelId] ??
          0;
      return await KnowledgeIndexer(
        service: KnowledgeSearchService(),
        store: _DiagnosticIndexStore(store, modelCode),
      ).build(
        bookId: book.id.toString(),
        chapters: chapters,
        vectorizeBatch: (chunks) => embedding.embedBatchCancellable(
          chunks.map((chunk) => chunk.text).toList(growable: false),
          isCancelled: isCancelled,
        ),
        embeddingMode: embedding.mode,
        embeddingModelId: embedding.modelId,
        embeddingDimensions: embedding.configuredDimension,
        onProgress: progress,
        isCancelled: isCancelled,
        beforeSave: () async => await embedding.release(),
      );
    } finally {
      await embedding.release();
    }
  }

  Future<void> deleteIndex(Book book) => withBookIndexLock(book.id, () async {
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
      });
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
