import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Run before opening any database, starting sync, or starting the reader.
/// Sources remain as a recovery copy; they are never used again after commit.
class AndroidStorageMigration {
  AndroidStorageMigration({
    required this.documents,
    required this.databases,
    required this.destination,
  });

  final Directory documents;
  final Directory databases;
  final Directory destination;
  static const stateName = '.modu-external-storage-v1.json';
  static const receiptName = '.modu-storage-v1.json';

  Future<void> run() async {
    final target = p.normalize(destination.absolute.path);
    for (final source in [documents, databases]) {
      final from = p.normalize(source.absolute.path);
      if (from == target ||
          p.isWithin(from, target) ||
          p.isWithin(target, from)) {
        throw const FileSystemException('迁移源目录与目标目录不能重叠');
      }
    }
    await _directory(documents);
    final stateFile = File(p.join(documents.path, stateName));
    final receiptFile = File(p.join(target, receiptName));
    Map<String, dynamic> state;
    if (await stateFile.exists()) {
      state = await _readState(stateFile);
      if (state['target'] != target) {
        throw const FileSystemException('应用数据目录已改变，请恢复原存储位置后重试');
      }
    } else {
      if (await receiptFile.exists()) {
        throw const FileSystemException('目标目录已有迁移记录，请勿覆盖现有数据');
      }
      final random = Random.secure();
      state = {
        'version': 1,
        'id': List.generate(16,
                (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
            .join(),
        'target': target,
        'complete': false,
        'database':
            await File(p.join(databases.path, 'app_database.db')).exists(),
      };
      await _writeState(stateFile, state);
    }

    if (await receiptFile.exists()) {
      final receipt = await _readState(receiptFile);
      if (receipt['id'] != state['id'] ||
          receipt['target'] != target ||
          receipt['complete'] != true) {
        throw const FileSystemException('应用数据迁移记录不一致，已停止以保护数据');
      }
      if (state['database'] == true &&
          !await File(p.join(target, 'databases', 'app_database.db'))
              .exists()) {
        throw const FileSystemException('已迁移的数据库缺失，请恢复数据后重试');
      }
      // A process may have stopped between publishing the two receipts.
      if (state['complete'] != true) {
        await _writeState(stateFile, {...state, 'complete': true});
      }
      return;
    }
    if (state['complete'] == true) {
      // Never fall back to the stale private database or silently create a new one.
      throw const FileSystemException('Android/data 应用数据不可用，请检查存储后重试');
    }

    await _directory(destination);
    final staging = Directory(p.join(target, '.modu-migration-${state['id']}'));
    await _directory(staging);
    await _copyTree(documents, destination, staging, root: true);
    await _copyTree(databases, Directory(p.join(target, 'databases')),
        Directory(p.join(staging.path, 'databases')));
    // Only verified complete files have reached the destination. No DB handle
    // has been opened yet, so its WAL/SHM belong to this same quiescent snapshot.
    final completed = {...state, 'complete': true};
    await _writeState(receiptFile, completed);
    await _writeState(stateFile, completed);
    // Only our random, migration-owned scratch directory is removed.
    try {
      await staging.delete(recursive: true);
    } on FileSystemException {
      // A leftover empty scratch directory must not undo a successful migration.
    }
  }

  Future<void> _copyTree(Directory source, Directory target, Directory staging,
      {bool root = false}) async {
    if (!await source.exists()) return;
    await _directory(source);
    await _directory(target);
    await _directory(staging);
    await for (final entity in source.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (root && (name == stateName || name == '$stateName.next')) continue;
      final next = p.join(target.path, name);
      if (entity is Directory) {
        await _copyTree(
            entity, Directory(next), Directory(p.join(staging.path, name)));
      } else if (entity is File) {
        final output = File(next);
        final kind = await FileSystemEntity.type(next, followLinks: false);
        if (kind != FileSystemEntityType.notFound) {
          if (kind != FileSystemEntityType.file ||
              !await _equal(entity, output)) {
            throw const FileSystemException('目标目录存在不同内容的文件，已保留两端数据并停止迁移');
          }
          continue; // Verified file from a previous interrupted copy.
        }
        final temporary = File(p.join(staging.path, name));
        await _regularOrMissing(temporary);
        await entity.copy(temporary.path);
        // Flush copied data before publishing the file and commit receipts.
        final handle = await temporary.open(mode: FileMode.append);
        try {
          await handle.flush();
        } finally {
          await handle.close();
        }
        if (!await _equal(entity, temporary)) {
          throw const FileSystemException('迁移文件完整性校验失败，请重试');
        }
        if (await FileSystemEntity.type(next, followLinks: false) !=
            FileSystemEntityType.notFound) {
          throw const FileSystemException('迁移期间目标文件发生变化，请重试');
        }
        await temporary.rename(next);
      } else {
        throw const FileSystemException('数据目录含符号链接或特殊文件，已停止迁移');
      }
    }
  }

  static Future<bool> _equal(File a, File b) async =>
      await a.length() == await b.length() &&
      await sha256.bind(a.openRead()).first ==
          await sha256.bind(b.openRead()).first;

  static Future<void> _directory(Directory dir) async {
    // Do not follow symlinks inside an externally accessible destination.
    final kind = await FileSystemEntity.type(dir.path, followLinks: false);
    if (kind != FileSystemEntityType.notFound &&
        kind != FileSystemEntityType.directory) {
      throw const FileSystemException('应用数据目录不可用');
    }
    await dir.create(recursive: true);
  }

  static Future<void> _regularOrMissing(File file) async {
    final kind = await FileSystemEntity.type(file.path, followLinks: false);
    if (kind != FileSystemEntityType.notFound &&
        kind != FileSystemEntityType.file) {
      throw const FileSystemException('迁移文件不可用');
    }
  }

  static Future<Map<String, dynamic>> _readState(File file) async {
    await _regularOrMissing(file);
    if (await file.length() > 8192) throw const FormatException('迁移记录无效');
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['id'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['id']) ||
        value['target'] is! String ||
        value['complete'] is! bool ||
        value['database'] is! bool) {
      throw const FormatException('迁移记录无效');
    }
    return value;
  }

  static Future<void> _writeState(File file, Map<String, dynamic> value) async {
    await _regularOrMissing(file);
    final temporary = File('${file.path}.next');
    await _regularOrMissing(temporary);
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }
}
