import 'dart:convert';
import 'package:anx_reader/models/pdf_reading_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device-local region positions supplement (never replace) the original CFI.
class PdfReadingStateStore {
  PdfReadingStateStore(this.prefs);
  final SharedPreferences prefs;
  static const key = 'pdfReadingStates';
  static Future<void> _writes = Future.value();

  bool hasSavedMode(String bookKey) {
    try {
      final value = jsonDecode(prefs.getString(key) ?? '{}')[bookKey];
      return value is Map && value['enabled'] is bool;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> read(String bookKey) {
    try {
      final value = jsonDecode(prefs.getString(key) ?? '{}')[bookKey];
      if (value is Map && value['enabled'] is bool) {
        return Map<String, dynamic>.from(value);
      }
    } catch (_) {}
    return {'enabled': false};
  }

  Future<void> setEnabled(String bookKey, bool enabled) =>
      _update(bookKey, {'enabled': enabled, 'position': null, 'cfi': null});

  PdfReadingView readView(String bookKey) {
    try {
      return PdfReadingView.fromJson(read(bookKey)['view']);
    } catch (_) {
      return const PdfReadingView();
    }
  }

  Future<void> saveView(String bookKey, PdfReadingView view, {bool? enabled}) =>
      _update(bookKey, {
        'view': PdfReadingView.fromJson(view.toJson()).toJson(),
        if (enabled != null) 'enabled': enabled
      });

  Future<void> savePosition(String bookKey, String cfi, dynamic position,
      {bool? enabled}) {
    if (position != null) {
      if (position is! Map ||
          position['page'] is! int ||
          position['page'] < 0 ||
          position['panel'] is! int ||
          position['panel'] < 0 ||
          position['panel'] > 8 ||
          position['signature'] is! String ||
          (position['signature'] as String).length > 4096 ||
          cfi.isEmpty) {
        throw const FormatException('Invalid PDF region position');
      }
      final center = position['center'];
      if (center != null &&
          (center is! Map ||
              !['x', 'y'].every((key) =>
                  center[key] is num &&
                  (center[key] as num).isFinite &&
                  center[key] >= 0 &&
                  center[key] <= 1))) {
        throw const FormatException('Invalid PDF viewport position');
      }
      position = {
        'page': position['page'],
        'panel': position['panel'],
        'signature': position['signature'],
        if (center != null) 'center': {'x': center['x'], 'y': center['y']},
      };
    }
    return _update(bookKey, {
      'cfi': cfi,
      'position': position,
      if (enabled != null) 'enabled': enabled
    });
  }

  Future<void> _update(String bookKey, Map<String, dynamic> patch) {
    if (bookKey.isEmpty) throw ArgumentError('Empty document identity');
    final operation = _writes.then((_) async {
      final previous = prefs.getString(key);
      final decoded = jsonDecode(previous ?? '{}');
      if (decoded is! Map) throw const FormatException('Invalid PDF states');
      final all = Map<String, dynamic>.from(decoded);
      all[bookKey] = {...read(bookKey), ...patch};
      try {
        if (!await prefs.setString(key, jsonEncode(all))) {
          throw StateError('PDF reading position save failed');
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
