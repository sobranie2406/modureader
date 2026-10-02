import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/ai/tools/repository/book_content_search_repository.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:anx_reader/service/knowledge/book_source_fingerprint.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

class UpgradeChapters extends BookContentSearchRepository {
  UpgradeChapters(this.chapters);
  final Map<String, String> chapters;
  int calls = 0;
  bool fail = false;
  Future<void> Function()? duringExtraction;
  @override
  Future<Map<String, String>> extractChaptersForIndex(Book book,
      {BookChapterExtractionProgress? onProgress,
      bool Function()? isCancelled}) async {
    calls++;
    if (fail) throw StateError('Extraction must not be repeated');
    await duringExtraction?.call();
    return chapters;
  }
}

class NoSourceReads extends BookKnowledgeIndexService {
  @override
  Future<String> sourceFingerprint(Book book) =>
      throw StateError('Unindexed books must not be hashed');
}

void main() {
  late Directory root;
  late String previousPath;
  late Book book;
  late UpgradeChapters chapters;
  late BookKnowledgeIndexService service;
  const text = {'one': '第一章正文。', 'two': '第二章正文。'};
  KnowledgeIndexSnapshot snapshot({String mode = 'builtin'}) {
    final base = KnowledgeSearchService()
        .rebuild(bookId: '1', chapters: text, vectorize: (_) => [0.5, 0.25]);
    return KnowledgeIndexSnapshot(
        bookId: '1',
        contentHash: base.contentHash,
        chunks: base.chunks,
        vectors: base.vectors,
        embeddingMode: mode,
        embeddingModelId: 'unchanged-model',
        embeddingDimensions: 2);
  }

  Future<void> saveLegacy({String mode = 'builtin'}) async {
    final stat = await File(book.fileFullPath).stat();
    final old = sha256
        .convert(utf8.encode(jsonEncode([
          book.filePath,
          book.md5,
          stat.size,
          stat.modified.microsecondsSinceEpoch,
        ])))
        .toString();
    await FileKnowledgeIndexStore(service.indexFile(1), sourceFingerprint: old)
        .save(snapshot(mode: mode));
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-index-upgrade-');
    previousPath = documentPath;
    documentPath = root.path;
    book = Book.mock().copyWith(
        filePath: 'book.epub',
        md5: md5.convert(utf8.encode('same local book')).toString());
    await File(book.fileFullPath).writeAsString('same local book');
    chapters = UpgradeChapters(text);
    service = BookKnowledgeIndexService(chapterRepository: chapters);
  });
  tearDown(() async {
    documentPath = previousPath;
    await root.delete(recursive: true);
  });

  test('file timestamps and storage paths do not change content identity',
      () async {
    final before = await bookSourceFingerprint(book);
    final file = File(book.fileFullPath);
    await file.setLastModified(DateTime(2040));
    expect(await bookSourceFingerprint(book), before);
    final copy =
        book.copyWith(filePath: 'copy.epub', md5: 'corrected metadata');
    await file.copy(copy.fileFullPath);
    expect(await bookSourceFingerprint(copy), before);
    await File(copy.fileFullPath).writeAsString('other local txt');
    expect(await bookSourceFingerprint(copy), isNot(before));
  });

  test('books without an index avoid hashing for status and search', () async {
    final unindexed = NoSourceReads();
    expect(await unindexed.hasIndex(book), isFalse);
    expect((await unindexed.status(book)).indexed, isFalse);
    expect(await unindexed.loadSnapshot(book), isNull);
  });

  test('same-size replacements cannot borrow the imported MD5 identity',
      () async {
    await saveLegacy();
    final file = File(book.fileFullPath);
    final modified = await file.lastModified();
    await file.writeAsString('other local txt');
    await file.setLastModified(modified);
    expect(await legacyBookSourceFingerprint(book), isNull);
    final changed = BookKnowledgeIndexService(
        chapterRepository: UpgradeChapters({'one': '另一部书'}));
    expect(await changed.hasIndex(book), isFalse);
    expect(await service.indexFile(1).exists(), isTrue);
  });

  test('new content identities reject replacements even with the same text',
      () async {
    await (await service.storeFor(book)).save(snapshot());
    final file = File(book.fileFullPath);
    final modified = await file.lastModified();
    await file.writeAsString('other local txt');
    await file.setLastModified(modified);
    expect(await service.hasIndex(book), isFalse);
    expect(await service.loadSnapshot(book), isNull);
    expect(chapters.calls, 0);
  });

  test('restarting after copying a book preserves its completed vectors',
      () async {
    await (await service.storeFor(book)).save(snapshot());
    await File(book.fileFullPath).setLastModified(DateTime(2040));
    chapters.fail = true;
    expect(await service.hasIndex(book), isTrue);
    expect((await service.status(book)).vectorCount, 2);
    expect(
        (await service.loadSnapshot(book))!.vectors.first.vector, [0.5, 0.25]);
    expect(chapters.calls, 0);
  });

  test('copied index repairs its commit metadata without loading all vectors',
      () async {
    await (await service.storeFor(book)).save(snapshot());
    final index = service.indexFile(1);
    final original = await index.readAsString();
    await index.setLastModified(DateTime(2040));
    chapters.fail = true;
    expect(await service.hasIndex(book), isTrue);
    expect((await service.status(book)).vectorCount, 2);
    expect(await index.readAsString(), original);
    expect(chapters.calls, 0);
  });

  test(
      'unchanged legacy source is adopted without text extraction or inference',
      () async {
    await saveLegacy();
    chapters.fail = true;
    expect(await service.hasIndex(book), isTrue);
    expect((await service.loadSnapshot(book))!.embeddingModelId,
        'unchanged-model');
    expect(chapters.calls, 0);
  });

  test(
      'legacy timestamp mismatch verifies text once and retains exact index bytes',
      () async {
    await saveLegacy();
    final original = await service.indexFile(1).readAsString();
    await File(book.fileFullPath).setLastModified(DateTime(2040));
    expect(await service.hasIndex(book), isTrue);
    expect(chapters.calls, 1);
    expect(await service.indexFile(1).readAsString(), original);
    final next = UpgradeChapters(text)..fail = true;
    final restarted = BookKnowledgeIndexService(chapterRepository: next);
    expect((await restarted.status(book)).vectorCount, 2);
    expect((await restarted.loadSnapshot(book))!.vectors.first.vector,
        [0.5, 0.25]);
    await service.indexFile(1).setLastModified(DateTime(2041));
    expect((await restarted.status(book)).indexed, isTrue);
    expect(next.calls, 0);
  });

  test(
      'changed legacy text or a source change during verification is never adopted',
      () async {
    await saveLegacy();
    await File(book.fileFullPath).writeAsString('different source');
    final changed = BookKnowledgeIndexService(
        chapterRepository: UpgradeChapters({'one': '完全不同的正文'}));
    expect(await changed.hasIndex(book), isFalse);
    chapters.duringExtraction = () =>
        File(book.fileFullPath).writeAsString('changed during verification');
    expect(await service.hasIndex(book), isFalse);
    expect(await service.indexFile(1).exists(), isTrue);
  });

  test('failed local verification can retry without rebuilding vectors',
      () async {
    await saveLegacy();
    await File(book.fileFullPath).setLastModified(DateTime(2040));
    chapters.fail = true;
    expect(await service.hasIndex(book), isFalse);
    chapters.fail = false;
    expect(await service.hasIndex(book), isTrue);
    expect(chapters.calls, 2);
    expect((await service.loadSnapshot(book))!.vectors.length, 2);
  });

  test('old indexes without a source fingerprint recover by local text',
      () async {
    await FileKnowledgeIndexStore(service.indexFile(1)).save(snapshot());
    expect(await service.hasIndex(book), isTrue);
    expect(chapters.calls, 1);
    chapters.fail = true;
    expect((await service.status(book)).indexed, isTrue);
    expect((await service.loadSnapshot(book))!.embeddingModelId,
        'unchanged-model');
    expect(chapters.calls, 1);
  });

  for (final mode in ['builtin', 'local', 'remote']) {
    test('$mode embedding provenance survives legacy index migration',
        () async {
      await saveLegacy(mode: mode);
      await File(book.fileFullPath).setLastModified(DateTime(2040));
      expect(await service.hasIndex(book), isTrue);
      final retained = (await service.loadSnapshot(book))!;
      expect(retained.embeddingMode, mode);
      expect(retained.embeddingModelId, 'unchanged-model');
      expect(retained.embeddingDimensions, 2);
      expect(retained.vectors.first.vector, [0.5, 0.25]);
    });
  }
}
