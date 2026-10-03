import 'dart:convert';
import 'package:anx_reader/models/document_page_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-document local layouts, never a transferable global preference.
class DocumentLayoutStore {
  DocumentLayoutStore(this.prefs);
  final SharedPreferences prefs;
  static const key = 'documentPageLayouts';
  static Future<void> _writes = Future.value();

  DocumentLayoutConfig read(String documentKey) {
    try {
      final data = jsonDecode(prefs.getString(key) ?? '{}');
      return DocumentLayoutConfig.fromJson(data[documentKey]);
    } catch (_) {
      return const DocumentLayoutConfig();
    }
  }

  Future<void> save(String documentKey, DocumentLayoutConfig config) {
    if (documentKey.isEmpty) throw ArgumentError('Empty document identity');
    final encoded = config.toJson();
    // Validate the complete snapshot before any write; do not retain mutable maps.
    final snapshot = DocumentLayoutConfig.fromJson(encoded).toJson();
    final operation = _writes.then((_) async {
      final previous = prefs.getString(key);
      final decoded = jsonDecode(previous ?? '{}');
      if (decoded is! Map) {
        throw const FormatException('Invalid stored layout collection');
      }
      final updated = Map<String, dynamic>.from(decoded)
        ..[documentKey] = snapshot;
      try {
        if (!await prefs.setString(key, jsonEncode(updated))) {
          throw StateError('Layout save failed');
        }
      } catch (_) {
        // SharedPreferences updates its in-memory cache before the platform write.
        // Restore it on failure so a later dialog cannot see an unsaved layout.
        try {
          if (previous == null) {
            await prefs.remove(key);
          } else {
            await prefs.setString(key, previous);
          }
        } catch (_) {/* The original write error remains authoritative. */}
        rethrow;
      }
    });
    _writes = operation.catchError((_) {});
    return operation;
  }
}
