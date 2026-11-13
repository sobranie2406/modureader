// Packs a plugin directory into a deterministic `.moduplugin` zip.
//
// Usage:
//   dart run scripts/dev/pack_plugin.dart docs/examples/plugins/prompt-pack
//   dart run scripts/dev/pack_plugin.dart <dir> [output-dir]
//
// Entries are sorted, timestamps are fixed, and the archive is stored with the
// same layout the installer expects (manifest.json at the root).
import 'dart:io';
import 'dart:typed_data';

import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
        'Usage: dart run scripts/dev/pack_plugin.dart <plugin-dir> [output-dir]');
    exitCode = 64;
    return;
  }

  final source = Directory(args[0]);
  if (!await source.exists()) {
    stderr.writeln('Plugin directory not found: ${source.path}');
    exitCode = 66;
    return;
  }

  final manifestFile = File(p.join(source.path, 'manifest.json'));
  if (!await manifestFile.exists()) {
    stderr.writeln('manifest.json is required at the plugin root.');
    exitCode = 65;
    return;
  }

  final manifest = PluginManifest.parse(await manifestFile.readAsString());
  final outputDir = Directory(args.length == 2 ? args[1] : source.parent.path);
  await outputDir.create(recursive: true);

  final files = await source
      .list(recursive: true, followLinks: false)
      .where((entity) =>
          entity is File && p.basename(entity.path) != 'manifest.json.orig')
      .cast<File>()
      .toList();
  files.sort((a, b) => a.path.compareTo(b.path));

  final archive = Archive();
  final modified = DateTime.utc(1980, 1, 1);
  for (final file in files) {
    final relative =
        p.relative(file.path, from: source.path).replaceAll('\\', '/');
    if (relative.startsWith('..')) {
      stderr.writeln(
          'Refusing to pack a file outside the plugin directory: $relative');
      exitCode = 65;
      return;
    }
    final bytes = await file.readAsBytes();
    final entry = ArchiveFile(relative, bytes.length, Uint8List.fromList(bytes))
      ..lastModTime = modified.millisecondsSinceEpoch ~/ 1000;
    archive.addFile(entry);
  }

  final encoded = ZipEncoder().encode(archive, modified: modified);
  if (encoded == null) {
    stderr.writeln('Failed to encode the package.');
    exitCode = 70;
    return;
  }

  final name = '${p.basename(source.path)}-${manifest.version}.moduplugin';
  final target = File(p.join(outputDir.path, name));
  await target.writeAsBytes(encoded, flush: true);
  stdout.writeln(target.path);
}
