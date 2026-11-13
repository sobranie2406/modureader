import 'dart:io';

import 'package:modu_reader/service/book_formats.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class BookImportEntry {
  const BookImportEntry(
      {required this.id, required this.name, required this.label});
  final String id;
  final String name;
  final String label;
}

bool isSupportedBookFile(String name) => allowBookExtensions
    .contains(p.extension(name).replaceFirst('.', '').toLowerCase());

String importedBookTitle(String filePath, String metadataTitle) {
  // PDF producer metadata often contains garbled text or working names like P3.
  if (p.extension(filePath).toLowerCase() == '.pdf' ||
      metadataTitle == 'Unknown' ||
      metadataTitle.trim().isEmpty) {
    return p.basenameWithoutExtension(filePath);
  }
  return metadataTitle;
}

/// Enumerate without following links, reading book contents, or changing sources.
/// Resolve duplicates so overlapping dropped folders do not import twice.
Future<List<BookImportEntry>> discoverBookImportFiles(
    List<String> paths) async {
  final entries = <String, BookImportEntry>{};
  Future<void> addFile(String path, String label) async {
    if (!isSupportedBookFile(path)) return;
    final id = await File(path).resolveSymbolicLinks();
    entries.putIfAbsent(
        id,
        () => BookImportEntry(
              id: id,
              name: p.basename(path),
              label: label,
            ));
  }

  Future<void> visit(Directory folder, String prefix) async {
    await for (final child in folder.list(followLinks: false)) {
      final name = p.basename(child.path);
      if (name.startsWith('.')) continue;
      final label = p.join(prefix, name);
      if (child is Directory) {
        await visit(child, label);
      } else if (child is File) {
        await addFile(child.path, label);
      }
    }
  }

  for (final path in paths) {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await visit(Directory(path), p.basename(path));
    } else if (type == FileSystemEntityType.file) {
      await addFile(path, p.basename(path));
    }
  }
  return entries.values.toList()
    ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
}

/// The existing importer deletes its inputs. Always supply isolated copies,
/// including for Android and for identically named books in different folders.
Future<List<File>> stageBookImportFiles(
    List<BookImportEntry> entries, Directory temp) async {
  final session = await temp.createTemp('book-import-');
  try {
    final files = <File>[];
    for (var i = 0; i < entries.length; i++) {
      final item = entries[i];
      final folder = await Directory(p.join(session.path, '$i')).create();
      files.add(
          await File(item.id).copy(p.join(folder.path, p.basename(item.name))));
    }
    return files;
  } catch (_) {
    await session.delete(recursive: true);
    rethrow;
  }
}

/// Drag-and-drop imports need no confirmation/result UI. Stage one book at a
/// time so one unreadable or invalid book does not abort the remaining files.
Future<int> importBookEntriesQuietly(
  List<BookImportEntry> entries,
  Directory temp, {
  required Future<bool> Function(File) isDuplicate,
  required Future<void> Function(File) importFile,
  required void Function(BookImportEntry, Object, StackTrace) onError,
}) async {
  var imported = 0;
  for (final entry in entries) {
    if (!isSupportedBookFile(entry.name)) continue;
    Directory? session;
    try {
      final files = await stageBookImportFiles([entry], temp);
      final file = files.single;
      session = file.parent.parent;
      if (await isDuplicate(file)) continue;
      await importFile(file);
      imported++;
    } catch (error, stack) {
      onError(entry, error, stack);
    } finally {
      if (session != null) {
        try {
          if (await session.exists()) await session.delete(recursive: true);
        } catch (error, stack) {
          onError(entry, error, stack);
        }
      }
    }
  }
  return imported;
}

/// Mobile document providers require scoped URI access, not filesystem paths.
class MobileBookFolder {
  static const channel = MethodChannel('com.modu.reader/book_folder');

  static Future<List<BookImportEntry>?> pick(
      {bool files = false,
      bool inPlace = false,
      List<String> extensions = allowBookExtensions}) async {
    final result = await channel.invokeListMethod<dynamic>('pick', {
      'extensions': extensions,
      'files': files,
      'inPlace': inPlace,
    });
    return result
        ?.map((dynamic item) => BookImportEntry(
              id: item['id'] as String,
              name: item['name'] as String,
              label: item['label'] as String,
            ))
        .toList();
  }

  static Future<List<File>> stage(List<BookImportEntry> entries) async {
    final paths = await channel.invokeListMethod<String>(
        'copy', {'ids': entries.map((e) => e.id).toList()});
    if (paths == null || paths.length != entries.length) {
      throw const FileSystemException('Incomplete folder import');
    }
    return paths.map(File.new).toList();
  }

  static Future<void> release() => channel.invokeMethod<void>('release');
}
