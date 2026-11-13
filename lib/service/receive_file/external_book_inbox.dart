import 'dart:io';

import 'package:modu_reader/service/book_import_source.dart';
import 'package:path/path.dart' as p;

/// Accept local documents only; reading links and network URLs are not imports.
String? externalBookPath(String raw) {
  String value = raw;
  try {
    if (raw.startsWith('file:')) {
      final uri = Uri.parse(raw);
      if (uri.host.isNotEmpty && uri.host != 'localhost') return null;
      value = uri.toFilePath(windows: Platform.isWindows);
    }
    if (!p.isAbsolute(value) || !isSupportedBookFile(value)) return null;
    return p.normalize(value);
  } on FormatException {
    return null;
  } on UnsupportedError {
    return null;
  }
}

/// Never recurse into a directory merely because it has a book extension.
Future<List<BookImportEntry>> externalBookEntries(List<String> paths) async {
  final entries = <String, BookImportEntry>{};
  for (final raw in paths) {
    final path = externalBookPath(raw);
    if (path == null) continue;
    if (await FileSystemEntity.type(path) != FileSystemEntityType.file) {
      throw FileSystemException('Book source is not a regular file', path);
    }
    final id = await File(path).resolveSymbolicLinks();
    entries.putIfAbsent(
        id,
        () => BookImportEntry(
            id: id, name: p.basename(path), label: p.basename(path)));
  }
  return entries.values.toList();
}

/// Retain cold-start requests and serialize imports, including initial/stream
/// duplicates. Unlike reading links, opening several documents must keep all.
class ExternalBookInbox {
  Future<void> Function(List<String>)? _handler;
  final _pending = <List<String>>[];
  final _queued = <String>{};
  bool _running = false;

  void add(Iterable<String> paths) {
    final batch = <String>[];
    for (final raw in paths) {
      final path = externalBookPath(raw);
      if (path != null && _queued.add(path)) batch.add(path);
    }
    if (batch.isEmpty) return;
    _pending.add(batch);
    _drain();
  }

  void attach(Future<void> Function(List<String>) handler) {
    _handler = handler;
    _drain();
  }

  void detach() => _handler = null;

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (_handler != null && _pending.isNotEmpty) {
        final batch = _pending.removeAt(0);
        try {
          await _handler!(batch);
        } catch (_) {
          // The UI handler reports failures; one bad file must not stall the queue.
        } finally {
          _queued.removeAll(batch);
        }
      }
    } finally {
      _running = false;
    }
  }
}

final externalBookInbox = ExternalBookInbox();
