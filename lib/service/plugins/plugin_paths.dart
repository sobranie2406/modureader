import 'dart:io';

import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:path/path.dart' as p;

/// Filesystem layout for installed plugin packages.
///
/// The default root is `<basePath>/plugins`, created by `initBasePath()`.
/// Tests pass an explicit [rootPath] so the host never touches real app data.
class PluginPaths {
  PluginPaths({String? rootPath})
      : root = Directory(rootPath ?? p.join(documentPath, 'plugins'));

  final Directory root;

  Directory get staging => Directory(p.join(root.path, '.staging'));

  Directory get trash => Directory(p.join(root.path, '.trash'));

  Directory pluginDir(String id) => Directory(p.join(root.path, id));

  File manifestFile(String id) =>
      File(p.join(pluginDir(id).path, 'manifest.json'));

  Future<void> ensureCreated() async {
    await root.create(recursive: true);
    await staging.create(recursive: true);
    await trash.create(recursive: true);
  }

  /// Removes leftover staging/trash directories from a previous crash.
  ///
  /// Failures are ignored: a locked temporary directory must not block startup.
  Future<void> cleanStale() async {
    for (final directory in [staging, trash]) {
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(followLinks: false)) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // Leave it for the next start; it is outside every plugin directory.
        }
      }
    }
  }

  Future<void> deletePlugin(String id) async {
    final directory = pluginDir(id);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
