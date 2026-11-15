import 'dart:convert';
import 'dart:io';

import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/service/sync/private_book_sync.dart';
import 'package:modu_reader/service/sync/row_sync_record.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class PortableBackupSelection {
  const PortableBackupSelection(this.publicBookIds, this.assets);
  final Set<int> publicBookIds;
  final Set<String> assets;
}

String _identifier(String name) => '"${name.replaceAll('"', '""')}"';

/// Operates only on the disposable export snapshot, never the live database.
Future<PortableBackupSelection> sanitizePortableBackup(File snapshot,
    {PrivateLibrary? library, DatabaseFactory? factory}) async {
  final privacy = library ?? PrivateLibrary.instance;
  if (privacy.corrupt) throw StateError('Cannot filter a private backup');
  final db = await (factory ?? databaseFactory).openDatabase(snapshot.path,
      options: OpenDatabaseOptions(singleInstance: false));
  final publicIds = <int>{}, assets = <String>{};
  try {
    await db.rawQuery('PRAGMA journal_mode=DELETE');
    final secure = await db.rawQuery('PRAGMA secure_delete=ON');
    if (secure.isEmpty || secure.first.values.first != 1) {
      throw StateError('Cannot sanitize the export database');
    }
    final schema =
        (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
            .map((row) => row['name'])
            .toSet();
    if (schema.containsAll(
        {'modu_sync_records', 'modu_sync_control', 'tb_sync_secrets'})) {
      await RowSyncStore(db).snapshot();
    }
    await db.transaction((txn) async {
      final tables = (await txn
              .rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((row) => row['name'] as String)
          .toSet();
      final books = await txn.query('tb_books');
      final booksById = {for (final book in books) book['id']: book};
      final privateIds = <int>{}, privateAssets = <String>{};
      for (final row in books) {
        final allowed =
            privacy.canSyncBook(Book.fromDb(Map<String, dynamic>.from(row)));
        (allowed ? publicIds : privateIds).add(row['id'] as int);
      }
      final metadata = tables.contains('modu_sync_records')
          ? await txn.query('modu_sync_records')
          : <Map<String, Object?>>[];
      final records = metadata.map(RowSyncRecord.fromMap).toList();
      final seeds = <RowSyncRecord>[...records];
      for (final row in metadata.where((row) => row['kind'] == 'book')) {
        final book = booksById[row['local_id']];
        if (book == null) continue;
        final record = RowSyncRecord.fromMap(row);
        seeds.add(RowSyncRecord(record.kind, record.id, record.clock,
            record.revision, record.deleted, {
          ...record.data,
          'file_path': book['file_path'],
          'file_md5': book['file_md5']
        }));
      }
      final filter = PrivateBookSyncFilter(seeds, library: privacy);
      final allowedRecords =
          filter.allowedRecords(records).map((record) => record.key).toSet();
      final blockedLocal = <String, Set<int>>{
        for (final kind in ['book', 'position', 'life', 'review'])
          kind: privateIds,
      };
      for (final row in metadata) {
        if (!allowedRecords.contains('${row['kind']}/${row['sync_id']}') &&
            row['local_id'] is int) {
          blockedLocal
              .putIfAbsent(row['kind'] as String, () => {})
              .add(row['local_id'] as int);
        }
      }
      publicIds.removeAll(privateIds);
      assets.clear();
      privateAssets.clear();
      for (final row in books) {
        for (final key in ['file_path', 'cover_path']) {
          final path = row[key];
          if (path is String && path.isNotEmpty) {
            (privateIds.contains(row['id']) ? privateAssets : assets).add(path);
          }
        }
      }
      assets.removeAll(privateAssets);
      // Suppress only this copy's change tracking: filtering is not a deletion.
      final controls = tables.contains('modu_sync_control')
          ? await txn.query('modu_sync_control')
          : <Map<String, Object?>>[];
      if (controls.isNotEmpty) {
        await txn.update('modu_sync_control', {'applying': 1});
      }
      for (final table in tables.where((name) =>
          !name.startsWith('sqlite_') && name != 'modu_sync_records')) {
        final columns =
            await txn.rawQuery('PRAGMA table_info(${_identifier(table)})');
        if (!columns.any((column) => column['name'] == 'book_id')) continue;
        final rows = await txn.query(table);
        final deletedOwners = <Object?>{};
        for (final row in rows) {
          final bookId = row['book_id'];
          final denied = privateIds.contains(bookId) ||
              (table == 'modu_replaced_book_files' &&
                  (!filter.allows(RowSyncRecord('position', bookId.toString(),
                          0, '', false, const {})) ||
                      !privacy.canSyncSource(
                          md5: row['old_md5'] as String?,
                          filePath: row['old_path'] as String?)));
          if (!denied) continue;
          final kind = switch (table) {
            'tb_notes' => 'note',
            'tb_reading_time' => 'time',
            'tb_reading_rounds' => 'round',
            _ => null
          };
          if (kind != null && row['id'] is int) {
            blockedLocal.putIfAbsent(kind, () => {}).add(row['id'] as int);
          }
          if (table == 'modu_replaced_book_files') {
            await txn.delete(table,
                where: 'book_id=? AND old_path=?',
                whereArgs: [bookId, row['old_path']]);
          } else if (deletedOwners.add(bookId)) {
            await txn.delete(table, where: 'book_id=?', whereArgs: [bookId]);
          }
        }
      }
      if (tables.contains('tb_styles')) {
        for (final id in privateIds) {
          final links = await txn.query('tb_styles',
              columns: ['id'],
              where: 'font_size=2 AND line_height=?',
              whereArgs: [id]);
          blockedLocal
              .putIfAbsent('tag_link', () => {})
              .addAll(links.map((row) => row['id'] as int));
          await txn.delete('tb_styles',
              where: 'font_size=2 AND line_height=?', whereArgs: [id]);
        }
      }
      for (final row in metadata) {
        if (!allowedRecords.contains('${row['kind']}/${row['sync_id']}') ||
            (blockedLocal[row['kind']]?.contains(row['local_id']) ?? false)) {
          await txn.delete('modu_sync_records',
              where: 'kind=? AND sync_id=?',
              whereArgs: [row['kind'], row['sync_id']]);
        }
      }
      for (final id in privateIds) {
        await txn.delete('tb_books', where: 'id=?', whereArgs: [id]);
      }
      for (final id in blockedLocal['group'] ?? <int>{}) {
        await txn.delete('tb_groups', where: 'id=?', whereArgs: [id]);
      }
      for (final id in blockedLocal['tag'] ?? <int>{}) {
        await txn.delete('tb_styles',
            where: 'id=? AND font_size=1', whereArgs: [id]);
      }
      if (controls.isNotEmpty) {
        await txn.update(
            'modu_sync_control', {'applying': controls.first['applying']});
      }
    });
    // Remove private bytes from freelist pages as well as logical rows.
    await db.execute('VACUUM');
    final check = await db.rawQuery('PRAGMA quick_check');
    if (check.length != 1 || check.single.values.single != 'ok') {
      throw StateError('Invalid sanitized export');
    }
  } finally {
    await db.close();
  }
  for (final suffix in ['-wal', '-shm', '-journal']) {
    if (await File('${snapshot.path}$suffix').exists()) {
      throw StateError('Export snapshot is not standalone');
    }
  }
  return PortableBackupSelection(publicIds, assets);
}

Map<String, dynamic> portableBackupPreferences(
    Map<String, dynamic> backup, Set<int> publicIds) {
  final result = Map<String, dynamic>.from(backup);
  result.remove('privateLibrary_v1');
  result.removeWhere((key, _) =>
      key.startsWith('ttsRoleBook_') &&
      !publicIds.contains(int.tryParse(key.substring('ttsRoleBook_'.length))));
  if (result['bookTranslationModes'] case final Map entry) {
    try {
      final modes = jsonDecode(entry['value'] as String) as Map;
      result['bookTranslationModes'] = {
        ...entry,
        'value': jsonEncode({
          for (final e in modes.entries)
            if (publicIds.contains(int.tryParse(e.key.toString())))
              e.key: e.value
        })
      };
    } catch (_) {
      result.remove('bookTranslationModes');
    }
  }
  return result;
}

Future<String> portableBackupAiHistory(
    Directory documents, PortableBackupSelection selection,
    {PrivateLibrary? library}) async {
  final privacy = library ?? PrivateLibrary.instance;
  final file = File(p.join(documents.path, 'ai', 'ai_history.json'));
  if (!await file.exists()) return '[]';
  if (await file.length() > 32 * 1024 * 1024) {
    throw StateError('AI backup is too large');
  }
  try {
    final rows = jsonDecode(await file.readAsString()) as List;
    return jsonEncode(rows.where((row) {
      if (row is! Map || row['id'] is! String) return false;
      final request = row['readingRequest'];
      final bookId = request is Map ? request['bookId'] : null;
      return privacy.canSyncHistory(row['id'] as String,
              unscoped: bookId == null) &&
          (bookId == null || selection.publicBookIds.contains(bookId));
    }).toList());
  } catch (_) {
    return '[]';
  }
}
