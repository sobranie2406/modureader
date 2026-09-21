import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/knowledge/book_index_lock.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:anx_reader/service/knowledge/book_source_fingerprint.dart';
import 'package:anx_reader/service/knowledge/index_build_marker.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/service/knowledge/knowledge_index_stream.dart';
import 'package:anx_reader/service/sync/knowledge_index_transfer.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:crypto/crypto.dart';

const knowledgeSyncRoot = 'modu/knowledge-v1';
const maxKnowledgeTransferBytes = maxKnowledgeIndexBytes;

/// Legacy transfer implementation, no longer wired into application sync.
/// Retained for compatibility regression tests, not a user-facing feature.
/// Immutable attachments, outside the row-sync database. A remote
/// pathname never selects a local book: only the SHA-256 of its actual bytes can.
class KnowledgeIndexSync {
  KnowledgeIndexSync({
    required this.client,
    required this.cache,
    File Function(Book)? sourceFile,
    File Function(Book)? indexFile,
    Future<String> Function(Book)? fingerprint,
    Future<bool> Function(Book)? isBookCurrent,
  })  : sourceFile = sourceFile ?? ((book) => File(book.fileFullPath)),
        indexFile = indexFile ??
            ((book) => BookKnowledgeIndexService().indexFile(book.id)),
        fingerprint = fingerprint ?? bookSourceFingerprint,
        isBookCurrent = isBookCurrent ?? ((_) async => true);

  final SyncClientBase client;
  final Directory cache;
  final File Function(Book) sourceFile;
  final File Function(Book) indexFile;
  final Future<String> Function(Book) fingerprint;
  final Future<bool> Function(Book) isBookCurrent;

  Future<void> sync(
    Iterable<Book> books, {
    required bool Function() enabled,
    bool upload = true,
    bool download = true,
    Future<void> Function(Book, String?, String?)? onImported,
  }) async {
    if (!enabled()) return;
    await cache.create(recursive: true);
    final temporaryRoot = await cache.createTemp('knowledge-sync-');
    try {
      for (final book in books) {
        if (!enabled()) break;
        if (book.isDeleted || !await sourceFile(book).exists()) continue;
        await withBookIndexLock(book.id, () async {
          final temporary = await temporaryRoot.createTemp('book-');
          try {
            if (!enabled() || book.isDeleted || !await isBookCurrent(book)) {
              return;
            }
            final file = indexFile(book);
            // Interrupted/rebuilding indexes must never be published as complete.
            if (await indexBuildMarker(file).exists()) return;
            final before = await fingerprint(book);
            final source = sourceFile(book);
            final bookSha = await _fileSha256(source.path);
            if (await fingerprint(book) != before) return;
            final folder = '$knowledgeSyncRoot/$bookSha';
            final localStore =
                FileKnowledgeIndexStore(file, sourceFingerprint: before);
            final local = await localStore.summary(book.id.toString());
            // Missing/stale badge metadata alone must not replace a valid index.
            // Inspect missing metadata by streaming, never loading all vectors.
            if ((local != null && (local['vectorCount'] as int) > 0) ||
                (local == null && await file.exists())) {
              if (!enabled()) return;
              final exported = await _exportIndex(file.path, book.id.toString(),
                  before, bookSha, '${temporary.path}/out.json');
              if (!enabled() ||
                  !await isBookCurrent(book) ||
                  await fingerprint(book) != before) {
                return;
              }
              if (exported != null) {
                if (!upload) return;
                await client.mkdirAll(folder);
                final remotePath = '$folder/$exported.json';
                final props = await client.readProps(remotePath);
                final outgoing = File('${temporary.path}/out.json');
                final localSize = await outgoing.length();
                if (props == null || props.size != localSize) {
                  if (!enabled()) return;
                  // Same digest always denotes the exact same immutable bytes.
                  // Repair an interrupted PUT at that name, never another index.
                  await client.uploadFile(
                      '${temporary.path}/out.json', remotePath,
                      replace: props != null);
                  final verified = '${temporary.path}/verify.json';
                  await client.downloadFile(remotePath, verified,
                      onProgress: (received, _) {
                    if (received > maxKnowledgeTransferBytes) {
                      throw const FormatException('向量索引超过安全同步大小限制');
                    }
                  });
                  if (await File(verified).length() != localSize ||
                      await _fileSha256(verified) != exported) {
                    throw const FormatException('向量索引上传完整性校验失败');
                  }
                }
                return;
              }
            }
            if (!download || !enabled()) return;
            if (await client.readProps(folder) == null) return;
            final candidates = (await client.readSyncDirectory(folder))
                .where((entry) =>
                    entry.isDir != true &&
                    RegExp(r'^[a-f0-9]{64}\.json$').hasMatch(entry.name ?? ''))
                .toList()
              ..sort((a, b) {
                final date = (b.mTime?.millisecondsSinceEpoch ?? 0)
                    .compareTo(a.mTime?.millisecondsSinceEpoch ?? 0);
                return date != 0 ? date : a.name!.compareTo(b.name!);
              });
            if (candidates.isEmpty) return;
            // Never replace a valid local index merely because server time is newer.
            final candidate = candidates.first;
            if ((candidate.size ?? 0) > maxKnowledgeTransferBytes) {
              throw const FormatException('向量索引超过安全同步大小限制（1 GiB）');
            }
            final incoming = File('${temporary.path}/in.json');
            await client
                .downloadFile('$folder/${candidate.name}', incoming.path,
                    onProgress: (received, _) {
              if (received > maxKnowledgeTransferBytes) {
                throw const FormatException('向量索引超过安全同步大小限制');
              }
            });
            final staged = '${temporary.path}/mapped.json';
            final model = await _importIndex(
                incoming.path,
                candidate.name!.split('.').first,
                bookSha,
                book.id.toString(),
                before,
                staged);
            if (!enabled() ||
                book.isDeleted ||
                !await isBookCurrent(book) ||
                await fingerprint(book) != before) {
              return;
            }
            // All identity/format checks finished before touching the active index.
            await file.parent.create(recursive: true);
            final staging = File('${file.path}.sync-import');
            await File(staged).copy(staging.path);
            if (!enabled() ||
                !await isBookCurrent(book) ||
                await fingerprint(book) != before) {
              await staging.delete();
              return;
            }
            await staging.rename(file.path);
            final summary = File('${file.path}.summary');
            final summaryData =
                jsonDecode(await File('$staged.summary').readAsString()) as Map;
            final stat = await file.stat();
            summaryData['size'] = stat.size;
            summaryData['modified'] = stat.modified.microsecondsSinceEpoch;
            await File('${summary.path}.sync-import')
                .writeAsString(jsonEncode(summaryData), flush: true);
            await File('${summary.path}.sync-import').rename(summary.path);
            await onImported?.call(book, model[0], model[1]);
          } finally {
            if (await temporary.exists()) {
              await temporary.delete(recursive: true);
            }
          }
        });
      }
    } finally {
      if (await temporaryRoot.exists()) {
        await temporaryRoot.delete(recursive: true);
      }
    }
  }
}

Future<String> _fileSha256(String path) => Isolate.run(
    () async => (await sha256.bind(File(path).openRead()).first).toString());

Future<String?> _exportIndex(String path, String localId, String fingerprint,
        String bookSha, String output) =>
    Isolate.run(() async {
      final result = await transferKnowledgeIndex(
          input: File(path),
          output: File(output),
          bookSha: bookSha,
          localId: localId,
          fingerprint: fingerprint,
          importing: false);
      if (result['matchesSource'] != true || result['vectorCount'] == 0) {
        return null;
      }
      return (await sha256.bind(File(output).openRead()).first).toString();
    });

Future<List<String?>> _importIndex(String path, String expectedDigest,
        String bookSha, String localId, String fingerprint, String output) =>
    Isolate.run(() async {
      final file = File(path);
      if (await file.length() > maxKnowledgeTransferBytes) {
        throw const FormatException('向量索引超过安全同步大小限制（1 GiB）');
      }
      if ((await sha256.bind(file.openRead()).first).toString() !=
          expectedDigest) {
        throw const FormatException('向量索引传输完整性校验失败');
      }
      final result = await transferKnowledgeIndex(
          input: file,
          output: File(output),
          bookSha: bookSha,
          localId: localId,
          fingerprint: fingerprint,
          importing: true);
      final stat = await File(output).stat();
      await File('$output.summary').writeAsString(
          jsonEncode({
            'bookId': localId,
            'sourceFingerprint': fingerprint,
            'chunkCount': result['chunkCount'],
            'vectorCount': result['vectorCount'],
            'size': stat.size,
            'modified': stat.modified.microsecondsSinceEpoch,
          }),
          flush: true);
      return [
        result['embeddingMode'] as String?,
        result['embeddingModelId'] as String?
      ];
    });
