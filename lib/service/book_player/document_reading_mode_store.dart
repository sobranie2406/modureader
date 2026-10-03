import 'dart:convert';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/models/document_reading_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Import-time evidence. Opening only reads this local cache; no file I/O,
/// sampling, hashing, or silent migration is allowed on the reader hot path.
class DocumentReadingModeStore {
  DocumentReadingModeStore(this.prefs);
  final SharedPreferences prefs;
  static const key = 'documentReadingModes';
  static Future<void> _writes = Future.value();

  String _source(Book book) => book.md5?.isNotEmpty == true
      ? 'md5:${book.md5}'
      : 'path:${book.filePath}';

  Map<String, dynamic> _read() {
    try {
      final value = jsonDecode(prefs.getString(key) ?? '{}');
      return value is Map ? Map<String, dynamic>.from(value) : {};
    } catch (_) {
      return {};
    }
  }

  DocumentReadingMode read(Book book) {
    // PDF is a known container type, including old library entries. No page
    // inspection is necessary. Old EPUBs without evidence keep Preview 3.
    if (book.filePath.toLowerCase().endsWith('.pdf'))
      return DocumentReadingMode.pdf;
    final entry = _read()[customCssBookKey(book)];
    if (entry is! Map ||
        entry['version'] != 1 ||
        entry['source'] != _source(book)) {
      return DocumentReadingMode.standard;
    }
    return DocumentReadingMode.fromDetection(book.filePath, entry['mode']);
  }

  Future<void> save(Book book, Object? detection) {
    final mode = DocumentReadingMode.fromDetection(book.filePath, detection);
    final identity = customCssBookKey(book), source = _source(book);
    final operation = _writes.then((_) async {
      final previous = prefs.getString(key);
      final entries = _read();
      entries[identity] = {
        'version': 1,
        'source': source,
        'mode': mode.storageValue
      };
      try {
        if (!await prefs.setString(key, jsonEncode(entries))) {
          throw StateError('Document classification save failed');
        }
      } catch (_) {
        try {
          if (previous == null) {
            await prefs.remove(key);
          } else {
            await prefs.setString(key, previous);
          }
        } catch (_) {}
        rethrow;
      }
    });
    _writes = operation.catchError((_) {});
    return operation;
  }
}
