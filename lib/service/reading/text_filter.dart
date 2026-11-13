import 'dart:ui';
import 'package:modu_reader/models/custom_css_profile.dart';

List<TextRange> filteredTextRanges(String text, List<CustomCssProfile> rules) {
  final ranges = <TextRange>[];
  for (final rule in rules) {
    // OCR has no reliable heading tags; title-only rules do not match it.
    if (!rule.isFilter || rule.scope == 'title') continue;
    for (final word in rule.pattern
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)) {
      var at = 0;
      while ((at = text.indexOf(word, at)) >= 0) {
        var start = at, end = at + word.length;
        if (rule.filterMode == 'paragraph') {
          start = at == 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;
          final newline = text.indexOf('\n', end);
          end = newline < 0 ? text.length : newline + 1;
        }
        ranges.add(TextRange(start: start, end: end));
        at += word.length;
      }
    }
  }
  ranges.sort((a, b) => a.start.compareTo(b.start));
  final merged = <TextRange>[];
  for (final range in ranges) {
    if (merged.isNotEmpty && range.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add(TextRange(
          start: last.start, end: range.end > last.end ? range.end : last.end));
    } else {
      merged.add(range);
    }
  }
  return merged;
}

String maskFilteredText(String text, List<TextRange> ranges) {
  final out = StringBuffer();
  var at = 0;
  for (final range in ranges) {
    out.write(text.substring(at, range.start));
    out.write(text
        .substring(range.start, range.end)
        .replaceAll(RegExp(r'[^\r\n]'), ' '));
    at = range.end;
  }
  out.write(text.substring(at));
  return out.toString();
}
