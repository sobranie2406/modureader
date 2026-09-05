import 'dart:io';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late String originalPath;
  late Book book;
  final service = BookKnowledgeIndexService();
  KnowledgeIndexSnapshot snapshot() => KnowledgeSearchService()
      .rebuild(bookId: '1', chapters: {'preface': '旧版正文'});

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('modu-index-freshness-');
    originalPath = documentPath;
    documentPath = directory.path;
    book = Book.mock().copyWith(filePath: 'book.epub', md5: 'original');
    await File(book.fileFullPath).writeAsString('original source');
  });
  tearDown(() async {
    documentPath = originalPath;
    await directory.delete(recursive: true);
  });

  test('replacement with the same book ID rejects the old index', () async {
    await (await service.storeFor(book)).save(snapshot());
    expect(await service.hasIndex(book), isTrue);
    final replacement = book.copyWith(filePath: 'replacement.epub', md5: 'new');
    await File(replacement.fileFullPath).writeAsString('new source');
    expect(await service.hasIndex(replacement), isFalse);
    expect(await service.loadSnapshot(replacement), isNull);
    expect((await service.status(replacement)).indexed, isFalse);
    expect(await service.indexFile(book.id).exists(), isTrue);
  });

  test(
      'legacy indexes require rebuilding once; ordinary reading progress does not',
      () async {
    await FileKnowledgeIndexStore(service.indexFile(book.id)).save(snapshot());
    expect(await service.hasIndex(book), isFalse);
    await (await service.storeFor(book)).save(snapshot());
    expect(
        await service.hasIndex(
            book.copyWith(readingPercentage: 0.5, updateTime: DateTime(2030))),
        isTrue);
  });

  test('source changed during indexing cannot commit obsolete content',
      () async {
    final store = await service.storeFor(book);
    await File(book.fileFullPath)
        .writeAsString('changed source with different length');
    await expectLater(store.save(snapshot()), throwsStateError);
    expect(await service.indexFile(book.id).exists(), isFalse);
  });

  test('cancellation during final embedding batch does not persist an index',
      () async {
    var cancelled = false;
    final result = await KnowledgeIndexer(
            service: KnowledgeSearchService(),
            store: await service.storeFor(book))
        .build(
            bookId: '1',
            chapters: {'one': 'content'},
            isCancelled: () => cancelled,
            vectorizeBatch: (chunks) async {
              cancelled = true;
              return chunks.map((_) => [1.0]).toList();
            });
    expect(result.status, IndexBuildStatus.cancelled);
    expect(await service.indexFile(book.id).exists(), isFalse);
  });
}
