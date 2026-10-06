import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:xml/xml.dart';

import 'row_sync_store.dart';
import 'sync_paths.dart';

/// file_md5 describes the stored file, not the TXT/Markdown that produced it.
/// The stable sync ID may still describe that source: never rewrite it, note
/// foreign keys, positions or book paths when repairing an old checksum.
class ConvertedBookChecksum {
  ConvertedBookChecksum(this.db);
  final Database db;
  static final _digest = RegExp(r'^[a-fA-F0-9]{32}$');
  static const _checks = 'modu_converted_checksum_checks_v1';

  /// Seed the source identity and install the actual content hash atomically.
  /// This keeps import deduplication deterministic even though TXT's EPUB UUID
  /// and ZIP timestamps change each time it is converted.
  static Future<int> insert(DatabaseExecutor txn, Map<String, Object?> row,
      {required String sourceMd5}) async {
    final contentMd5 = row['file_md5'];
    if (!_digest.hasMatch(sourceMd5) ||
        contentMd5 is! String ||
        !_digest.hasMatch(contentMd5)) {
      throw const FormatException('Converted book requires both checksums');
    }
    final existing = await txn.query(syncRecordsTable,
        columns: ['sync_id'],
        where: "kind='book' AND sync_id=?",
        whereArgs: ['md5:${sourceMd5.toLowerCase()}']);
    if (existing.isNotEmpty) {
      // Never let an INSERT trigger move an existing identity to a new row.
      throw StateError('Converted book already has a bookshelf identity');
    }
    final id = await txn.insert('tb_books', {...row, 'file_md5': sourceMd5});
    await txn.update('tb_books', {'file_md5': contentMd5},
        where: 'id=?', whereArgs: [id]);
    return id;
  }

  /// Only the device retaining a local converted book can repair legacy data.
  /// NEVER call the detector on a downloaded file to bypass its expected hash.
  /// Unchanged ordinary EPUBs are inspected once, not on every sync/restart.
  Future<int> repairLocalBooks({
    required File Function(String relativePath) localFile,
    int? bookId,
  }) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS $_checks (
      book_id INTEGER PRIMARY KEY, fingerprint TEXT NOT NULL)''');
    final rows = await db.rawQuery('''SELECT b.* FROM tb_books b
      JOIN $syncRecordsTable r ON r.kind='book' AND r.local_id=b.id
      WHERE b.is_deleted=0 AND lower(b.file_path) LIKE 'file/%.epub'
      AND r.sync_id='md5:' || lower(b.file_md5)
      ${bookId == null ? '' : 'AND b.id=?'}''', bookId == null ? [] : [bookId]);
    var repaired = 0;
    for (final row in rows) {
      final expected = row['file_md5'];
      if (expected is! String || !_digest.hasMatch(expected)) continue;
      final path = row['file_path'] as String;
      SyncPaths.data(path);
      final file = localFile(path);
      final before = await file.stat();
      if (before.type != FileSystemEntityType.file) continue;
      final fingerprint = jsonEncode([
        path,
        expected,
        before.size,
        before.modified.microsecondsSinceEpoch,
        before.changed.microsecondsSinceEpoch
      ]);
      final checked = await db.query(_checks,
          where: 'book_id=? AND fingerprint=?',
          whereArgs: [row['id'], fingerprint]);
      if (checked.isNotEmpty) continue;
      final actual = await compute(_localConvertedHash, file.path);
      final after = await file.stat();
      if (before.size != after.size ||
          before.modified != after.modified ||
          before.changed != after.changed ||
          after.type != FileSystemEntityType.file) {
        continue;
      }
      await db.transaction((txn) async {
        // A replacement, deletion or concurrent sync may have happened during IO.
        final current = await txn.query('tb_books',
            columns: ['id'],
            where: 'id=? AND file_path=? AND file_md5=? AND is_deleted=0',
            whereArgs: [row['id'], path, expected]);
        if (current.isEmpty) return;
        if (actual != null && actual != expected.toLowerCase()) {
          await txn.update(
              'tb_books',
              {
                'file_md5': actual,
                'update_time': DateTime.now().toIso8601String(),
              },
              where: 'id=?',
              whereArgs: [row['id']]);
          repaired++;
        }
        await txn.insert(
            _checks, {'book_id': row['id'], 'fingerprint': fingerprint},
            conflictAlgorithm: ConflictAlgorithm.replace);
      });
    }
    return repaired;
  }
}

// Conservative recognizer for the exact historical Modu TXT/Markdown writers.
// Reject unrecognized layouts and broken ZIP members. This is trusted LOCAL
// migration evidence, not remote authenticity proof or a checksum bypass.
// No extraction, network or changes to the book bytes.
Future<String?> _localConvertedHash(String path) async {
  InputFileStream? input;
  Archive? archive;
  try {
    final file = File(path);
    if (await file.length() > 128 * 1024 * 1024) return null;
    input = InputFileStream(path);
    final decoder = ZipDecoder();
    archive = decoder.decodeBuffer(input);
    if (archive.length > 20000 ||
        decoder.directory.fileHeaders.length != archive.length ||
        decoder.directory.fileHeaders
            .any((h) => h.generalPurposeBitFlag & 1 != 0)) {
      return null;
    }
    var expanded = 0;
    for (final entry in archive) {
      expanded += entry.size;
      if (entry.size < 0 ||
          entry.size > 32 * 1024 * 1024 ||
          expanded > 256 * 1024 * 1024 ||
          entry.isSymbolicLink) {
        return null;
      }
    }
    String text(String name) {
      final entry = archive!.findFile(name);
      if (entry == null || entry.size > 4 * 1024 * 1024) {
        throw const FormatException();
      }
      return utf8.decode(entry.content as List<int>);
    }

    if (text('mimetype') != 'application/epub+zip') return null;
    final container = XmlDocument.parse(text('META-INF/container.xml'));
    if (container
            .findAllElements('rootfile')
            .single
            .getAttribute('full-path') !=
        'OEBPS/content.opf') {
      return null;
    }
    final opf = XmlDocument.parse(text('OEBPS/content.opf'));
    final package = opf.rootElement;
    final metadata = package.findElements('metadata').single;
    final identifier = metadata.findElements('dc:identifier').single;
    final txt = package.getAttribute('unique-identifier') == 'pub-id' &&
        identifier.getAttribute('id') == 'pub-id' &&
        RegExp(r'^urn:uuid:[0-9a-f-]{36}$').hasMatch(identifier.innerText) &&
        metadata.childElements.map((e) => e.name.qualified).join(',') ==
            'dc:title,dc:creator,dc:identifier' &&
        text('OEBPS/style.css') == 'body {\n\n}\n';
    final markdown = package.getAttribute('unique-identifier') == 'book-id' &&
        identifier.getAttribute('id') == 'book-id' &&
        RegExp(r'^urn:sha256:[0-9a-f]{64}$').hasMatch(identifier.innerText) &&
        metadata.childElements.map((e) => e.name.qualified).join(',') ==
            'dc:identifier,dc:title,dc:language,meta' &&
        metadata.findElements('meta').single.getAttribute('property') ==
            'dcterms:modified' &&
        metadata.findElements('meta').single.innerText ==
            '2000-01-01T00:00:00Z' &&
        text('OEBPS/style.css') ==
            'img { max-width:100%; height:auto; } pre { white-space:pre-wrap; overflow-wrap:anywhere; } '
                'table { border-collapse:collapse; max-width:100%; } td,th { border:1px solid currentColor; padding:.3em; } '
                'blockquote { margin-inline:1em; padding-inline-start:1em; border-inline-start:2px solid currentColor; }';
    if (!txt && !markdown) return null;
    final items =
        package.findElements('manifest').single.findElements('item').toList();
    final spine =
        package.findElements('spine').single.findElements('itemref').toList();
    if (spine.isEmpty) return null;
    final allowed = {'mimetype', 'META-INF/container.xml', 'OEBPS/content.opf'};
    for (final item in items) {
      final href = item.getAttribute('href') ?? '';
      if (!RegExp(r'^(style\.css|toc\.ncx|nav\.xhtml|xhtml/\d+\.xhtml|images/\d+\.(png|jpeg|gif|webp))$')
              .hasMatch(href) ||
          archive.findFile('OEBPS/$href') == null ||
          !allowed.add('OEBPS/$href')) {
        return null;
      }
    }
    for (var i = 0; i < spine.length; i++) {
      final id = '${txt ? 'item' : 'c'}$i';
      if (spine[i].getAttribute('idref') != id ||
          items
                  .where((e) =>
                      e.getAttribute('id') == id &&
                      e.getAttribute('href') == 'xhtml/$i.xhtml')
                  .length !=
              1) {
        return null;
      }
    }
    for (final entry in archive) {
      if (!entry.isFile) continue;
      if (!allowed.contains(entry.name)) return null;
      final bytes = entry.content as List<int>;
      if (bytes.length != entry.size || getCrc32(bytes) != entry.crc32) {
        return null;
      }
      if (RegExp(r'\.(xml|opf|ncx|xhtml)$').hasMatch(entry.name)) {
        XmlDocument.parse(utf8.decode(bytes));
      }
      entry.clear();
    }
    return (await md5.bind(file.openRead()).first).toString();
  } catch (_) {
    // Advisory migration only: unknown/corrupt files remain strictly checked.
    return null;
  } finally {
    await archive?.clear();
    await input?.close();
  }
}
