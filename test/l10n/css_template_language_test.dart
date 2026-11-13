import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:modu_reader/l10n/app_language.dart';
import 'package:modu_reader/l10n/modu_catalogs.g.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/custom_css_profile.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/localization/catalog.dart' as catalog;

void main() {
  test('all built-in CSS names and model title have every app locale', () {
    for (final locale in appLocales) {
      final translations = moduCatalogs[appLocaleKey(locale)]!;
      for (final profile in customCssTemplates) {
        final original = profile.toJson();
        final key = moduSourceKeys[profile.name];
        expect(key, isNotNull, reason: profile.name);
        expect(profile.localizedName(locale), translations[key]);
        if (!['zh', 'ja'].contains(locale.languageCode)) {
          expect(profile.localizedName(locale), isNot(profile.name));
        }
        expect(profile.toJson(), original);
        // Imported defaults saved in another language still follow app locale.
        final imported =
            CustomCssProfile(name: profile.localizedName(const Locale('fr')));
        expect(imported.localizedName(locale), profile.localizedName(locale));
      }
      expect(ModuStrings.label(locale, '离线本地模型设置', 'fallback'),
          translations[moduSourceKeys['离线本地模型设置']]);
      expect(
          const CustomCssProfile(name: '我的 CSS / My CSS').localizedName(locale),
          '我的 CSS / My CSS');
    }
  });

  test('catalog extraction includes implicit CSS template constructors', () {
    catalog.entries.clear();
    const path = 'lib/models/custom_css_profile.dart';
    parseString(content: File(path).readAsStringSync())
        .unit
        .accept(catalog.Extract(path));
    for (final profile in customCssTemplates) {
      expect(
          catalog.entries[catalog.keyFor(profile.name)]?['zh'], profile.name);
    }
  });
}
