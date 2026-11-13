import 'dart:io';

import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Reviewed project releases only. Never populated from packages, preferences,
/// backups or network responses. Adding a release requires a reviewed app update.
class PluginTrust {
  const PluginTrust();

  static const projectSource = 'https://github.com/sobranie2406/modureader';

  static const approved = <String, Map<String, String>>{
    'com.example.prompt-pack@1.1.0': {
      'manifest.json':
          '405941bfa8f15fef6a5fa7b6d6628da357733f84faa919c6676699bdcc730fbe',
      'README.md':
          'dc7a53ee926b20a087fb1240db0051af274a7aa46650223e1ef2db54335fb729',
      'LICENSE':
          '1b8f0b15266cbeba35ed28401ffbf7e9e4438e302e1431462342b8d0ed3d6a63',
    },
  };

  Future<void> verify(Directory directory, String id, String version) async {
    final expected = approved['$id@$version'];
    if (expected == null ||
        await FileSystemEntity.type(directory.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      throw _untrusted;
    }
    final seen = <String>{};
    var count = 0;
    await for (final entity
        in directory.list(recursive: true, followLinks: false)) {
      if (++count > PluginLimits.maxEntries || entity is Link) throw _untrusted;
      final name =
          p.relative(entity.path, from: directory.path).replaceAll('\\', '/');
      if (entity is Directory) {
        if (!expected.keys.any((key) => key.startsWith('$name/'))) {
          throw _untrusted;
        }
        continue;
      }
      if (entity is! File || !expected.containsKey(name)) throw _untrusted;
      if (await entity.length() > PluginLimits.maxFileBytes) throw _untrusted;
      final digest = await sha256.bind(entity.openRead()).first;
      if (digest.toString() != expected[name]) throw _untrusted;
      seen.add(name);
    }
    if (seen.length != expected.length) throw _untrusted;
  }

  static const _untrusted = PluginInstallError(
    PluginErrorCode.untrustedPackage,
    'This plugin is not in the project-reviewed catalog, or its files have changed. '
    'Install an approved release from the Modu project. Third-party packages cannot be enabled.',
  );
}
