import 'dart:io';

import 'package:flutter/services.dart';

/// Device-local security-scoped bookmarks are never stored in the synced DB.
class IosLinkedBooks {
  static const channel = MethodChannel('com.modu.reader/book_folder');
  static const extensions = ['epub', 'pdf', 'mobi', 'azw3', 'fb2'];
  static final Map<String, String> _paths = {};

  static bool isLinked(String path) =>
      path.startsWith('file/ios-linked-') || path.startsWith('file/linked-');
  static String? resolve(String path) => _paths[path];

  static void registerPath(String key, String path) {
    if (!isLinked(key) || !File(path).isAbsolute) {
      throw const FileSystemException('Invalid original path');
    }
    _paths[key] = path;
  }

  static Future<void> restore() async {
    final paths = await channel.invokeMapMethod<String, String>('restoreLinks');
    _paths
      ..clear()
      ..addAll(paths ?? {});
  }

  static Future<String> link(String selectionId) async {
    final link = await channel
        .invokeMapMethod<String, String>('link', {'id': selectionId});
    final key = link?['key'];
    final path = link?['path'];
    if (key == null ||
        !isLinked(key) ||
        path == null ||
        !File(path).isAbsolute) {
      throw const FileSystemException('Unable to retain book access');
    }
    _paths[key] = path;
    return key;
  }

  static Future<void> forget(String key) async {
    if (!isLinked(key)) return;
    // Release native access when a host is available.
    try {
      await channel.invokeMethod<void>('forgetLink', {'key': key});
    } on MissingPluginException {
      // No native link host on this platform (Windows/Linux).
    }
    _paths.remove(key);
  }
}
