import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_package.dart';
import 'package:modu_reader/service/plugins/plugin_trust.dart';
import 'package:path/path.dart' as p;

/// A user-confirmed, in-memory file seal; never an official review proof.
class PluginDevelopmentTrust extends PluginTrust {
  final _accepted = <String, Map<String, String>>{};

  @override
  void bindCatalogDirectory(Directory directory) {}

  @override
  Future<void> acceptCatalog(String envelope) async =>
      throw const PluginInstallError(PluginErrorCode.untrustedPackage,
          'Development sessions cannot accept official review proofs.');

  @override
  Future<Map<String, String>?> reviewedFiles(String id, String version) async =>
      _accepted['$id@$version'];

  Map<String, String>? sealFor(String id, String version) =>
      _accepted['$id@$version'];
  void restore(String id, String version, Map<String, String>? previous) {
    final key = '$id@$version';
    if (previous == null) {
      _accepted.remove(key);
    } else {
      _accepted[key] = previous;
    }
  }

  Future<void> acceptPackage(PluginPackage package) async {
    final files = <String, String>{};
    await for (final entity
        in package.staging.list(recursive: true, followLinks: false)) {
      if (entity is Link) {
        throw const PluginInstallError(PluginErrorCode.invalidPackage,
            'Development package contains a symbolic link.');
      }
      if (entity is! File) continue;
      if (await entity.length() > PluginLimits.maxFileBytes ||
          files.length >= PluginLimits.maxEntries) {
        throw const PluginInstallError(PluginErrorCode.packageTooLarge,
            'Development package exceeds its file limits.');
      }
      final name = p
          .relative(entity.path, from: package.staging.path)
          .replaceAll('\\', '/');
      files[name] = (await sha256.bind(entity.openRead()).first).toString();
    }
    _accepted['${package.manifest.id}@${package.manifest.version}'] =
        Map.unmodifiable(files);
    await verify(
        package.staging, package.manifest.id, package.manifest.version);
  }

  void forget(String id) =>
      _accepted.removeWhere((key, _) => key.startsWith('$id@'));
  void clear() => _accepted.clear();
}
