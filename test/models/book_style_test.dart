import 'dart:convert';

import 'package:anx_reader/models/book_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('simulated bold defaults off, including legacy styles', () {
    expect(BookStyle().simulateBold, isFalse);
    final legacy = BookStyle(fontWeight: 600).toMap()..remove('simulateBold');
    final restored = BookStyle.fromJson(jsonEncode(legacy));
    expect(restored.simulateBold, isFalse);
    expect(restored.fontWeight, 600);
  });

  test('simulated bold persists in maps, JSON and copies', () {
    final style = BookStyle(fontWeight: 640, simulateBold: true);
    expect(style.toMap()['simulateBold'], isTrue);
    expect(jsonDecode(style.toJson())['simulateBold'], isTrue);
    expect(BookStyle.fromJson(style.toJson()).simulateBold, isTrue);
    expect(style.copyWith(fontSize: 1.6).simulateBold, isTrue);
    expect(style.copyWith(simulateBold: false).simulateBold, isFalse);
    expect(style.copyWith(simulateBold: false).fontWeight, 640);
  });

  test('invalid imported simulated bold settings are rejected', () {
    for (final invalid in ['true', 1, [], {}]) {
      final data = {...BookStyle().toMap(), 'simulateBold': invalid};
      expect(() => BookStyle.fromJson(jsonEncode(data)), throwsFormatException);
    }
  });
}
