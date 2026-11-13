import 'package:modu_reader/service/read_only_book_file.dart';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;

/// Capabilities for files explicitly opened by the application. Never accept a
/// filesystem path from an HTTP request, even on the loopback interface.
class ReaderFileAccess {
  final _files = <String, (String, String)>{};
  final _random = Random.secure();

  String register(File file, {bool reuse = true}) {
    file = readOnlyBookFile(file.path);
    final canonical = file.resolveSymbolicLinksSync();
    for (final entry in _files.entries) {
      if (reuse && entry.value == (file.absolute.path, canonical)) {
        return entry.key;
      }
    }
    final token = List.generate(
            32, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    final name = '$token${p.extension(file.path).toLowerCase()}';
    _files[name] = (file.absolute.path, canonical);
    return name;
  }

  File? resolve(String token) {
    final registered = _files[token];
    if (registered == null) return null;
    final (accessPath, canonical) = registered;
    try {
      final file = readOnlyBookFile(accessPath);
      return file.resolveSymbolicLinksSync() == canonical && file.existsSync()
          ? file
          : null;
    } on FileSystemException {
      return null;
    }
  }

  void revoke(String token) => _files.remove(token);

  static File? within(Directory directory, String relative) {
    if (p.isAbsolute(relative)) return null;
    try {
      final root = directory.resolveSymbolicLinksSync();
      final candidate = File(p.join(root, relative));
      final target = candidate.resolveSymbolicLinksSync();
      return p.isWithin(root, target) && candidate.existsSync()
          ? candidate
          : null;
    } on FileSystemException {
      return null;
    }
  }
}
