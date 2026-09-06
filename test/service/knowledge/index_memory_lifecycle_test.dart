import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

class NoSnapshotReads extends FileKnowledgeIndexStore {
  NoSnapshotReads(super.file);
  @override
  Future<KnowledgeIndexSnapshot?> load(String bookId) =>
      throw StateError('Badge must not load vectors');
}

class OrderedStore implements KnowledgeIndexStore {
  final List<String> events;
  OrderedStore(this.events);
  @override
  Future<KnowledgeIndexSnapshot?> load(String id) async => null;
  @override
  Future<void> save(KnowledgeIndexSnapshot snapshot) async =>
      events.add('save');
}

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('modu-index-memory-');
    file = File('${directory.path}/fixture.json');
  });
  tearDown(() => directory.delete(recursive: true));

  KnowledgeIndexSnapshot fixture() => KnowledgeSearchService().rebuild(
      bookId: 'fixture',
      chapters: {'a': '正文\n\n第二段'},
      vectorize: (_) => [0.25, -0.5]);

  test('streamed persistence remains standard JSON and has a tiny badge record',
      () async {
    final store = NoSnapshotReads(file);
    final snapshot = fixture();
    await store.save(snapshot);
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    expect(KnowledgeIndexSnapshot.fromJson(json).vectors.length, 2);
    expect((await store.summary('fixture'))!['vectorCount'], 2);
    expect(await store.summaryFile.length(), lessThan(4096));
    // This subclass throws if the badge attempts to load the full index.
    for (var i = 0; i < 100; i++) {
      expect(await store.summary('fixture'), isNotNull);
    }
  });

  test('changed/truncated data invalidates the commit summary', () async {
    final store = FileKnowledgeIndexStore(file);
    await store.save(fixture());
    await file.writeAsString('{incomplete');
    expect(await store.summary('fixture'), isNull);
    expect(await store.load('fixture'), isNull);
  });

  test('cancelling a streamed save leaves the previous committed index intact',
      () async {
    final original = FileKnowledgeIndexStore(file);
    await original.save(fixture());
    final previous = await file.readAsString();
    var checks = 0;
    final cancelling =
        FileKnowledgeIndexStore(file, isCancelled: () => ++checks > 2);
    await expectLater(cancelling.save(fixture()), throwsStateError);
    expect(await file.readAsString(), previous);
    expect(await original.summary('fixture'), isNotNull);
  });

  test('old small JSON migrates once without losing contents', () async {
    final snapshot = fixture();
    await file.writeAsString(jsonEncode(snapshot.toJson()));
    final store = FileKnowledgeIndexStore(file);
    expect(await store.summary('fixture'), isNotNull);
    expect(await store.summaryFile.exists(), isTrue);
    expect(await NoSnapshotReads(file).summary('fixture'), isNotNull);
  });

  test('large legacy badge does not deserialize vectors in the background',
      () async {
    final output = await file.open(mode: FileMode.write);
    await output.truncate(5 * 1024 * 1024);
    await output.close();
    expect(await NoSnapshotReads(file).summary('fixture'), isNull);
  });

  test('partial or invalid vectors cannot replace a completed index', () async {
    final store = FileKnowledgeIndexStore(file);
    final source = fixture();
    await store.save(source);
    for (final values in [
      source.vectors.take(1).toList(),
      [
        VectorEntry(chunk: source.chunks[0], vector: [double.nan]),
        VectorEntry(chunk: source.chunks[1], vector: [0.0]),
      ]
    ]) {
      await expectLater(
          store.save(KnowledgeIndexSnapshot(
            bookId: source.bookId,
            contentHash: source.contentHash,
            chunks: source.chunks,
            vectors: values,
          )),
          throwsFormatException);
    }
    expect((await store.load('fixture'))!.vectors.length, 2);
  });

  test('model teardown finishes before saving and vectors are compact',
      () async {
    final events = <String>[];
    final result = await KnowledgeIndexer(
            service: KnowledgeSearchService(), store: OrderedStore(events))
        .build(
      bookId: 'fixture',
      chapters: {'one': 'a\n\nb'},
      vectorizeBatch: (chunks) async => chunks.map((_) => [0.1, 0.2]).toList(),
      beforeSave: () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        events.add('released');
      },
    );
    expect(events, ['released', 'save']);
    expect(
        result.snapshot!.vectors.every((v) => v.vector is Float64List), isTrue);
  });

  test('cancelling during teardown cannot commit an index', () async {
    final events = <String>[];
    var cancelled = false;
    final result = await KnowledgeIndexer(
            service: KnowledgeSearchService(), store: OrderedStore(events))
        .build(
      bookId: 'fixture',
      chapters: {'one': 'a'},
      isCancelled: () => cancelled,
      beforeSave: () async => cancelled = true,
    );
    expect(result.status, IndexBuildStatus.cancelled);
    expect(events, isEmpty);
  });

  test('incremental source hashing is compatible with existing content hashes',
      () {
    final snapshot = KnowledgeSearchService().rebuild(
      bookId: 'fixture',
      chapters: {'two': '第二章', 'one': '序言😀'},
    );
    expect(
        snapshot.contentHash,
        sha256
            .convert(utf8.encode('one\u0000序言😀\u0001two\u0000第二章\u0001'))
            .toString());
  });
}
