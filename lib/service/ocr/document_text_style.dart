import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OCR/reflow appearance only; never writes BookStyle or original-page state.
class DocumentTextStyle {
  const DocumentTextStyle(
      {this.size = 20,
      this.height = 1.6,
      this.weight = 1,
      this.spacing = 0,
      this.margin = 20,
      this.serif = false,
      this.justify = false});
  final double size, height, weight, spacing, margin;
  final bool serif, justify;
  TextStyle get textStyle => TextStyle(
      fontSize: size,
      height: height,
      letterSpacing: spacing,
      fontFamily: serif ? 'SourceHanSerif' : null,
      fontWeight:
          FontWeight.values[((weight * 400 / 100).round() - 1).clamp(0, 8)]);
  TextAlign get alignment => justify ? TextAlign.justify : TextAlign.start;
  Map<String, dynamic> toJson() => {
        'size': size,
        'height': height,
        'weight': weight,
        'spacing': spacing,
        'margin': margin,
        'serif': serif,
        'justify': justify
      };
  factory DocumentTextStyle.fromJson(dynamic value) {
    final v = value is Map ? value : const {};
    double number(String key, double fallback, double min, double max) {
      final n = v[key];
      return n is num && n.isFinite ? n.toDouble().clamp(min, max) : fallback;
    }

    return DocumentTextStyle(
        size: number('size', 20, 14, 40),
        height: number('height', 1.6, 1.2, 2.4),
        weight: number('weight', 1, .5, 2),
        spacing: number('spacing', 0, 0, 6),
        margin: number('margin', 20, 0, 60),
        serif: v['serif'] == true,
        justify: v['justify'] == true);
  }
  DocumentTextStyle withValue(String key, Object value) =>
      DocumentTextStyle.fromJson({...toJson(), key: value});
}

class DocumentTextStyleStore {
  DocumentTextStyleStore(this.prefs);
  final SharedPreferences prefs;
  static const key = 'documentTextStyles';
  static Future<void> _writes = Future.value();
  Map<String, dynamic> _read() {
    try {
      final v = jsonDecode(prefs.getString(key) ?? '{}');
      return v is Map ? Map<String, dynamic>.from(v) : {};
    } catch (_) {
      return {};
    }
  }

  DocumentTextStyle read(String book) =>
      DocumentTextStyle.fromJson(_read()[book]);
  Future<void> save(String book, DocumentTextStyle style) {
    if (book.isEmpty) throw ArgumentError('Missing book identity');
    final operation = _writes.then((_) async {
      final previous = prefs.getString(key);
      try {
        if (!await prefs.setString(
            key, jsonEncode({..._read(), book: style.toJson()}))) {
          throw StateError('Could not save OCR style');
        }
      } catch (_) {
        // SharedPreferences updates its in-memory cache before platform I/O.
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
