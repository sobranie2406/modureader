import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/service/sync/knowledge_index_sync.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'knowledge_index_sync_test.dart' show Device, IndexClient;

/// Filesystem-backed transport: do not allocate the synthetic 130 MiB object in
/// the in-memory fake server. Exercises the production sync flow, not a network.
class DiskIndexClient extends IndexClient {
  DiskIndexClient(this.root);
  final Directory root;
  File payload(String path) =>
      File('${root.path}/${sha256.convert(utf8.encode(path))}');

  @override
  Future<void> uploadFile(String localPath, String remotePath,
      {bool replace = true,
      void Function(int, int)? onProgress,
      CancelToken? cancelToken}) async {
    uploads++;
    await root.create(recursive: true);
    await File(localPath).copy(payload(remotePath).path);
    files[remotePath] = const [];
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath,
      {void Function(int, int)? onProgress}) async {
    downloads++;
    await payload(remotePath).copy(localPath);
    final size = await File(localPath).length();
    onProgress?.call(size, size);
  }

  @override
  Future<RemoteFile?> readProps(String path) async {
    if (!files.containsKey(path)) return super.readProps(path);
    return RemoteFile(
        path: path,
        name: path.split('/').last,
        isDir: false,
        size: await payload(path).length());
  }

  @override
  Future<List<RemoteFile>> readDir(String path) async => [
        for (final entry in await super.readDir(path))
          (await readProps('$path/${entry.name}'))!,
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a >128 MiB index syncs between device IDs and remains idempotent',
      () async {
    final root = await Directory.systemTemp.createTemp('modu-large-sync-');
    addTearDown(() => root.delete(recursive: true));
    final remote = DiskIndexClient(Directory('${root.path}/remote'));
    final pc = Device(Directory('${root.path}/pc'), remote);
    final phone = Device(Directory('${root.path}/phone'), remote);
    final first = Book.mock().copyWith(id: 7);
    final second = Book.mock().copyWith(id: 91);
    await pc.add(first, 'synthetic identical book');
    await phone.add(second, 'synthetic identical book');
    final values = jsonEncode(List<double>.filled(512, 0.12345678901234567));
    final count = (129 * 1024 * 1024 / values.length).ceil();
    final output = await pc.index(first).open(mode: FileMode.write);
    final header = jsonEncode({
      'bookId': '7',
      'contentHash': 'fixture',
      'sourceFingerprint': await pc.fingerprint(first),
      'embeddingMode': 'local',
      'embeddingModelId': 'large-fixture',
      'embeddingDimensions': 512,
    });
    try {
      await output.writeString(
          '${header.substring(0, header.length - 1)},"chunks":[\n');
      for (var i = 0; i < count; i++) {
        await output.writeString('${i == 0 ? '' : ','}${jsonEncode({
              'id': '7:chunk:$i',
              'bookId': '7',
              'chapterId': 'chapter',
              'text': 'synthetic $i',
              'startOffset': i,
            })}\n');
      }
      await output.writeString('],"vectors":[\n');
      for (var i = 0; i < count; i++) {
        await output.writeString(
            '${i == 0 ? '' : ','}{"chunkId":"7:chunk:$i","vector":$values}\n');
      }
      await output.writeString(']}');
    } finally {
      await output.close();
    }
    expect(await pc.index(first).length(), greaterThan(128 * 1024 * 1024));
    expect(await pc.index(first).length(), lessThan(maxKnowledgeTransferBytes));
    // No summary: the fallback must also stream rather than load all vectors.
    await pc.service().sync([first], enabled: () => true);
    expect(
        await pc.root
            .list()
            .any((file) => file.path.contains('knowledge-sync-')),
        isFalse);
    expect(remote.uploads, 1);
    expect(await remote.payload(remote.files.keys.single).length(),
        greaterThan(128 * 1024 * 1024));
    await phone.service().sync([second], enabled: () => true);
    expect(
        await phone.root
            .list()
            .any((file) => file.path.contains('knowledge-sync-')),
        isFalse);
    final store = FileKnowledgeIndexStore(phone.index(second),
        sourceFingerprint: await phone.fingerprint(second));
    final summary = await store.summary('91');
    expect(summary?['vectorCount'], count);
    final snapshot = (await store.load('91'))!;
    expect(snapshot.chunks.length, count);
    expect(snapshot.vectors.length, count);
    expect(snapshot.chunks.last.id, '91:${count - 1}');
    expect(snapshot.chunks.last.startOffset, count - 1);
    expect(snapshot.vectors.last.chunk, same(snapshot.chunks.last));
    expect(snapshot.vectors.last.vector.length, 512);
    expect(snapshot.vectors.last.vector.last, 0.12345678901234567);
    await phone.service().sync([second], enabled: () => true);
    expect(remote.uploads, 1);
    expect(remote.files.length, 1);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
