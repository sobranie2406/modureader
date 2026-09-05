import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

class KnowledgeChunk {
  const KnowledgeChunk({
    required this.id,
    required this.bookId,
    required this.chapterId,
    required this.text,
    this.startOffset = 0,
  });

  final String id;
  final String bookId;
  final String chapterId;
  final String text;
  final int startOffset;
}

class TextChunker {
  const TextChunker({this.maxCharacters = 800});

  final int maxCharacters;

  List<KnowledgeChunk> chunk({
    required String bookId,
    required String chapterId,
    required String content,
  }) {
    if (content.trim().isEmpty) return const [];
    final paragraphs = content.split(RegExp(r'\n\s*\n'));
    final result = <KnowledgeChunk>[];
    var offset = 0;
    var index = 0;
    for (final paragraph in paragraphs) {
      final text = paragraph.trim();
      if (text.isNotEmpty) {
        for (var start = 0; start < text.length; start += maxCharacters) {
          final end = math.min(start + maxCharacters, text.length);
          result.add(KnowledgeChunk(
            id: '$bookId:$chapterId:$index',
            bookId: bookId,
            chapterId: chapterId,
            text: text.substring(start, end),
            startOffset: offset + start,
          ));
          index++;
        }
      }
      offset += paragraph.length + 2;
    }
    return result;
  }
}

class SearchResult {
  const SearchResult({required this.chunk, required this.score});

  final KnowledgeChunk chunk;
  final double score;
}

List<String> _tokens(String input) {
  final words =
      input.toLowerCase().split(RegExp(r'[^\p{L}\p{N}]+', unicode: true));
  final result = <String>[];
  for (final word in words) {
    if (word.isEmpty) continue;
    if (word.runes.length > 1 && word.runes.every((rune) => rune > 0x2e80)) {
      result.addAll(word.runes.map(String.fromCharCode));
    } else {
      result.add(word);
    }
  }
  return result;
}

/// Small deterministic local embedding used for offline book indexing.
///
/// Tokens are feature-hashed into a fixed-size normalized vector, so indexing
/// does not require sending book content to a remote embedding service.
class LocalTextEmbedding {
  const LocalTextEmbedding({this.dimensions = 256});

  final int dimensions;

  List<double> encode(String input) {
    if (dimensions <= 0) {
      throw ArgumentError.value(dimensions, 'dimensions', 'must be positive');
    }
    final vector = List<double>.filled(dimensions, 0);
    for (final token in _tokens(input)) {
      var hash = 2166136261;
      for (final codeUnit in token.codeUnits) {
        hash ^= codeUnit;
        hash = (hash * 16777619) & 0xffffffff;
      }
      final index = hash % dimensions;
      final sign = (hash & 0x80000000) == 0 ? 1.0 : -1.0;
      vector[index] += sign;
    }
    final norm = math.sqrt(vector.fold<double>(0, (sum, x) => sum + x * x));
    if (norm == 0) return vector;
    return vector.map((value) => value / norm).toList(growable: false);
  }
}

class Bm25Index {
  Bm25Index(Iterable<KnowledgeChunk> chunks)
      : _chunks = List.unmodifiable(chunks);

  final List<KnowledgeChunk> _chunks;

  List<SearchResult> search(String query) {
    final queryTokens = _tokens(query).toSet();
    if (queryTokens.isEmpty) return const [];
    final scored = <SearchResult>[];
    for (final chunk in _chunks) {
      final tokens = _tokens(chunk.text);
      final score = queryTokens.fold<double>(0, (sum, token) {
        return sum + tokens.where((value) => value == token).length;
      });
      if (score > 0) scored.add(SearchResult(chunk: chunk, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }
}

class VectorEntry {
  const VectorEntry({required this.chunk, required this.vector});

  final KnowledgeChunk chunk;
  final List<double> vector;
}

class VectorIndex {
  VectorIndex(Iterable<VectorEntry> entries)
      : _entries = List.unmodifiable(entries);

  final List<VectorEntry> _entries;

  List<SearchResult> search(List<double> query) {
    final scored = <SearchResult>[];
    for (final entry in _entries) {
      if (entry.vector.length != query.length) continue;
      final denominator = _norm(entry.vector) * _norm(query);
      final score =
          denominator == 0 ? 0.0 : _dot(entry.vector, query) / denominator;
      if (score > 0) scored.add(SearchResult(chunk: entry.chunk, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored;
  }

  double _dot(List<double> left, List<double> right) =>
      List.generate(left.length, (i) => left[i] * right[i])
          .fold(0, (a, b) => a + b);

  double _norm(List<double> vector) => math.sqrt(_dot(vector, vector));
}

class HybridSearch {
  List<SearchResult> merge(
    List<SearchResult> lexical,
    List<SearchResult> vector, {
    double lexicalWeight = 0.7,
    double vectorWeight = 0.3,
  }) {
    final maxLexical = lexical.isEmpty ? 1 : lexical.first.score;
    final maxVector = vector.isEmpty ? 1 : vector.first.score;
    final scores = <String, double>{};
    final chunks = <String, KnowledgeChunk>{};
    for (final result in lexical) {
      scores[result.chunk.id] = (scores[result.chunk.id] ?? 0) +
          lexicalWeight * result.score / maxLexical;
      chunks[result.chunk.id] = result.chunk;
    }
    for (final result in vector) {
      scores[result.chunk.id] = (scores[result.chunk.id] ?? 0) +
          vectorWeight * result.score / maxVector;
      chunks[result.chunk.id] = result.chunk;
    }
    final result = scores.entries
        .map((entry) =>
            SearchResult(chunk: chunks[entry.key]!, score: entry.value))
        .toList();
    result.sort((a, b) => b.score.compareTo(a.score));
    return result;
  }
}

class KnowledgeIndexSnapshot {
  const KnowledgeIndexSnapshot({
    required this.bookId,
    required this.contentHash,
    required this.chunks,
    required this.vectors,
    this.embeddingMode,
    this.embeddingModelId,
    this.embeddingDimensions,
    this.sourceFingerprint,
  });

  final String bookId;
  final String contentHash;
  final List<KnowledgeChunk> chunks;
  final List<VectorEntry> vectors;
  final String? embeddingMode;
  final String? embeddingModelId;
  final int? embeddingDimensions;
  final String? sourceFingerprint;

  Map<String, dynamic> toJson() => {
        'bookId': bookId,
        'contentHash': contentHash,
        if (sourceFingerprint != null) 'sourceFingerprint': sourceFingerprint,
        'chunks': chunks
            .map((chunk) => {
                  'id': chunk.id,
                  'bookId': chunk.bookId,
                  'chapterId': chunk.chapterId,
                  'text': chunk.text,
                  'startOffset': chunk.startOffset,
                })
            .toList(growable: false),
        'vectors': vectors
            .map((entry) => {
                  'chunkId': entry.chunk.id,
                  'vector': entry.vector,
                })
            .toList(growable: false),
        if (embeddingMode != null) 'embeddingMode': embeddingMode,
        if (embeddingModelId != null) 'embeddingModelId': embeddingModelId,
        if (embeddingDimensions != null)
          'embeddingDimensions': embeddingDimensions,
      };

  factory KnowledgeIndexSnapshot.fromJson(Map<String, dynamic> json) {
    final chunks = (json['chunks'] as List<dynamic>? ?? const []).map((value) {
      final item = Map<String, dynamic>.from(value as Map);
      return KnowledgeChunk(
        id: item['id'] as String,
        bookId: item['bookId'] as String,
        chapterId: item['chapterId'] as String,
        text: item['text'] as String,
        startOffset: item['startOffset'] as int? ?? 0,
      );
    }).toList(growable: false);
    final byId = {for (final chunk in chunks) chunk.id: chunk};
    final vectors = (json['vectors'] as List<dynamic>? ?? const [])
        .map((value) {
          final item = Map<String, dynamic>.from(value as Map);
          final chunk = byId[item['chunkId'] as String];
          if (chunk == null) return null;
          return VectorEntry(
            chunk: chunk,
            vector: (item['vector'] as List<dynamic>)
                .map((number) => (number as num).toDouble())
                .toList(growable: false),
          );
        })
        .whereType<VectorEntry>()
        .toList(growable: false);
    return KnowledgeIndexSnapshot(
      bookId: json['bookId'] as String,
      contentHash: json['contentHash'] as String,
      sourceFingerprint: json['sourceFingerprint'] as String?,
      chunks: chunks,
      vectors: vectors,
      embeddingMode: json['embeddingMode'] as String?,
      embeddingModelId: json['embeddingModelId'] as String?,
      embeddingDimensions: (json['embeddingDimensions'] as num?)?.toInt(),
    );
  }
}

abstract interface class KnowledgeIndexStore {
  Future<void> save(KnowledgeIndexSnapshot snapshot);

  Future<KnowledgeIndexSnapshot?> load(String bookId);
}

class FileKnowledgeIndexStore implements KnowledgeIndexStore {
  const FileKnowledgeIndexStore(this.file,
      {this.sourceFingerprint, this.isSourceCurrent});

  final File file;
  final String? sourceFingerprint;
  final Future<bool> Function()? isSourceCurrent;

  @override
  Future<void> save(KnowledgeIndexSnapshot snapshot) async {
    if (isSourceCurrent != null && !await isSourceCurrent!()) {
      throw StateError('书籍文件已变更，请使用新文件重新建立索引。');
    }
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
        jsonEncode({
          ...snapshot.toJson(),
          if (sourceFingerprint != null) 'sourceFingerprint': sourceFingerprint,
        }),
        flush: true);
    if (isSourceCurrent != null && !await isSourceCurrent!()) {
      await temporary.delete();
      throw StateError('书籍文件已变更，请重新建立索引。');
    }
    await temporary.rename(file.path);
  }

  @override
  Future<KnowledgeIndexSnapshot?> load(String bookId) async {
    if (!await file.exists()) return null;
    try {
      final path = file.path;
      // Vector files can be large. Parsing them must not block reading frames.
      final snapshot = await Isolate.run(() async {
        final json = jsonDecode(await File(path).readAsString());
        return KnowledgeIndexSnapshot.fromJson(
            Map<String, dynamic>.from(json as Map));
      });
      if (snapshot.bookId != bookId) return null;
      if (sourceFingerprint != null &&
          snapshot.sourceFingerprint != sourceFingerprint) return null;
      return snapshot;
    } on Object {
      return null;
    }
  }
}

/// In-memory index coordinator. Persistence and embedding downloads can be
/// layered on top without changing the search contract.
class KnowledgeSearchService {
  final Map<String, KnowledgeIndexSnapshot> _indexes = {};

  KnowledgeIndexSnapshot rebuild({
    required String bookId,
    required Map<String, String> chapters,
    List<double> Function(KnowledgeChunk chunk)? vectorize,
  }) {
    final chunks = <KnowledgeChunk>[];
    final canonical = StringBuffer();
    for (final entry in chapters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))) {
      canonical
        ..write(entry.key)
        ..write('\u0000')
        ..write(entry.value)
        ..write('\u0001');
      chunks.addAll(TextChunker().chunk(
        bookId: bookId,
        chapterId: entry.key,
        content: entry.value,
      ));
    }

    final vectors = vectorize == null
        ? const <VectorEntry>[]
        : chunks
            .map((chunk) => VectorEntry(chunk: chunk, vector: vectorize(chunk)))
            .toList(growable: false);
    final snapshot = KnowledgeIndexSnapshot(
      bookId: bookId,
      contentHash: sha256.convert(utf8.encode(canonical.toString())).toString(),
      chunks: List.unmodifiable(chunks),
      vectors: vectors,
    );
    _indexes[bookId] = snapshot;
    return snapshot;
  }

  bool isCurrent(String bookId, String contentHash) =>
      _indexes[bookId]?.contentHash == contentHash;

  KnowledgeIndexSnapshot? snapshot(String bookId) => _indexes[bookId];

  void putSnapshot(KnowledgeIndexSnapshot snapshot) {
    _indexes[snapshot.bookId] = snapshot;
  }

  Future<void> save(String bookId, KnowledgeIndexStore store) async {
    final snapshot = _indexes[bookId];
    if (snapshot == null) return;
    await store.save(snapshot);
  }

  Future<bool> restore(String bookId, KnowledgeIndexStore store) async {
    final snapshot = await store.load(bookId);
    if (snapshot == null) return false;
    _indexes[bookId] = snapshot;
    return true;
  }

  List<SearchResult> search(
    String query, {
    String? bookId,
    List<double>? queryVector,
    int limit = 8,
  }) {
    final snapshots = bookId == null
        ? _indexes.values
        : [_indexes[bookId]].whereType<KnowledgeIndexSnapshot>();
    final chunks = snapshots.expand((snapshot) => snapshot.chunks).toList();
    final lexical = Bm25Index(chunks).search(query);
    if (queryVector == null) {
      return lexical.take(limit).toList(growable: false);
    }

    final vectors = snapshots
        .expand((snapshot) => snapshot.vectors)
        .toList(growable: false);
    return HybridSearch()
        .merge(lexical, VectorIndex(vectors).search(queryVector))
        .take(limit)
        .toList(growable: false);
  }
}

enum IndexBuildStatus { completed, cancelled }

class IndexBuildResult {
  const IndexBuildResult({required this.status, this.snapshot});

  final IndexBuildStatus status;
  final KnowledgeIndexSnapshot? snapshot;
}

typedef IndexProgressCallback = void Function(
  String chapterId,
  int completed,
  int total,
);

typedef KnowledgeVectorBatchCallback = Future<List<List<double>>> Function(
  List<KnowledgeChunk> chunks,
);

/// Builds one book index as a cancellable, persist-at-the-end task.
///
/// Chapter extraction is deliberately supplied by the caller. This keeps the
/// indexer independent from foliate and makes it usable by a future EPUB
/// chapter provider on both macOS and Android.
class KnowledgeIndexer {
  KnowledgeIndexer({
    required KnowledgeSearchService service,
    required KnowledgeIndexStore store,
  })  : _service = service,
        _store = store;

  final KnowledgeSearchService _service;
  final KnowledgeIndexStore _store;

  Future<IndexBuildResult> build({
    required String bookId,
    required Map<String, String> chapters,
    List<double> Function(KnowledgeChunk chunk)? vectorize,
    KnowledgeVectorBatchCallback? vectorizeBatch,
    String? embeddingMode,
    String? embeddingModelId,
    int? embeddingDimensions,
    IndexProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    final ordered = chapters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final collected = <String, String>{};
    for (var index = 0; index < ordered.length; index++) {
      if (isCancelled?.call() ?? false) {
        return const IndexBuildResult(status: IndexBuildStatus.cancelled);
      }
      final entry = ordered[index];
      collected[entry.key] = entry.value;
      onProgress?.call(entry.key, index + 1, ordered.length);
      await Future<void>.value();
    }

    if (isCancelled?.call() ?? false) {
      return const IndexBuildResult(status: IndexBuildStatus.cancelled);
    }
    var snapshot = _service.rebuild(
      bookId: bookId,
      chapters: collected,
      vectorize: vectorize,
    );
    if (vectorizeBatch != null) {
      final vectors = <VectorEntry>[];
      const batchSize = 16;
      for (var start = 0; start < snapshot.chunks.length; start += batchSize) {
        if (isCancelled?.call() ?? false) {
          return const IndexBuildResult(status: IndexBuildStatus.cancelled);
        }
        final end = math.min(start + batchSize, snapshot.chunks.length);
        final batch = snapshot.chunks.sublist(start, end);
        final values = await vectorizeBatch(batch);
        if (values.length != batch.length) {
          throw const FormatException(
            'Embedding response count does not match chunk count',
          );
        }
        for (var index = 0; index < batch.length; index++) {
          vectors.add(VectorEntry(chunk: batch[index], vector: values[index]));
        }
        onProgress?.call('@embedding', end, snapshot.chunks.length);
        // The macOS ONNX plugin executes on a background task queue. Yielding
        // here also gives Flutter a frame between batches, as ReadAny does.
        await Future<void>.delayed(Duration.zero);
      }
      snapshot = KnowledgeIndexSnapshot(
        bookId: snapshot.bookId,
        contentHash: snapshot.contentHash,
        chunks: snapshot.chunks,
        vectors: List.unmodifiable(vectors),
        embeddingMode: embeddingMode,
        embeddingModelId: embeddingModelId,
        embeddingDimensions:
            vectors.isEmpty ? embeddingDimensions : vectors.first.vector.length,
      );
      _service.putSnapshot(snapshot);
    }
    if (isCancelled?.call() ?? false) {
      return const IndexBuildResult(status: IndexBuildStatus.cancelled);
    }
    await _store.save(snapshot);
    return IndexBuildResult(
      status: IndexBuildStatus.completed,
      snapshot: snapshot,
    );
  }
}
