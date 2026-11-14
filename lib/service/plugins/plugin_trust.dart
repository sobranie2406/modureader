import 'dart:io';
import 'package:modu_reader/service/plugins/plugin_catalog_signature.dart';
import 'package:pub_semver/pub_semver.dart';

import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Only compiled approvals or project-signed review proofs may grant trust.
class PluginTrust {
  PluginTrust(
      {Directory? catalogDirectory, PluginCatalogSignature? signatureVerifier})
      : _catalogDirectory = catalogDirectory,
        _signature = signatureVerifier ?? PluginCatalogSignature();
  Directory? _catalogDirectory;
  final PluginCatalogSignature _signature;
  final _reviewed = <String, Map<String, String>>{};
  void bindCatalogDirectory(Directory directory) =>
      _catalogDirectory ??= directory;

  static const projectSource = 'https://github.com/sobranie2406/modu-plugin';

  static const approved = <String, Map<String, String>>{
    'com.modu.private-books@1.0.0': {
      'LICENSE':
          '776fdcb645b929da3ec5184f16f9ef1d50ac2094394a1958cb7fd4d1d9a609a1',
      'README.md':
          'dd7fa6692302a09ce1985109253bc4b5de6b3e4ba1a33e83d12f0db87b6a70b0',
      'main.js':
          'bc2994699ee7a5efcf98ef0f9b5bf93470389225e91b39538b452576c4a07229',
      'manifest.json':
          '7bf4cfe4089cc31146d0004807f9ebdb1df6440ba0f81c394ee3cf9fd66cc650',
    },
    'com.modu.text-tools@1.0.0': {
      'LICENSE':
          '776fdcb645b929da3ec5184f16f9ef1d50ac2094394a1958cb7fd4d1d9a609a1',
      'README.md':
          'edd90e37d85843ace496f33a4b013fe1539b1127fb5b3c0e02872a6cb420df46',
      'main.js':
          'f8791bb3a554af7e767f430771eadd15f5540afe0b9c1505edf357fb3e5a283a',
      'manifest.json':
          '33d36075899c350a7f4352867bd3ec3b51b448804d7b1104f6df353bdf64dc71',
    },
    'com.example.prompt-pack@1.1.0': {
      'manifest.json':
          '405941bfa8f15fef6a5fa7b6d6628da357733f84faa919c6676699bdcc730fbe',
      'README.md':
          'dc7a53ee926b20a087fb1240db0051af274a7aa46650223e1ef2db54335fb729',
      'LICENSE':
          '1b8f0b15266cbeba35ed28401ffbf7e9e4438e302e1431462342b8d0ed3d6a63',
    },
  };

  static bool _safeRelease(String id, String version) {
    if (!pluginIdPattern.hasMatch(id)) return false;
    try {
      Version.parse(version);
      return !version.contains('/') && !version.contains('\\');
    } catch (_) {
      return false;
    }
  }

  static bool _same(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length &&
      a.entries.every((entry) => b[entry.key] == entry.value);

  static Map<String, Map<String, String>> _reviews(
      Map<String, dynamic> catalog) {
    if (catalog['schemaVersion'] != 1 ||
        catalog['repository'] != projectSource ||
        catalog['plugins'] is! List ||
        (catalog['plugins'] as List).length > 100) {
      throw _untrusted;
    }
    final releases = <String, Map<String, String>>{};
    for (final entry in catalog['plugins'] as List) {
      if (entry is! Map) throw _untrusted;
      if (entry['status'] != 'reviewed') continue;
      final id = entry['id'],
          version = entry['version'],
          files = entry['files'],
          review = entry['review'];
      if (id is! String ||
          version is! String ||
          !_safeRelease(id, version) ||
          files is! Map ||
          files.isEmpty ||
          files.length > PluginLimits.maxEntries ||
          review is! Map ||
          review['reviewer'] is! String ||
          (review['reviewer'] as String).isEmpty ||
          review['kind'] is! String ||
          review['reviewedAt'] is! String ||
          DateTime.tryParse(review['reviewedAt']) == null) {
        throw _untrusted;
      }
      final expected = <String, String>{};
      for (final file in files.entries) {
        final name = file.key, hash = file.value;
        if (name is! String ||
            name.isEmpty ||
            name.length > 256 ||
            name.startsWith('/') ||
            name.contains('\\') ||
            name.contains(':') ||
            name
                .split('/')
                .any((part) => part.isEmpty || part == '.' || part == '..') ||
            hash is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
          throw _untrusted;
        }
        expected[name] = hash;
      }
      final key = '$id@$version';
      if (!expected.containsKey('manifest.json') || releases.containsKey(key)) {
        throw _untrusted;
      }
      final builtin = approved[key];
      if (builtin != null && !_same(builtin, expected)) throw _untrusted;
      releases[key] = Map.unmodifiable(expected);
    }
    return releases;
  }

  /// Retain signed proofs per release for offline use and later catalog updates.
  Future<void> acceptCatalog(String envelope) async {
    final releases = _reviews(await _signature.decode(envelope));
    final directory = _catalogDirectory;
    if (directory == null) throw _untrusted;
    await directory.create(recursive: true);
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw _untrusted;
    }
    for (final entry in releases.entries) {
      final split = entry.key.indexOf('@');
      final old = await reviewedFiles(
          entry.key.substring(0, split), entry.key.substring(split + 1));
      if (old != null && !_same(old, entry.value)) throw _untrusted;
    }
    for (final entry in releases.entries) {
      if (approved.containsKey(entry.key)) continue;
      final file = File(p.join(directory.path, '${entry.key}.json'));
      if (!_reviewed.containsKey(entry.key)) {
        final staged = File('${file.path}.pending');
        await staged.writeAsString(envelope, flush: true);
        if (await file.exists()) await file.delete();
        await staged.rename(file.path);
      }
      _reviewed[entry.key] = entry.value;
    }
  }

  Future<Map<String, String>?> reviewedFiles(String id, String version) async {
    if (!_safeRelease(id, version)) return null;
    final key = '$id@$version';
    if (approved.containsKey(key)) return approved[key];
    if (_reviewed.containsKey(key)) return _reviewed[key];
    final directory = _catalogDirectory;
    if (directory == null) return null;
    final file = File(p.join(directory.path, '$key.json'));
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() > PluginCatalogSignature.maxEnvelopeBytes) {
        return null;
      }
      final reviews =
          _reviews(await _signature.decode(await file.readAsString()));
      final expected = reviews[key];
      if (expected != null) _reviewed[key] = expected;
      return expected;
    } catch (_) {
      return null;
    }
  }

  Future<void> verify(Directory directory, String id, String version) async {
    final expected = await reviewedFiles(id, version);
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
