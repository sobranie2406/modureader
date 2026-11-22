import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:path/path.dart' as p;

/// A packaged .moduplugin must match the directory it was built from.
///
/// The dist folder is gitignored build output, so it is easy to edit an
/// example, commit the source, and leave a stale package behind. That is
/// exactly what happened: the shipped note-cards kept an older manifest
/// without search:library, so the installed plugin reported permission
/// (the package never declared it) while the source looked correct.
void main() {
  final root = Directory('docs/examples/plugins');
  final dist = Directory(p.join(root.path, 'dist'));

  test('every packaged example matches its source', () {
    if (!dist.existsSync()) return;
    final offenders = <String>[];
    for (final directory in root.listSync().whereType<Directory>().where(
        (dir) => File(p.join(dir.path, 'manifest.json')).existsSync())) {
      final name = p.basename(directory.path);
      final manifest = PluginManifest.parse(
          File(p.join(directory.path, 'manifest.json')).readAsStringSync());
      // Only scripted examples are shipped as packages; the declarative
      // prompt-pack sample is installed from source and has no scripts whose
      // bytes could drift.
      if (manifest.contributions.whereType<ScriptActionContribution>().isEmpty) {
        continue;
      }
      final packages = dist
          .listSync()
          .whereType<File>()
          .where((file) =>
              p.basename(file.path) ==
              '$name-${manifest.version}.moduplugin')
          .toList();
      if (packages.isEmpty) {
        offenders.add('$name has no packaged release');
        continue;
      }
      final archive =
          ZipDecoder().decodeBytes(packages.single.readAsBytesSync());
      // Compare raw bytes: the packer stores files verbatim, and decoding them
      // as characters would corrupt every non-ASCII byte in a Chinese script.
      final files = <String, List<int>>{
        for (final entry in archive.files)
          if (entry.isFile) entry.name: entry.content,
      };

      final packaged = PluginManifest.parse(
          utf8.decode(files['manifest.json']!));
      if (!_sameSet(packaged.capabilities, manifest.capabilities)) {
        final expected = manifest.capabilities.toList()..sort();
        final actual = packaged.capabilities.toList()..sort();
        offenders.add('$name capabilities differ: package=$actual '
            'source=$expected');
      }

      for (final action in manifest.contributions) {
        if (action is! ScriptActionContribution) continue;
        final source = File(p.join(directory.path, action.entry));
        if (!source.existsSync()) continue;
        final packed = files[action.entry];
        final actual = source.readAsBytesSync();
        if (packed == null ||
            packed.length != actual.length ||
            !_sameBytes(packed, actual)) {
          offenders.add('$name/${action.entry} is stale');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'rebuild with scripts/dev/pack_plugin.dart; these differ: '
            '${offenders.join('; ')}');
  });
}

bool _sameBytes(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
