import 'dart:async';

import 'package:flutter/services.dart';

/// Uses system word segmentation (Android ICU / macOS NaturalLanguage) without
/// network or a bundled dictionary. Also used by the native OCR reflow surface.
class ReaderWordSelection {
  static const _channel = MethodChannel('com.modu.reader/word_selection');

  static Future<List<int>?> bounds(Object? request) async {
    if (request is! Map) {
      return null;
    }
    final text = request['text'];
    final offset = request['offset'];
    final locale = request['locale'];
    if (text is! String ||
        text.isEmpty ||
        text.length > 65536 ||
        offset is! int ||
        offset < 0 ||
        offset > text.length ||
        (locale != null && (locale is! String || locale.length > 128))) {
      return null;
    }
    try {
      final result = await _channel.invokeMethod<Object?>('bounds', {
        'text': text,
        'offset': offset,
        'locale': locale,
      }).timeout(const Duration(milliseconds: 300));
      if (result is! List || result.length != 2) {
        return null;
      }
      final start = result[0];
      final end = result[1];
      final index = offset == text.length ? offset - 1 : offset;
      if (start is! int ||
          end is! int ||
          start < 0 ||
          end > text.length ||
          start > index ||
          index >= end) {
        return null;
      }
      return [start, end];
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}
