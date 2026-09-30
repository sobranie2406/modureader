import 'package:flutter/widgets.dart';

/// One locale policy for widgets, system-language changes, and AI defaults.
const appLocales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh', 'TW'),
  Locale('zh', 'LZH'),
  Locale('tr'),
  Locale('de'),
  Locale('ar'),
  Locale('ru'),
  Locale('fr'),
  Locale('es'),
  Locale('it'),
  Locale('pt'),
  Locale('ja'),
  Locale('ko'),
  Locale('ro'),
];

Locale? parseAppLocale(String? value) {
  if (value == null || value.isEmpty || value.toLowerCase() == 'system')
    return null;
  final parts = value.replaceAll('_', '-').split('-');
  final language = parts.first.toLowerCase();
  String? script, country;
  for (final part in parts.skip(1)) {
    if (part.length == 4) {
      script = '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}';
    } else if (part.isNotEmpty) {
      country = part.toUpperCase();
    }
  }
  return Locale.fromSubtags(
      languageCode: language, scriptCode: script, countryCode: country);
}

Locale resolveAppLocale(Iterable<Locale>? preferred,
    [Iterable<Locale> supported = appLocales]) {
  for (final locale in preferred ?? const <Locale>[]) {
    final candidates = supported
        .where((item) => item.languageCode == locale.languageCode)
        .toList();
    if (candidates.isEmpty) continue;
    if (locale.languageCode == 'zh') {
      final country = locale.countryCode?.toUpperCase();
      final target = country == 'LZH'
          ? 'LZH'
          : (locale.scriptCode == 'Hant' ||
                  const {'TW', 'HK', 'MO'}.contains(country))
              ? 'TW'
              : 'CN';
      return candidates.firstWhere((item) => item.countryCode == target,
          orElse: () => candidates.first);
    }
    return candidates.firstWhere((item) => item == locale,
        orElse: () => candidates.first);
  }
  return const Locale('en');
}

String appLocaleKey(Locale locale) {
  final resolved = resolveAppLocale([locale]);
  return resolved.countryCode == null
      ? resolved.languageCode
      : '${resolved.languageCode}-${resolved.countryCode}';
}

Locale currentAppLocale(Locale? manual) => resolveAppLocale(manual == null
    ? WidgetsBinding.instance.platformDispatcher.locales
    : [manual]);
