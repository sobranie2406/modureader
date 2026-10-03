import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Local per-document correction, separate from transferable global settings.
class DocumentTypeStore {
  DocumentTypeStore(this.prefs);
  final SharedPreferences prefs;
  static const key = 'documentTypeOverrides';
  static const types = {'text', 'scanned', 'image-with-text', 'mixed'};

  Map<String, String> _read() {
    try {
      final value = jsonDecode(prefs.getString(key) ?? '{}');
      if (value is! Map) return {};
      return {
        for (final entry in value.entries)
          if (entry.key is String &&
              entry.value is String &&
              types.contains(entry.value))
            entry.key as String: entry.value as String
      };
    } catch (_) {
      return {};
    }
  }

  String? read(String documentKey) => _read()[documentKey];

  Future<void> save(String documentKey, String? kind) async {
    if (documentKey.isEmpty || (kind != null && !types.contains(kind))) {
      throw ArgumentError('Invalid document type correction');
    }
    final values = _read();
    if (kind == null) {
      values.remove(documentKey);
    } else {
      values[documentKey] = kind;
    }
    if (!await prefs.setString(key, jsonEncode(values))) {
      throw StateError('Could not save document type correction');
    }
  }
}
