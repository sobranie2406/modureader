import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:anx_reader/service/ios_linked_books.dart';

/// Device-only locators. Kept outside the backup/sync directory allowlist.
/// The synchronized book path remains a remote asset key, never a local locator.
class BookLocalSources {
  BookLocalSources(this.file);
  final File file;
  Map<String, Map<String, String>> _entries = {};
  Future<void> _writes = Future.value();

  static String identity(String? md5, String legacyPath) =>
      RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(md5 ?? '')
          ? 'md5:${md5!.toLowerCase()}'
          : 'path:$legacyPath';

  Set<String> get ownedPaths => {
        for (final entry in _entries.values)
          if (entry['kind'] == 'internal') entry['locator']!,
      };

  Future<void> load() async {
    if (!await file.exists()) return;
    final data = jsonDecode(await file.readAsString());
    if (data is! Map || data['version'] != 1 || data['entries'] is! Map) {
      throw const FormatException('Invalid local book sources');
    }
    final entries = <String, Map<String, String>>{};
    for (final item in (data['entries'] as Map).entries) {
      final value = Map<String, String>.from(item.value as Map);
      _validate(value);
      entries[item.key as String] = value;
    }
    _entries = entries;
  }

  Map<String, String>? read(String? md5, String legacyPath) {
    final entry = _entries[identity(md5, legacyPath)];
    return entry == null ? null : Map.unmodifiable(entry);
  }

  static void _validate(Map<String, String> entry) {
    final kind = entry['kind'];
    final locator = entry['locator'];
    if (!const ['internal', 'linked'].contains(kind) ||
        locator == null ||
        locator.isEmpty ||
        locator.contains('\u0000')) {
      throw const FormatException('Invalid book source');
    }
    if (kind == 'internal' &&
        (!locator.startsWith('file/') ||
            locator.split('/').length != 2 ||
            locator.contains('\\') ||
            const ['.', '..'].contains(p.posix.basename(locator)))) {
      throw const FormatException('Invalid internal book path');
    }
  }

  Future<void> save(String? md5, String legacyPath,
      {required String kind, required String locator}) {
    final entry = {'kind': kind, 'locator': locator};
    _validate(entry);
    return _change(identity(md5, legacyPath), entry);
  }

  Future<void> remove(String? md5, String legacyPath) =>
      _change(identity(md5, legacyPath), null);

  Future<void> _change(String key, Map<String, String>? entry) {
    final next = _writes.then((_) async {
      final updated = Map<String, Map<String, String>>.from(_entries);
      if (entry == null) {
        updated.remove(key);
      } else {
        updated[key] = entry;
      }
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
          jsonEncode({'version': 1, 'entries': updated}),
          flush: true);
      await temporary.rename(file.path);
      _entries = updated;
    });
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }
}

// Integration uses explicit initialization after the library directory is known;
// this also prevents locators from one library leaking into another library.
class BookSources {
  static BookLocalSources? _store;
  static Object? _loadError;
  static BookLocalSources? get store => _store;

  static String? resolve(String? md5, String remotePath, String library) {
    final source = _store?.read(md5, remotePath);
    if (source == null) return IosLinkedBooks.resolve(remotePath);
    final locator = source['locator']!;
    if (source['kind'] == 'internal') return p.join(library, locator);
    if (IosLinkedBooks.isLinked(locator)) {
      return IosLinkedBooks.resolve(locator);
    }
    return p.isAbsolute(locator) ? locator : null;
  }

  static bool isLinked(String? md5, String remotePath) {
    final source = _store?.read(md5, remotePath);
    return source == null
        ? IosLinkedBooks.isLinked(remotePath)
        : source['kind'] == 'linked';
  }

  /// Preserve the local source before the synced asset key changes. Does not
  /// change the incoming payload, clocks, or replacement/identity protocol.
  static Future<void> retain(Map<String, Object?> row, String library) async {
    if (_loadError != null) {
      throw StateError(
          'Local book sources unavailable; synchronization deferred');
    }
    final store = _store;
    if (store == null) return;
    final md5 = row['file_md5'] as String?;
    final path = row['file_path'] as String? ?? '';
    if (store.read(md5, path) != null) return;
    if (IosLinkedBooks.isLinked(path)) {
      await store.save(md5, path, kind: 'linked', locator: path);
    } else if (path.startsWith('file/') &&
        await File(p.join(library, path)).exists()) {
      await store.save(md5, path, kind: 'internal', locator: path);
    }
  }

  static Future<void> forget(String? md5, String remotePath) async {
    final entry = _store?.read(md5, remotePath);
    final locator = entry?['locator'] ?? remotePath;
    if (IosLinkedBooks.isLinked(locator)) await IosLinkedBooks.forget(locator);
    await _store?.remove(md5, remotePath);
  }

  static Future<void> initialize(Directory library) async {
    _store = null;
    final next =
        BookLocalSources(File(p.join(library.path, 'book_sources.json')));
    await next.load();
    _store = next;
  }
}
