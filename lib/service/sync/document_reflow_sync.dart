import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/service/ocr/document_reflow_store.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// Immutable book snapshots: concurrent devices cannot overwrite each other's pages.
class DocumentReflowSync {
  DocumentReflowSync(
      {required this.client,
      required this.cache,
      required this.durableDirectory,
      DocumentReflowStore Function(Book)? store,
      File Function(Book)? sourceFile})
      : sourceFile = sourceFile ?? ((book) => File(book.fileFullPath)),
        store =
            store ?? ((book) => DocumentReflowStore(customCssBookKey(book)));

  static const root = 'modu/document-reflow-v1';
  final SyncClientBase client;
  final Directory cache, durableDirectory;
  final DocumentReflowStore Function(Book) store;
  final File Function(Book) sourceFile;
  static Future<void> _pendingTransfer = Future<void>.value();
  static final _bookId = RegExp(r'^[a-f0-9]{32}$');
  static final _snapshotName = RegExp(r'^([a-f0-9]{64})\.json$');

  Future<void> sync(Iterable<Book> books) async {
    final previous = _pendingTransfer;
    final done = Completer<void>();
    _pendingTransfer = done.future;
    await previous;
    try {
      await _sync(books);
    } finally {
      done.complete();
    }
  }

  Future<void> _sync(Iterable<Book> books) async {
    final candidates = <Book>[];
    for (final book in books) {
      if (!book.isDeleted && _bookId.hasMatch(book.md5?.toLowerCase() ?? '')) {
        candidates.add(book);
      }
    }
    if (candidates.isEmpty) return;
    await cache.create(recursive: true);
    final staging = await cache.createTemp('ocr-sync-');
    try {
      final remote = await client.readProps(root);
      if (remote != null && remote.isDir != true) {
        throw const FormatException('Invalid OCR sync directory');
      }
      final folders = remote == null
          ? <String>{}
          : {
              for (final entry in await client.readSyncDirectory(root))
                if (entry.isDir == true && _bookId.hasMatch(entry.name ?? ''))
                  entry.name!
            };
      for (final book in candidates) {
        final id = book.md5!.toLowerCase();
        final local = store(book);
        final data = await local.syncSnapshot();
        if ((data['pages'] as Map).isEmpty && !folders.contains(id)) continue;
        await _syncBook(id, local, staging);
        folders.add(id);
      }
    } finally {
      await staging.delete(recursive: true);
    }
  }

  Future<List<String>> _list(String folder) async {
    if (await client.readProps(folder) == null) return [];
    final names = <String>[];
    for (final file in await client.readSyncDirectory(folder)) {
      if (const {'.DS_Store', 'Thumbs.db', 'desktop.ini'}.contains(file.name)) {
        continue;
      }
      if (file.isDir != false ||
          !_snapshotName.hasMatch(file.name ?? '') ||
          (file.size ?? 0) > DocumentReflowSyncData.maxBytes ||
          names.length >= 1000) {
        throw const FormatException('Invalid or oversized OCR sync snapshot');
      }
      names.add(file.name!);
    }
    return names..sort();
  }

  Future<Map<String, dynamic>> _read(File file, String name, String id) async {
    if (await file.length() > DocumentReflowSyncData.maxBytes ||
        (await sha256.bind(file.openRead()).first).toString() !=
            name.split('.').first) {
      throw const FormatException('OCR sync integrity check failed');
    }
    final data = jsonDecode(await file.readAsString());
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['bookMd5'] != id ||
        data['data'] is! Map<String, dynamic>) {
      throw const FormatException('OCR sync source book mismatch');
    }
    return DocumentReflowSyncData.normalize(
        data['data'] as Map<String, dynamic>);
  }

  Future<void> _download(String path, File file) =>
      client.downloadFile(path, file.path, onProgress: (received, _) {
        if (received > DocumentReflowSyncData.maxBytes) {
          throw const FormatException('OCR sync exceeds size limit');
        }
      });

  Future<void> _publish(File pending, String folder, String name, String id,
      Directory staging) async {
    await _read(pending, name, id);
    await client.mkdirAll(folder);
    await client.uploadFile(pending.path, '$folder/$name');
    final verify = File('${staging.path}/verify.json');
    await _download('$folder/$name', verify);
    await _read(verify, name, id);
    final cached = File('${cache.path}/ocr-sync-verified/$name');
    await cached.parent.create(recursive: true);
    await verify.copy(cached.path);
    await pending.delete(); // Only after a complete verified read-back.
  }

  Future<void> _syncBook(
      String id, DocumentReflowStore local, Directory staging) async {
    final folder = '$root/$id';
    final destination =
        sha256.convert(utf8.encode(jsonEncode(client.syncIdentity)));
    final pending =
        Directory('${durableDirectory.path}/ocr-sync-pending/$destination/$id');
    await pending.create(recursive: true);
    // Repair interrupted immutable uploads before attempting to read them.
    await for (final file in pending.list(followLinks: false)) {
      if (file is File && _snapshotName.hasMatch(file.uri.pathSegments.last)) {
        await _publish(file, folder, file.uri.pathSegments.last, id, staging);
      }
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final names = await _list(folder);
        var merged = await local.syncSnapshot();
        var bytes = 0;
        for (final name in names) {
          var file = File('${cache.path}/ocr-sync-verified/$name');
          Map<String, dynamic>? incoming;
          if (await file.exists()) {
            try {
              incoming = await _read(file, name, id);
            } on FormatException {
              // A damaged local transport cache is safe to download again.
            }
          }
          if (incoming == null) {
            file = File('${staging.path}/incoming.json');
            await _download('$folder/$name', file);
            incoming = await _read(file, name, id);
            final cached = File('${cache.path}/ocr-sync-verified/$name');
            await cached.parent.create(recursive: true);
            await file.copy(cached.path);
          }
          bytes += await file.length();
          if (bytes > DocumentReflowSyncData.maxBytes) {
            throw const FormatException('OCR sync scan exceeds size limit');
          }
          merged = DocumentReflowSyncData.merge(merged, incoming);
        }
        // Compaction may race another device's listing. Retry the complete scan.
        if (jsonEncode(names) != jsonEncode(await _list(folder))) continue;
        await local.mergeSynced(merged);
        // Include edits saved during the downloads, under the store's write lock.
        merged = await local.syncSnapshot();
        if ((merged['pages'] as Map).isEmpty) return;
        final bytesOut = utf8
            .encode(jsonEncode({'version': 1, 'bookMd5': id, 'data': merged}));
        if (bytesOut.length > DocumentReflowSyncData.maxBytes) {
          throw const FormatException('OCR sync snapshot exceeds size limit');
        }
        final name = '${sha256.convert(bytesOut)}.json';
        if (!names.contains(name)) {
          final part = File('${pending.path}/$name.part');
          await part.writeAsBytes(bytesOut, flush: true);
          final outgoing = await part.rename('${pending.path}/$name');
          await _publish(outgoing, folder, name, id, staging);
        }
        // Only reclaim fully read inputs after their complete successor is verified.
        // Concurrent publications absent from this scan are never touched.
        for (final old in names.where((old) => old != name)) {
          try {
            await client.remove('$folder/$old');
          } on DioException catch (error) {
            if (error.response?.statusCode != 404) rethrow;
          }
        }
        return;
      } on DioException catch (error) {
        if (error.response?.statusCode != 404) rethrow;
      }
    }
    throw StateError('OCR sync changed concurrently; retry later');
  }
}
