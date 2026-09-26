import 'dart:convert';
import 'package:anx_reader/models/custom_css_profile.dart';

/// Portable CSS only. Never exports book IDs or reads referenced fonts/images.
class CustomCssTransfer {
  static const maxBytes = 1024 * 1024;
  static const kind = 'modu-css-profiles';

  static String encode(List<CustomCssProfile> profiles) {
    if (profiles.every((p) => p.isEmpty)) {
      throw const FormatException('No profiles to export');
    }
    if (profiles.where((p) => !p.isEmpty).length > customCssProfileCount) {
      throw const FormatException('Expected 1–32 profiles');
    }
    final text = const JsonEncoder.withIndent('  ').convert({
      'kind': kind,
      'version': 1,
      'profiles':
          profiles.where((p) => !p.isEmpty).map((p) => p.toJson()).toList(),
    });
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('CSS file too large');
    }
    return text;
  }

  static List<CustomCssProfile> decode(String text,
      {required String fileName}) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('CSS file too large');
    }
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    if (fileName.toLowerCase().endsWith('.css')) {
      if (text.trim().isEmpty) throw const FormatException('Empty CSS');
      final name = fileName.replaceAll('\\', '/').split('/').last;
      return [
        CustomCssProfile(
            name: name.substring(0, name.length - 4).charactersSafe, css: text)
      ];
    }
    final data = jsonDecode(text);
    if (data is! Map ||
        data['kind'] != kind ||
        data['version'] != 1 ||
        data['profiles'] is! List) {
      throw const FormatException('Not a Modu CSS bundle');
    }
    final entries = data['profiles'] as List;
    if (entries.isEmpty || entries.length > customCssProfileCount) {
      throw const FormatException('Expected 1–32 profiles');
    }
    return entries.map((entry) {
      if (entry is! Map ||
          entry['name'] is! String ||
          entry['css'] is! String ||
          (entry['name'] as String).length > 200) {
        throw const FormatException('Invalid CSS profile');
      }
      if ((entry.containsKey('pattern') &&
              (entry['pattern'] is! String ||
                  (entry['pattern'] as String).length > 512)) ||
          (entry.containsKey('scope') &&
              !const ['all', 'title', 'body'].contains(entry['scope']))) {
        throw const FormatException('Invalid highlight rule');
      }
      if (entry.containsKey('visual') && entry['visual'] is! String) {
        throw const FormatException('Invalid visual CSS');
      }
      return CustomCssProfile.fromJson(entry);
    }).toList();
  }

  /// Append into unused slots. Never silently overwrite another book's CSS.
  static List<CustomCssProfile> append(
      List<CustomCssProfile> existing, List<CustomCssProfile> imported) {
    final slots = [
      for (var i = 0; i < existing.length; i++)
        if (existing[i].isEmpty) i
    ];
    if (slots.length < imported.length) {
      throw const FormatException('Not enough empty CSS slots');
    }
    final result = [...existing];
    for (var i = 0; i < imported.length; i++) {
      result[slots[i]] = imported[i];
    }
    return result;
  }
}

extension on String {
  String get charactersSafe => String.fromCharCodes(runes.take(40));
}
