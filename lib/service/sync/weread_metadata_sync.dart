import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/custom_css_profile.dart';
import 'package:modu_reader/service/sync/sync_client_base.dart';
import 'package:modu_reader/service/weread/weread_store.dart';
import 'package:crypto/crypto.dart';

/// Optional sidecars, keyed by the original book checksum, never database IDs.
/// Immutable snapshots preserve concurrent bindings and per-section refreshes.
class WereadMetadataSync {
  WereadMetadataSync({
    required this.client,
    required this.cache,
    required this.durableDirectory,
    WereadStore Function(Book)? store,
    File Function(Book)? sourceFile,
  })  : store = store ?? ((book) => WereadStore(customCssBookKey(book))),
        sourceFile = sourceFile ?? ((book) => File(book.fileFullPath));

  static const root = 'modu/weread-metadata-v1';
  static final _md5 = RegExp(r'^[a-f0-9]{32}$');
  static final _name = RegExp(r'^[a-f0-9]{64}\.json$');
  static Future<void> _pending = Future.value();
  final SyncClientBase client;
  final Directory cache, durableDirectory;
  final WereadStore Function(Book) store;
  final File Function(Book) sourceFile;

  Future<void> sync(Iterable<Book> books) async {
    final previous = _pending;
    final done = Completer<void>();
    _pending = done.future;
    await previous;
    Directory? staging;
    try {
      final localBooks = <Book>[];
      for (final book in books) {
        if (!book.isDeleted && _md5.hasMatch(book.md5?.toLowerCase() ?? '')) {
          localBooks.add(book);
        }
      }
      if (localBooks.isEmpty) return;
      await cache.create(recursive: true);
      staging = await cache.createTemp('weread-sync-');
      final exists = await client.readProps(root);
      if (exists != null && exists.isDir != true) {
        throw const FormatException('Invalid WeRead sync root');
      }
      final folders = exists == null
          ? <String>{}
          : {
              for (final entry in await client.readSyncDirectory(root))
                if (entry.isDir == true && _md5.hasMatch(entry.name ?? ''))
                  entry.name!,
            };
      for (final book in localBooks) {
        final id = book.md5!.toLowerCase();
        final local = store(book);
        if (WereadData.revision(await local.read()) == null &&
            !folders.contains(id)) {
          continue;
        }
        await _syncBook(id, local, staging);
      }
    } finally {
      try {
        if (staging != null) await staging.delete(recursive: true);
      } finally {
        done.complete();
      }
    }
  }

  Future<Map<String, dynamic>> _read(File file, String name, String id) async {
    if (await file.length() > WereadData.maxBytes ||
        (await sha256.bind(file.openRead()).first).toString() !=
            name.split('.').first) {
      throw const FormatException('WeRead sync integrity failure');
    }
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map<String, dynamic> ||
        raw['version'] != 1 ||
        raw['bookMd5'] != id) {
      throw const FormatException('WeRead sync source mismatch');
    }
    return WereadData.normalize(raw['data']);
  }

  Future<void> _download(String path, File file) =>
      client.downloadFile(path, file.path, onProgress: (bytes, _) {
        if (bytes > WereadData.maxBytes) {
          throw const FormatException('WeRead sync exceeds limit');
        }
      });

  Future<void> _publish(
      File file, String folder, String id, Directory stage) async {
    final name = file.uri.pathSegments.last;
    await _read(file, name, id);
    await client.mkdirAll(folder);
    await client.uploadFile(file.path, '$folder/$name');
    final verify = File('${stage.path}/verify.json');
    await _download('$folder/$name', verify);
    await _read(verify, name, id);
    final cached = File('${cache.path}/weread-sync-verified/$name');
    await cached.parent.create(recursive: true);
    await verify.copy(cached.path);
    await file.delete();
  }

  Future<void> _syncBook(String id, WereadStore local, Directory stage) async {
    final folder = '$root/$id';
    final destination =
        sha256.convert(utf8.encode(jsonEncode(client.syncIdentity)));
    final pending = Directory(
        '${durableDirectory.path}/weread-sync-pending/$destination/$id');
    await pending.create(recursive: true);
    await for (final file in pending.list(followLinks: false)) {
      if (file is File && _name.hasMatch(file.uri.pathSegments.last)) {
        await _publish(file, folder, id, stage);
      }
    }
    final names = <String>[];
    if (await client.readProps(folder) != null) {
      for (final entry in await client.readSyncDirectory(folder)) {
        if (const {'.DS_Store', 'Thumbs.db', 'desktop.ini'}
            .contains(entry.name)) {
          continue;
        }
        if (entry.isDir != false ||
            !_name.hasMatch(entry.name ?? '') ||
            (entry.size ?? 0) > WereadData.maxBytes ||
            names.length >= 1000) {
          throw const FormatException('Invalid WeRead snapshot listing');
        }
        names.add(entry.name!);
      }
    }
    names.sort();
    var merged = await local.read();
    var total = 0;
    for (final name in names) {
      var file = File('${cache.path}/weread-sync-verified/$name');
      Map<String, dynamic>? incoming;
      if (await file.exists()) {
        try {
          incoming = await _read(file, name, id);
        } catch (_) {
          // A corrupt transport cache is downloaded again, never trusted.
        }
      }
      if (incoming == null) {
        final download = File('${stage.path}/incoming.json');
        await _download('$folder/$name', download);
        incoming = await _read(download, name, id);
        await file.parent.create(recursive: true);
        await download.copy(file.path);
      }
      total += await file.length();
      if (total > 32 * WereadData.maxBytes) {
        throw const FormatException('WeRead sync scan exceeds limit');
      }
      merged = WereadData.merge(merged, incoming);
    }
    // Rereads under the store lock so an association changed during download wins.
    merged = await local.merge(merged);
    if (WereadData.revision(merged) == null) return;
    final bytes =
        utf8.encode(jsonEncode({'version': 1, 'bookMd5': id, 'data': merged}));
    if (bytes.length > WereadData.maxBytes) {
      throw const FormatException('WeRead sync snapshot exceeds limit');
    }
    final name = '${sha256.convert(bytes)}.json';
    if (!names.contains(name)) {
      final part = File('${pending.path}/$name.part');
      await part.writeAsBytes(bytes, flush: true);
      await _publish(
          await part.rename('${pending.path}/$name'), folder, id, stage);
    }
    // Only remove inputs read successfully and incorporated into this verified
    // successor. Concurrent uploads not in our listing remain untouched.
    for (final old in names.where((old) => old != name)) {
      await client.remove('$folder/$old');
    }
  }
}
