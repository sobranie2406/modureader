import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const backupDirectories = {'file', 'cover', 'font', 'bgimg', 'databases', 'ai'};
const backupPrefsFiles = {'modu_shared_prefs.json', 'anx_shared_prefs.json'};

/// Validate the entire archive before extracting any entry. No links, path
/// traversal, absolute paths, unknown roots, or unbounded expansion.
void validateBackupArchive(Archive archive) {
  if (archive.length > 100000) throw const FormatException('备份文件数量超限');
  var bytes = 0;
  for (final entry in archive) {
    final name = entry.name.replaceAll('\\', '/');
    final parts = name.split('/');
    bytes += entry.size;
    if (bytes > 20 * 1024 * 1024 * 1024 ||
        entry.isSymbolicLink ||
        p.posix.isAbsolute(name) ||
        name.contains(':') ||
        parts.any((part) => part == '..' || part == '.') ||
        !(backupDirectories.contains(parts.first) ||
            backupPrefsFiles.contains(name))) {
      throw const FormatException('备份包含不安全的路径、链接、未知文件或超大内容');
    }
  }
  if (!archive.any(
      (entry) => entry.name == 'databases/app_database.db' && entry.isFile)) {
    throw const FormatException('备份缺少书库数据库，未修改现有数据');
  }
}

Future<Map<String, dynamic>?> readBackupPreferences(Directory source) async {
  for (final name in backupPrefsFiles) {
    final file = File(p.join(source.path, name));
    if (!await file.exists()) continue;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('备份设置格式无效');
    }
    return decoded;
  }
  return null;
}

Future<void> validateBackupDatabase(Directory source,
    {DatabaseFactory? factory, int? maxSchemaVersion}) async {
  final db = await (factory ?? databaseFactory).openDatabase(
    p.join(source.path, 'databases', 'app_database.db'),
    options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
  );
  try {
    final version = await db.getVersion();
    if (maxSchemaVersion != null && version > maxSchemaVersion) {
      throw const FormatException('备份由更新版本的默读创建，请先升级应用');
    }
    final check = await db.rawQuery('PRAGMA quick_check');
    if (check.length != 1 || check.single.values.single != 'ok') {
      throw const FormatException('备份数据库损坏');
    }
    final tables =
        (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
            .map((row) => row['name'])
            .toSet();
    if (!tables.containsAll({
      'tb_books',
      'tb_notes',
      'tb_reading_time',
      'tb_themes',
      'tb_groups'
    })) {
      throw const FormatException('不是兼容的默读书库数据库');
    }
    for (final row in await db
        .rawQuery('SELECT file_path, cover_path, is_deleted FROM tb_books')) {
      for (final column in ['file_path', 'cover_path']) {
        final value = row[column];
        if (value == null || value == '') continue;
        final prefix = column == 'file_path' ? 'file/' : 'cover/';
        if (value is! String ||
            !value.startsWith(prefix) ||
            value.contains('\\') ||
            value.split('/').any((part) => part == '..' || part == '.') ||
            value.contains(':')) {
          throw const FormatException('备份数据库包含不安全的书籍路径');
        }
      }
      final bookPath = row['file_path'];
      if (row['is_deleted'] != 1 &&
          bookPath is String &&
          bookPath.isNotEmpty &&
          !await File(p.join(source.path, bookPath)).exists()) {
        throw const FormatException('备份缺少书籍文件，已停止恢复。请在原设备下载完整书籍后重新导出。');
      }
    }
  } finally {
    await db.close();
  }
}

/// Stage in each target's own filesystem, then swap. Retain recovery copies on
/// success; roll back in reverse order on an exception. Not a power-loss-atomic
/// cross-directory transaction.
class BackupDirectoryTransaction {
  final _staged = <Directory, Directory>{};
  final _saved = <Directory, Directory>{};
  final _installed = <Directory>[];
  final _work = <Directory>[];

  Future<void> stage(Directory source, Map<String, Directory> targets) async {
    for (final entry in targets.entries) {
      if (!backupDirectories.contains(entry.key)) {
        throw ArgumentError('Unknown backup directory');
      }
      final incoming = Directory(p.join(source.path, entry.key));
      if (!await incoming.exists()) continue;
      await entry.value.parent.create(recursive: true);
      final work =
          await entry.value.parent.createTemp('.modu-restore-${entry.key}-');
      _work.add(work);
      final staging = Directory(p.join(work.path, 'incoming'));
      await _copy(incoming, staging);
      _staged[entry.value] = staging;
    }
  }

  Future<void> commit({required Future<void> Function() applySettings}) async {
    try {
      for (final entry in _staged.entries) {
        if (await entry.key.exists()) {
          final saved = Directory(p.join(entry.value.parent.path, 'previous'));
          await entry.key.rename(saved.path);
          _saved[entry.key] = saved;
        }
        await entry.value.rename(entry.key.path);
        _installed.add(entry.key);
      }
      await applySettings();
    } catch (_) {
      await rollback();
      rethrow;
    }
  }

  Future<void> rollback() async {
    for (final target in _installed.reversed) {
      // Preserve the failed replacement for diagnosis, never delete the backup.
      final staged = _staged[target]!;
      if (await target.exists()) {
        await target.rename(p.join(staged.parent.path, 'failed'));
      }
    }
    _installed.clear();
    for (final entry in _saved.entries.toList().reversed) {
      if (await entry.value.exists()) await entry.value.rename(entry.key.path);
    }
    _saved.clear();
  }

  List<String> get recoveryPaths => _saved.values.map((d) => d.path).toList();

  /// Remove only unused incoming copies created by this transaction. Keep
  /// previous/failed replacements for recovery, including after a failed swap.
  Future<void> cleanStaging() async {
    for (final work in _work) {
      final incoming = Directory(p.join(work.path, 'incoming'));
      if (await incoming.exists()) await incoming.delete(recursive: true);
      if (await work.exists() && await work.list().isEmpty) await work.delete();
    }
  }

  Future<void> _copy(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final destination = p.join(target.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(destination);
      } else if (entity is Directory) {
        await _copy(entity, Directory(destination));
      } else {
        throw const FormatException('备份不能包含链接');
      }
    }
  }
}

/// Conservative default: credentials can be embedded in arbitrary provider
/// headers/endpoints, so omit the entire credential-bearing setting container.
Map<String, dynamic> withoutBackupCredentials(Map<String, dynamic> backup) => {
      for (final entry in backup.entries)
        if (!isCredentialPreference(entry.key)) entry.key: entry.value,
    };

bool isCredentialPreference(String key) =>
    {
      'aiProviders',
      'vectorModelConfig',
      'webdavInfo',
      'ftpInfo',
      'sftpInfo',
      'syncAiSettingsEncryptionPassword',
      'syncAiSettingsToWebdav'
    }.contains(key) ||
    ['aiConfig_', 'onlineTtsConfig_', 'translateServiceConfig_']
        .any(key.startsWith) ||
    RegExp(r'(apikey|api_key|secret|password|authorization|accessToken|refreshToken|(^|_)token($|_))',
            caseSensitive: false)
        .hasMatch(key);

void validatePreferencesBackup(Map<String, dynamic>? backup) {
  if (backup == null) return;
  if (backup['__prefsBackupVersion'] != 1) {
    throw const FormatException('不支持的备份设置版本');
  }
  for (final entry in backup.entries) {
    if (entry.key == '__prefsBackupVersion') continue;
    final data = entry.value;
    if (data is! Map) throw const FormatException('备份设置条目无效');
    final value = data['value'];
    final valid = switch (data['type']) {
      'bool' => value is bool,
      'int' => value is int,
      'double' => value is num && value.isFinite,
      'string' => value is String,
      'stringList' => value is List && value.every((item) => item is String),
      _ => false,
    };
    if (!valid) throw const FormatException('备份设置类型无效');
  }
}
