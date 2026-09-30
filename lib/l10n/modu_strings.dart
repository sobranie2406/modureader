import 'package:flutter/widgets.dart';
import 'package:anx_reader/l10n/app_language.dart';
import 'package:anx_reader/l10n/modu_catalogs.g.dart';

/// Localized newer UI and bundled prompts. Defaults are never saved as edits.
abstract final class ModuStrings {
  static String value(Locale locale, String key, String fallback) =>
      moduCatalogs[appLocaleKey(locale)]?[key] ??
      moduCatalogs['en']?[key] ??
      fallback;

  static String text(BuildContext context, String zh, String en) {
    return label(Localizations.localeOf(context), zh, en);
  }

  /// Translate the stable template before inserting user data or numbers.
  static String format(BuildContext context, String zh, String en,
      {required Map<String, Object> values}) {
    return text(context, zh, en).replaceAllMapped(RegExp(r'\{([a-zA-Z_]+)\}'),
        (match) => values[match[1]]?.toString() ?? match[0]!);
  }

  static String label(Locale locale, String zh, String en) {
    var key = moduSourceKeys[zh];
    if (key == null && locale.languageCode != 'zh') {
      for (final entry in moduCatalogs['en']?.entries ??
          const <MapEntry<String, String>>[]) {
        if (entry.key.startsWith('ui_') && entry.value == en) {
          key = entry.key;
          break;
        }
      }
    }
    return key == null
        ? (locale.languageCode == 'zh' ? zh : en)
        : value(locale, key, en);
  }

  static bool isDefault(String key, String value, String legacy) =>
      value.trim() == legacy.trim() ||
      moduCatalogs.values
          .any((catalog) => catalog[key]?.trim() == value.trim());

  static bool isBundledText(String original, String value) {
    final key = moduSourceKeys[original];
    return key == null ? original == value : isDefault(key, value, original);
  }
}
