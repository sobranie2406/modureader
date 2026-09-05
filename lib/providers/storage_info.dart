import 'dart:io';

import 'package:anx_reader/models/storege_info_model.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/providers/font_list.dart';
import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/get_path/get_cache_dir.dart';
import 'package:anx_reader/utils/get_path/log_file.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'storage_info.g.dart';

@riverpod
class StorageInfo extends _$StorageInfo {
  @override
  Future<StorageInfoModel> build() async {
    // An upgraded user can open Storage before ever opening AI history. Resolve
    // the legacy copy first so existing conversations are not reported as 0 B.
    await AiHistoryStore.migrateLegacyHistory();
    return StorageInfoModel(
      databaseSize: await calculatePathSize(await getAnxDataBasesDir()),
      booksSize: await calculatePathSize(getFileDir()),
      fontSize: await calculatePathSize(getFontDir()),
      cacheSize: await calculatePathSize(
        await getAnxCacheDir(),
        recursive: true,
      ),
      logSize: await calsulateFileSize(await getLogFile()),
      coverSize: await calculatePathSize(getCoverDir()),
      modelSize: await calculatePathSize(Directory(getBasePath('models'))),
      indexSize: await calculatePathSize(Directory(getBasePath('knowledge'))),
      aiHistorySize: await calculatePathSize(Directory(getBasePath('ai'))),
      backgroundSize: await calculatePathSize(getBgimgDir()),
    );
  }

  Future<bool> clearCache() async {
    try {
      // Abort cleanup if migration fails; conversations are not disposable cache.
      await AiHistoryStore.migrateLegacyHistory();
      final cacheDir = await getAnxCacheDir();
      if (!cacheDir.existsSync()) {
        return true;
      }

      final entities = await cacheDir.list(followLinks: false).toList();
      for (var entity in entities) {
        if (entity.existsSync()) {
          if (entity is File) {
            entity.deleteSync();
          } else if (entity is Directory) {
            entity.deleteSync(recursive: true);
          }
        }
      }

      state = AsyncData(await build());

      return true;
    } catch (e) {
      AnxLog.severe('StorageInfo clearCache error: $e');
      return false;
    }
  }

  Future<int> calculatePathSize(Directory dir, {bool recursive = true}) async {
    if (!dir.existsSync()) {
      return 0;
    }

    int totalSize = 0;
    final entities =
        await dir.list(recursive: recursive, followLinks: false).toList();
    for (var entity in entities) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }

    return totalSize;
  }

  Future<int> calsulateFileSize(File file) async {
    return await file.exists() ? await file.length() : 0;
  }

  Future<List<File>> listBookFiles() async {
    final fileDir = getFileDir();
    if (!fileDir.existsSync()) {
      return [];
    }

    final files = <File>[];
    final entities = await fileDir.list(recursive: true).toList();
    for (var entity in entities) {
      if (entity is File) {
        files.add(entity);
      }
    }

    return files;
  }

  Future<List<File>> listFontFiles() async {
    final fontDir = getFontDir();
    if (!fontDir.existsSync()) {
      return [];
    }

    final files = <File>[];
    final entities = await fontDir.list(recursive: true).toList();
    for (var entity in entities) {
      if (entity is File) {
        files.add(entity);
      }
    }

    return files;
  }

  Future<List<File>> listCoverFiles() async {
    final coverDir = getCoverDir();
    if (!coverDir.existsSync()) {
      return [];
    }

    final files = <File>[];
    final entities = await coverDir.list(recursive: true).toList();
    for (var entity in entities) {
      if (entity is File) {
        files.add(entity);
      }
    }

    return files;
  }

  Future<void> deleteFile(File file) async {
    await file.delete();
    state = AsyncData(await build());
    ref.watch(fontListProvider.notifier).refresh();
  }
}
