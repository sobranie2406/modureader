import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'android_storage_migration.dart';

/// Android's app-specific external files directory, not a public user folder.
Future<Directory> androidDataDirectory() async {
  final directory = await getExternalStorageDirectory();
  if (directory == null) {
    throw const FileSystemException('Android/data 存储暂不可用，请检查存储后重试');
  }
  return directory;
}

Future<void> prepareAndroidStorage() async {
  final documents = (await getApplicationDocumentsDirectory()).path;
  final databases = await getDatabasesPath();
  final destination = (await androidDataDirectory()).path;
  // Large fonts/models/indexes are copied and hashed away from the UI isolate.
  await Isolate.run(() => AndroidStorageMigration(
        documents: Directory(documents),
        databases: Directory(databases),
        destination: Directory(destination),
      ).run());
}
