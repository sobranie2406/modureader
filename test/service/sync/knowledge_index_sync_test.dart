import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/knowledge/book_index_lock.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/service/sync/knowledge_index_sync.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'row_sync_test.dart' show MemorySyncClient;

class IndexClient extends MemorySyncClient {
  int uploads = 0;
  int downloads = 0;
  Future<void> Function()? afterDownload;
  @override
  Future<void> uploadFile(String localPath, String remotePath,
      {bool replace = true,
      void Function(int, int)? onProgress,
      CancelToken? cancelToken}) async {
    uploads++;
    await super.uploadFile(localPath, remotePath, replace: replace);
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath,
      {void Function(int, int)? onProgress}) async {
    downloads++;
    await super.downloadFile(remotePath, localPath);
    await afterDownload?.call();
  }
}

class Device {
  Device(this.root, this.client);
  final Directory root;
  final IndexClient client;
  File source(Book b) => File('${root.path}/${b.id}.epub');
  File index(Book b) => File('${root.path}/${b.id}.json');
  Future<String> fingerprint(Book b) async {
    final stat = await source(b).stat();
    return '${root.path}:${b.id}:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
  }

  KnowledgeIndexSync service({Future<bool> Function(Book)? current}) =>
      KnowledgeIndexSync(
          client: client,
          cache: root,
          sourceFile: source,
          indexFile: index,
          fingerprint: fingerprint,
          isBookCurrent: current);
  Future<void> add(Book b, String text, {bool indexed = false}) async {
    await root.create(recursive: true);
    await source(b).writeAsString(text);
    if (!indexed) return;
    final chunk = KnowledgeChunk(
        id: '${b.id}:chapter:0',
        bookId: '${b.id}',
        chapterId: 'chapter',
        text: text);
    await FileKnowledgeIndexStore(index(b),
            sourceFingerprint: await fingerprint(b))
        .save(KnowledgeIndexSnapshot(
            bookId: '${b.id}',
            contentHash: 'content-digest',
            chunks: [chunk],
            vectors: [
              VectorEntry(chunk: chunk, vector: [0.5, 0.8])
            ],
            embeddingMode: 'local',
            embeddingModelId: 'fixture-model',
            embeddingDimensions: 2));
  }

  Future<KnowledgeIndexSnapshot?> read(Book b) async =>
      FileKnowledgeIndexStore(index(b), sourceFingerprint: await fingerprint(b))
          .load('${b.id}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late IndexClient remote;
  late Device pc, phone;
  final first = Book.mock().copyWith(id: 7, title: '同名书籍');
  final second = Book.mock().copyWith(id: 91, title: '同名书籍');
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-index-sync-test-');
    remote = IndexClient()..atomic = false;
    pc = Device(Directory('${root.path}/pc'), remote);
    phone = Device(Directory('${root.path}/phone'), remote);
  });
  tearDown(() async => root.delete(recursive: true));
  Future<void> publish() async {
    await pc.add(first, '同一份 EPUB 内容', indexed: true);
    await pc.service().sync([first], enabled: () => true);
    remote.downloads = 0;
  }

  test('retired index sync setting is removed and cannot be restored',
      () async {
    SharedPreferences.setMockInitialValues({'syncKnowledgeIndexes': true});
    await Prefs().initPrefs();
    expect(Prefs().prefs.containsKey('syncKnowledgeIndexes'), isFalse);
    expect(Prefs().quickMarkShowMenu, isFalse);
    await Prefs().applyPrefsBackupMap({
      'syncKnowledgeIndexes': {'type': 'bool', 'value': true},
    });
    expect(Prefs().prefs.containsKey('syncKnowledgeIndexes'), isFalse);
    // Even a stale key introduced after initialization is not exported.
    await Prefs().prefs.setBool('syncKnowledgeIndexes', true);
    expect(await Prefs().buildPrefsBackupMap(),
        isNot(contains('syncKnowledgeIndexes')));
    Prefs().quickMarkShowMenu = true;
    await Prefs().initPrefs();
    expect(Prefs().prefs.containsKey('syncKnowledgeIndexes'), isFalse);
    expect(Prefs().quickMarkShowMenu, isTrue);
  });

  test('normal WebDAV sync and settings no longer wire index transfer', () {
    final sync = File('lib/providers/sync.dart').readAsStringSync();
    expect(sync, isNot(contains('KnowledgeIndexSync')));
    expect(sync, isNot(contains('knowledge_index_sync.dart')));
    expect(sync, isNot(contains('syncKnowledgeIndexes')));
    final settings = File('lib/page/settings_page/sync.dart').readAsStringSync();
    expect(settings, isNot(contains('syncKnowledgeIndexes')));
    expect(settings, isNot(contains('Sync book vector indexes')));
  });

  test(
      'portable payload excludes device paths and local IDs; truncated PUT is repaired',
      () async {
    await publish();
    final path = remote.files.keys.single;
    final original = List<int>.from(remote.files[path]!);
    final text = utf8.decode(original);
    expect(text, isNot(contains(root.path)));
    final payload = jsonDecode(text) as Map;
    expect(payload['index']['bookId'], startsWith('sha256:'));
    expect(payload['index']['sourceFingerprint'], isNull);
    remote.files[path] = original.take(12).toList();
    final writes = remote.uploads;
    await pc.service().sync([first], enabled: () => true);
    expect(remote.uploads, writes + 1);
    expect(remote.files[path], original);
  });

  test('valid transport digest does not bypass vector dimension validation',
      () async {
    await publish();
    final path = remote.files.keys.single;
    final payload = jsonDecode(utf8.decode(remote.files.remove(path)!)) as Map;
    payload['index']['embeddingDimensions'] = 3;
    final bytes = utf8.encode(jsonEncode(payload));
    remote.files[
            '${path.substring(0, path.lastIndexOf('/'))}/${sha256.convert(bytes)}.json'] =
        bytes;
    await phone.add(second, '同一份 EPUB 内容');
    await expectLater(phone.service().sync([second], enabled: () => true),
        throwsFormatException);
    expect(await phone.index(second).exists(), isFalse);
  });

  test(
      'no reliable ETag: PC and phone IDs differ, vectors and chapter bindings survive',
      () async {
    await publish();
    await phone.add(second, '同一份 EPUB 内容');
    await phone.service().sync([second], enabled: () => true);
    final snapshot = (await phone.read(second))!;
    expect(snapshot.bookId, '91');
    expect(snapshot.chunks.single.bookId, '91');
    expect(snapshot.chunks.single.id, '91:0');
    expect(snapshot.chunks.single.chapterId, 'chapter');
    expect(snapshot.vectors.single.chunk, same(snapshot.chunks.single));
    expect(snapshot.vectors.single.vector, [0.5, 0.8]);
    expect(snapshot.embeddingModelId, 'fixture-model');
    final summary = await FileKnowledgeIndexStore(phone.index(second),
            sourceFingerprint: await phone.fingerprint(second))
        .summary('91');
    expect(summary?['vectorCount'], 1);
    final writes = remote.uploads;
    await phone.service().sync([second], enabled: () => true);
    expect(remote.uploads, writes); // canonical payload is identical across IDs
  });
  test(
      'same title AND reused local ID with different bytes never receives another book index',
      () async {
    await publish();
    await phone.add(first, '另一本同名书籍内容');
    await phone.service().sync([first], enabled: () => true);
    expect(await phone.read(first), isNull);
    expect(remote.downloads, 0);
  });
  test('disabled, deleted, missing books and upload-only never download',
      () async {
    await publish();
    await phone.add(second, '同一份 EPUB 内容');
    await phone.service().sync([second], enabled: () => false);
    await phone
        .service()
        .sync([second.copyWith(isDeleted: true)], enabled: () => true);
    await phone.service().sync([second], enabled: () => true, download: false);
    await phone
        .service()
        .sync([Book.mock().copyWith(id: 100)], enabled: () => true);
    expect(remote.downloads, 0);
    expect(await phone.read(second), isNull);
  });
  test('corrupt/truncated remote payload rejected before replacing local data',
      () async {
    await publish();
    remote.files[remote.files.keys.single] = utf8.encode('{"schema":');
    await phone.add(second, '同一份 EPUB 内容');
    await expectLater(phone.service().sync([second], enabled: () => true),
        throwsFormatException);
    expect(await phone.index(second).exists(), isFalse);
  });
  test('valid checksum cannot bypass embedded book identity or vector checks',
      () async {
    await publish();
    final path = remote.files.keys.single;
    final payload = jsonDecode(utf8.decode(remote.files.remove(path)!)) as Map;
    payload['index']['chunks'][0]['bookId'] = 'other-book';
    final bytes = utf8.encode(jsonEncode(payload));
    remote.files[
            '${path.substring(0, path.lastIndexOf('/'))}/${sha256.convert(bytes)}.json'] =
        bytes;
    await phone.add(second, '同一份 EPUB 内容');
    await expectLater(phone.service().sync([second], enabled: () => true),
        throwsFormatException);
    expect(await phone.index(second).exists(), isFalse);
  });
  test(
      'book replacement or deleting DB row during download prevents installation',
      () async {
    await publish();
    await phone.add(second, '同一份 EPUB 内容');
    var current = true;
    remote.afterDownload = () async {
      current = false;
    };
    await phone
        .service(current: (_) async => current)
        .sync([second], enabled: () => true);
    expect(await phone.index(second).exists(), isFalse);
    remote.afterDownload =
        () => phone.source(second).writeAsString('已经被替换的新文件').then((_) {});
    await phone.service().sync([second], enabled: () => true);
    expect(await phone.index(second).exists(), isFalse);
  });
  test('switching off during download does not install index', () async {
    await publish();
    await phone.add(second, '同一份 EPUB 内容');
    var enabled = true;
    remote.afterDownload = () async {
      enabled = false;
    };
    await phone.service().sync([second], enabled: () => enabled);
    expect(await phone.index(second).exists(), isFalse);
  });
  test(
      'local valid index is not overwritten and interrupted builds are not published',
      () async {
    await publish();
    await phone.add(second, '同一份 EPUB 内容', indexed: true);
    await phone.service().sync([second], enabled: () => true, upload: false);
    expect(remote.downloads, 0);
    await File('${phone.index(second).path}.building')
        .writeAsString('unfinished');
    final uploads = remote.uploads;
    await phone.service().sync([second], enabled: () => true);
    expect(remote.uploads, uploads);
  });
  test('index writers serialize for one book without blocking another book',
      () async {
    final gate = Completer<void>();
    final calls = <int>[];
    final a = withBookIndexLock(1, () async {
      calls.add(1);
      await gate.future;
    });
    final b = withBookIndexLock(1, () async => calls.add(2));
    await withBookIndexLock(2, () async => calls.add(3));
    expect(calls, [1, 3]);
    gate.complete();
    await Future.wait([a, b]);
    expect(calls, [1, 3, 2]);
  });
}
