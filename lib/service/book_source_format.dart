import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/sync/converted_book_checksum.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

/// Local display cache only; stored paths, checksums and sync rows stay intact.
class BookSourceFormat {
  BookSourceFormat(this.prefs);
  final SharedPreferences prefs;
  // Limit legacy ZIP inspection to one worker, outside the rendering isolate.
  static Future<void> _work = Future.value();

  String _key(Book book) =>
      'bookSourceFormat.v1.${sha256.convert(utf8.encode(jsonEncode([
            book.filePath,
            book.md5
          ])))}';

  Map? _cached(Book book) {
    try {
      final value = jsonDecode(prefs.getString(_key(book)) ?? 'null');
      return value is Map ? value : null;
    } catch (_) {
      return null;
    }
  }

  String format(Book book) {
    final extension =
        path.extension(book.filePath).replaceFirst('.', '').toUpperCase();
    if (extension != 'EPUB') return extension == 'MARKDOWN' ? 'MD' : extension;
    final cached = _cached(book)?['format'];
    return ['TXT', 'MD', 'UMD'].contains(cached) ? cached as String : extension;
  }

  Future<void> remember(Book book, String sourceFormat) async {
    final format = sourceFormat.toUpperCase();
    if (!['TXT', 'MD', 'MARKDOWN', 'UMD'].contains(format)) return;
    final stat = await File(book.fileFullPath).stat();
    if (stat.type != FileSystemEntityType.file) return;
    await _save(book, stat, format == 'MARKDOWN' ? 'MD' : format);
  }

  Future<void> _save(Book book, FileStat stat, String format) async {
    await prefs.setString(
        _key(book),
        jsonEncode({
          'format': format,
          'size': stat.size,
          'modified': stat.modified.microsecondsSinceEpoch,
          'changed': stat.changed.microsecondsSinceEpoch,
        }));
  }

  Future<String> resolve(Book book) {
    if (path.extension(book.filePath).toLowerCase() != '.epub') {
      return Future.value(format(book));
    }
    final operation = _work.then((_) async {
      try {
        final file = File(book.fileFullPath);
        final before = await file.stat();
        // Do not negative-cache remote-only books: retry after download.
        if (before.type != FileSystemEntityType.file) return format(book);
        final cached = _cached(book);
        if (cached?['size'] == before.size &&
            cached?['modified'] == before.modified.microsecondsSinceEpoch &&
            cached?['changed'] == before.changed.microsecondsSinceEpoch) {
          return format(book);
        }
        final detected = await compute(convertedBookSourceFormat, file.path);
        final after = await file.stat();
        if (after.type == FileSystemEntityType.file &&
            before.size == after.size &&
            before.modified == after.modified &&
            before.changed == after.changed) {
          await _save(book, after, detected ?? 'EPUB');
          return detected ?? 'EPUB';
        }
      } catch (_) {
        // An optional badge must never prevent opening the bookshelf.
      }
      return format(book);
    });
    _work = operation.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return operation;
  }
}
