import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:anx_reader/service/local_data/backup_safety.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/utils/reading_progress.dart';

String _hash(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();
Future<String> _fileHash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Only extracts library data, never preferences, credentials, fonts or scripts
/// outside books. Runs off the UI isolate; validates all paths before writing.
Future<void> _extractAnxBackup(Map<String, String> args) async {
  final input = InputFileStream(args['zip']!);
  try {
    final decoder = ZipDecoder();
    final archive = decoder.decodeBuffer(input);
    try {
      validateBackupArchive(archive);
      if (decoder.directory.fileHeaders.length > 100000) {
        throw const FormatException('备份 ZIP 条目超过 10 万安全限制');
      }
      // ZipDecoder collapses exact duplicate names. Inspect original headers
      // first: ANX adds its databases directory twice, but conflicting copies
      // (for example a write in between the two copies) must not be accepted.
      final headers = <String, String>{};
      for (final header in decoder.directory.fileHeaders) {
        if (header.generalPurposeBitFlag & 1 != 0) {
          throw const FormatException('不支持加密 ZIP，请从 ANX 重新导出普通备份');
        }
        final key = header.filename.replaceAll('\\', '/').toLowerCase();
        if (key == 'databases/app_database.db-journal' &&
            (header.uncompressedSize ?? 0) > 0) {
          throw const FormatException('备份含未完成的数据库事务，请停止 ANX 阅读并重新导出');
        }
        final signature = '${header.uncompressedSize}:${header.crc32}';
        if (headers.containsKey(key) && headers[key] != signature) {
          throw const FormatException('备份包含相互冲突的重复文件，请停止 ANX 阅读后重新导出');
        }
        headers[key] = signature;
      }
      final seen = <String, String>{};
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final name = entry.name.replaceAll('\\', '/');
        if (name.contains('\u0000') ||
            name.split('/').any((part) =>
                part.endsWith('.') ||
                part.endsWith(' ') ||
                RegExp(r'[<>"|?*]').hasMatch(part))) {
          throw const FormatException('备份包含不兼容的文件名');
        }
        if (!(name.startsWith('file/') ||
            name.startsWith('cover/') ||
            name == 'databases/app_database.db' ||
            name == 'databases/app_database.db-wal')) {
          continue;
        }
        final destination = File(p.join(args['directory']!, name));
        destination.parent.createSync(recursive: true);
        // Upstream's export adds databases twice. Accept identical duplicates,
        // but never let a later, different SQLite/WAL entry overwrite the first.
        final temporary =
            File('${destination.path}.extract-${const Uuid().v4()}');
        final output = OutputFileStream(temporary.path);
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
        }
        var crc = 0;
        await for (final bytes in temporary.openRead()) {
          crc = getCrc32(bytes, crc);
        }
        if (await temporary.length() != entry.size ||
            (entry.crc32 != null && crc != entry.crc32)) {
          throw const FormatException('备份文件校验失败，请重新导出');
        }
        final digest = await _fileHash(temporary);
        final key = name.toLowerCase();
        if (seen.containsKey(key)) {
          temporary.deleteSync();
          if (seen[key] != digest) throw const FormatException('备份包含相互冲突的重复文件');
        } else {
          seen[key] = digest;
          temporary.renameSync(destination.path);
        }
      }
    } finally {
      archive.clearSync();
    }
  } finally {
    await input.close();
  }
}

class AnxImportResult {
  const AnxImportResult(this.addedBooks, this.addedNotes, this.backupPath);
  final int addedBooks;
  final int addedNotes;
  final String backupPath;
}

class _Asset {
  const _Asset(this.file, this.destination);
  final File file;
  final String destination;
}

class _AnxImportSource {
  const _AnxImportSource(this.root);
  final String root;
  String get databasePath => p.join(root, 'databases', 'app_database.db');
}

/// A read-only snapshot and validated import plan. No Modu data changes until
/// apply(). Original ANX databases are never opened/migrated/written by SQLite.
class AnxDatabaseImport {
  AnxDatabaseImport._(this.work, this._source, this.id);
  final Directory work;
  final _AnxImportSource _source;
  final String id;
  final records = <RowSyncRecord>[];
  final _assets = <_Asset>[];
  final missingBooks = <String>[];
  int skippedDeleted = 0;
  bool _applied = false;
  static bool _applying = false;

  int get books =>
      records.where((r) => r.kind == 'book').map((r) => r.id).toSet().length;
  int get notes =>
      records.where((r) => r.kind == 'note').map((r) => r.id).toSet().length;

  static Future<AnxDatabaseImport> prepare({
    required Directory cache,
    required File zip,
    DatabaseFactory? factory,
    void Function(String)? onProgress,
  }) async {
    await cache.create(recursive: true);
    final work = await cache.createTemp('anx-import-');
    try {
      onProgress?.call('正在校验并解压 ANX 备份…');
      final extracted = Directory(p.join(work.path, 'backup'));
      await compute(
          _extractAnxBackup, {'zip': zip.path, 'directory': extracted.path});
      final plan = AnxDatabaseImport._(
          work, _AnxImportSource(extracted.path), const Uuid().v4());
      await plan._read(factory ?? databaseFactory, onProgress);
      return plan;
    } catch (_) {
      await work.delete(recursive: true); // Only our new temporary directory.
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (await work.exists()) await work.delete(recursive: true);
  }

  Future<void> _read(
      DatabaseFactory factory, void Function(String)? progress) async {
    final original = File(_source.databasePath);
    if (!await original.exists()) {
      throw const FormatException('备份缺少 app_database.db，请从 ANX 重新导出完整 ZIP');
    }
    final journal = File('${original.path}-journal');
    if (await journal.exists() && await journal.length() > 0) {
      throw const FormatException('ANX 数据库正在写入或尚未恢复，请退出 ANX 后重试');
    }
    final copied = File(p.join(work.path, 'source.db'));
    final before = <String, String>{};
    for (final suffix in ['', '-wal']) {
      final file = File('${original.path}$suffix');
      if (!await file.exists()) continue;
      if (await file.length() > 256 * 1024 * 1024) {
        throw const FormatException('ANX 数据库或 WAL 超过 256 MiB 安全限制');
      }
      before[suffix] = await _fileHash(file);
      await file.copy('${copied.path}$suffix');
    }
    for (final suffix in ['', '-wal']) {
      final file = File('${original.path}$suffix');
      final after = await file.exists() ? await _fileHash(file) : null;
      if (after != before[suffix] ||
          (after != null &&
              await _fileHash(File('${copied.path}$suffix')) != after)) {
        throw const FormatException('ANX 数据库在复制过程中发生变化，请退出 ANX 后重试');
      }
    }
    final db = await factory.openDatabase(copied.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
    final tables = <String, List<Map<String, Object?>>>{};
    try {
      await db.execute('PRAGMA trusted_schema=OFF');
      final check = await db.rawQuery('PRAGMA quick_check');
      if (check.length != 1 || check.single.values.single != 'ok') {
        throw const FormatException('ANX 数据库完整性校验失败');
      }
      if (await db.getVersion() != 7) {
        throw const FormatException('目前支持 ANX 数据库第 7 版，请先更新 ANX 并重新导出备份');
      }
      final schema = await db.rawQuery(
          "SELECT name, type FROM sqlite_master WHERE type IN ('table','view','trigger')");
      if (schema.any((r) => r['type'] == 'trigger') ||
          schema.any((r) => r['name'] == syncRecordsTable)) {
        throw const FormatException('所选数据库不是原版 ANX 数据库，或包含未知触发器');
      }
      for (final name in [
        'tb_books',
        'tb_notes',
        'tb_groups',
        'tb_reading_time',
        'tb_styles'
      ]) {
        if (!schema.any((r) => r['name'] == name && r['type'] == 'table')) {
          throw FormatException('ANX 数据库缺少 $name');
        }
        final requiredColumns = switch (name) {
          'tb_books' => {
              'id',
              'title',
              'author',
              'file_path',
              'cover_path',
              'file_md5',
              'group_id',
              'is_deleted',
              'last_read_position',
              'reading_percentage'
            },
          'tb_notes' => {
              'id',
              'book_id',
              'content',
              'cfi',
              'type',
              'reader_note',
              'create_time',
              'update_time'
            },
          'tb_groups' => {'id', 'name', 'parent_id', 'is_deleted'},
          'tb_reading_time' => {'id', 'book_id', 'date', 'reading_time'},
          _ => {
              'id',
              'font_size',
              'font_family',
              'line_height',
              'letter_spacing'
            },
        };
        final columns = (await db.rawQuery('PRAGMA table_info($name)'))
            .map((r) => r['name'])
            .toSet();
        if (!columns.containsAll(requiredColumns)) {
          throw FormatException('ANX 数据表 $name 结构不兼容');
        }
        final rows = await db.query(name, limit: 200001);
        if (rows.length > 200000) throw const FormatException('ANX 数据库记录数量超限');
        final ids = <int>{};
        for (final row in rows) {
          if (row['id'] is! int || !ids.add(row['id'] as int)) {
            throw const FormatException('ANX 数据库记录标识无效');
          }
        }
        tables[name] = rows;
      }
    } finally {
      await db.close();
    }

    final groups = <int, String>{0: 'root'};
    final parents = <int, int>{};
    for (final row in tables['tb_groups']!) {
      if (row['id'] == 0) continue;
      groups[row['id'] as int] =
          'legacy:${_hash([row['id'], row['name'], row['create_time']])}';
      parents[row['id'] as int] = row['parent_id'] as int? ?? 0;
    }
    for (var group in parents.keys) {
      final seen = <int>{};
      while (group != 0) {
        if (!seen.add(group) || !parents.containsKey(group)) {
          throw const FormatException('ANX 文件夹包含循环或失效关联');
        }
        group = parents[group]!;
      }
    }
    for (final row in tables['tb_groups']!) {
      final group = row['id'] as int;
      if (group == 0) continue; // Keep Modu's own root.
      final parent = row['parent_id'] as int? ?? 0;
      if (!groups.containsKey(parent)) {
        throw const FormatException('ANX 文件夹关联无效');
      }
      _add('group', groups[group]!, {
        'name': row['name'],
        'parent_id': groups[parent],
        'is_deleted': row['is_deleted'] ?? 0,
        'create_time': row['create_time'],
        'update_time': row['update_time'],
      });
    }
    final bookIds = <int, String>{};
    for (final row in tables['tb_books']!) {
      if (row['is_deleted'] == 1) {
        skippedDeleted++;
        continue;
      }
      progress?.call('正在准备：${row['title'] ?? ''}');
      final filePath = _relative(row['file_path'], 'file');
      final file = await _sourceFile(filePath);
      if (file == null) {
        missingBooks.add(row['title'] as String? ?? filePath);
        continue; // Do not create an unreadable book or orphan notes.
      }
      final digest = (await md5.bind(file.openRead()).first).toString();
      final key = 'md5:$digest';
      bookIds[row['id'] as int] = key;
      final extension = p.posix.extension(filePath).toLowerCase();
      final safeExtension = RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension)
          ? extension
          : '.epub';
      // The shelf/sync file enumerators expect flat resource directories.
      final target = 'file/anx-$id-${_hash(key)}$safeExtension';
      await _stage(file, target);
      // Verify actual book bytes rather than trusting an outdated DB hash.
      if ((await md5.bind(_assets.last.file.openRead()).first).toString() !=
          digest) {
        throw const FormatException('书籍文件在复制时发生变化，请退出 ANX 后重试');
      }
      String cover = '';
      if (row['cover_path'] != null && row['cover_path'] != '') {
        final path = _relative(row['cover_path'], 'cover');
        final image = await _sourceFile(path);
        if (image != null) {
          cover = 'cover/anx-$id-${_hash(key)}';
          await _stage(image, cover);
        }
      }
      final group = groups[row['group_id'] ?? 0];
      if (group == null) throw const FormatException('ANX 书籍文件夹关联无效');
      _add('book', key, {
        'title': row['title'] ?? '',
        'author': row['author'] ?? '',
        'description': row['description'],
        'rating': row['rating'],
        'file_path': target,
        'cover_path': cover,
        'file_md5': digest,
        'group_id': group,
        'create_time': row['create_time'],
        'update_time': row['update_time'],
      });
      _add('position', key, {
        'last_read_position': row['last_read_position'] ?? '',
        'reading_percentage':
            normalizeReadingProgress(row['reading_percentage'] as num?)
      });
      _add('life', key, {'is_deleted': 0});
    }
    for (final row in tables['tb_notes']!) {
      final book = bookIds[row['book_id']];
      if (book == null) continue;
      _add(
          'note',
          'legacy:${_hash([book, row['id'], row['cfi'], row['create_time']])}',
          {
            for (final field in [
              'content',
              'cfi',
              'chapter',
              'type',
              'color',
              'create_time',
              'update_time',
              'reader_note'
            ])
              field: row[field],
            'book_id': book,
          });
    }
    final times = <String, Map<String, Object?>>{};
    for (final row in tables['tb_reading_time']!) {
      final book = bookIds[row['book_id']];
      if (book == null) continue;
      final date = row['date'] as String? ?? '';
      final duration = row['reading_time'];
      if (DateTime.tryParse(date) == null ||
          date.length < 10 ||
          duration is! int ||
          duration < 0) {
        throw const FormatException('ANX 阅读时长无效');
      }
      final key = 'legacy:${_hash([book, date.substring(0, 10)])}';
      final previous = times[key];
      times[key] = {
        'book_id': book,
        'date': date.substring(0, 10),
        'reading_time': duration + (previous?['reading_time'] as int? ?? 0)
      };
    }
    for (final entry in times.entries) {
      _add('time', entry.key, entry.value);
    }
    final tags = <int, String>{};
    for (final row in tables['tb_styles']!) {
      if (row['font_size'] != 1 || row['font_family'] is! String) continue;
      final key =
          'legacy:${_hash((row['font_family'] as String).toLowerCase())}';
      tags[row['id'] as int] = key;
      _add('tag', key, {
        'font_size': 1,
        'font_family': row['font_family'],
        'line_height': row['line_height']
      });
    }
    for (final row in tables['tb_styles']!) {
      if (row['font_size'] != 2) continue;
      final book = bookIds[(row['line_height'] as num?)?.toInt()];
      final tag = tags[(row['letter_spacing'] as num?)?.toInt()];
      if (book == null || tag == null) continue;
      _add('tag_link', '$book:$tag',
          {'font_size': 2, 'line_height': book, 'letter_spacing': tag});
    }
    for (final record in records) {
      RowSyncStore.validate(record);
    }
  }

  void _add(String kind, String key, Map<String, Object?> data) {
    const textFields = {
      'title',
      'author',
      'description',
      'content',
      'cfi',
      'chapter',
      'type',
      'color',
      'reader_note',
      'name',
      'font_family',
      'last_read_position',
      'create_time',
      'update_time',
      'date'
    };
    for (final entry in data.entries) {
      if (textFields.contains(entry.key) &&
          entry.value != null &&
          entry.value is! String) {
        throw const FormatException('ANX 数据库文本字段类型无效');
      }
    }
    if (kind == 'group' &&
        (data['name'] is! String || ![0, 1].contains(data['is_deleted']))) {
      throw const FormatException('ANX 文件夹字段无效');
    }
    for (final field in ['rating', 'line_height']) {
      if (kind == 'tag_link') continue;
      if (data[field] != null && data[field] is! num) {
        throw const FormatException('ANX 数值字段类型无效');
      }
    }
    final date = data['update_time'] ?? data['create_time'] ?? data['date'];
    records.add(RowSyncRecord(
        kind,
        key,
        date is String
            ? DateTime.tryParse(date)?.millisecondsSinceEpoch ?? 0
            : 0,
        'legacy',
        false,
        data));
  }

  String _relative(Object? value, String folder) {
    if (value is! String || value.isEmpty) {
      throw const FormatException('ANX 书籍路径为空');
    }
    var path = value.replaceAll('\\', '/');
    // Old Android exports stored absolute app_flutter paths. Rebase only the
    // known resource suffix; never open arbitrary absolute paths from a DB.
    if (!path.startsWith('$folder/')) {
      final index = path.lastIndexOf('/$folder/');
      if (index < 0) throw const FormatException('ANX 资源路径无效');
      path = path.substring(index + 1);
    }
    if (path.contains(':') ||
        path.contains('\u0000') ||
        path
            .split('/')
            .any((part) => part == '..' || part == '.' || part.isEmpty)) {
      throw const FormatException('ANX 资源路径越界');
    }
    return path;
  }

  Future<File?> _sourceFile(String relative) async {
    final file = File(p.join(_source.root, relative));
    if (!await file.exists()) return null;
    final root = await Directory(_source.root).resolveSymbolicLinks();
    final resolved = await file.resolveSymbolicLinks();
    if (!p.isWithin(root, resolved)) {
      throw const FormatException('ANX 资源链接指向数据目录之外');
    }
    return File(resolved);
  }

  Future<void> _stage(File source, String destination) async {
    final local = File(p.join(work.path, 'assets', destination));
    await local.parent.create(recursive: true);
    await source.copy(local.path);
    _assets.add(_Asset(local, destination));
  }

  Future<AnxImportResult> apply(Database target, Directory targetRoot) async {
    if (_applied || _applying) throw StateError('导入正在进行或已经完成');
    _applying = true;
    final installed = <File>[];
    bool committed = false;
    try {
      if (p.equals(
          p.normalize(_source.databasePath), p.normalize(target.path))) {
        throw const FormatException('不能将当前默读数据库作为 ANX 来源');
      }
      final store = RowSyncStore(target);
      final before = await store.snapshot();
      final existing = {
        for (final r in before.where((r) => r.kind == 'book' && !r.deleted))
          r.data['file_md5']: r
      };
      final destinations = <String, String?>{};
      for (final book in records.where((r) => r.kind == 'book')) {
        final hash = book.data['file_md5'];
        final current = hash == null ? null : existing[hash];
        if (current != null) {
          destinations[book.data['file_path'] as String] =
              current.data['file_path'] as String;
          final cover = current.data['cover_path'];
          destinations[book.data['cover_path'] as String] =
              cover is String && cover.isNotEmpty ? cover : null;
        }
      }
      final recovery = Directory(p.join(targetRoot.path, 'import-backups'));
      await recovery.create(recursive: true);
      final backup = p.join(recovery.path, 'before-anx-$id.db');
      // A consistent local recovery snapshot, including WAL. Never checkpoint
      // or rewrite ANX's database. Failure here aborts before the import.
      await target.execute("VACUUM INTO '${backup.replaceAll("'", "''")}'");
      for (final asset in _assets) {
        if (destinations.containsKey(asset.destination) &&
            destinations[asset.destination] == null) {
          continue;
        }
        final relative = destinations[asset.destination] ?? asset.destination;
        // Reuse only validated relative paths from the existing library.
        final folder = relative.startsWith('file/') ? 'file' : 'cover';
        if (_relative(relative, folder) != relative) {
          throw const FormatException('默读资源路径无效');
        }
        final destination = File(p.join(targetRoot.path, relative));
        if (await destination.exists()) {
          continue; // Never overwrite existing bytes.
        }
        var directory = targetRoot;
        for (final segment in p.posix.split(p.posix.dirname(relative))) {
          directory = Directory(p.join(directory.path, segment));
          if (await FileSystemEntity.type(directory.path, followLinks: false) ==
              FileSystemEntityType.link) {
            throw const FormatException('默读资源目录链接越界');
          }
          await directory.create();
        }
        final realParent = await destination.parent.resolveSymbolicLinks();
        if (!p.isWithin(await targetRoot.resolveSymbolicLinks(), realParent)) {
          throw const FormatException('默读资源目录链接越界');
        }
        await destination.create(exclusive: true);
        installed.add(destination);
        await asset.file.copy(destination.path);
      }
      final after = await store.merge(records, importOnlyMissingRecords: true);
      committed = true;
      _applied = true;
      int count(List<RowSyncRecord> rows, String kind) =>
          rows.where((r) => r.kind == kind && !r.deleted).length;
      return AnxImportResult(count(after, 'book') - count(before, 'book'),
          count(after, 'note') - count(before, 'note'), backup);
    } finally {
      try {
        if (!committed) {
          // New files only; existing files were never overwritten. Keep a file
          // if a concurrent successful operation has begun referencing it.
          final used = await target
              .query('tb_books', columns: ['file_path', 'cover_path']);
          final paths =
              used.expand((r) => [r['file_path'], r['cover_path']]).toSet();
          for (final file in installed) {
            if (!paths.contains(p
                    .relative(file.path, from: targetRoot.path)
                    .replaceAll('\\', '/')) &&
                await file.exists()) {
              await file.delete();
            }
          }
        }
      } finally {
        _applying = false;
      }
    }
  }
}
