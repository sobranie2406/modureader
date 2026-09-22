import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/bgimg_type.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/models/bgimg.dart';

ReadTheme readingThemeForDisplay(Prefs prefs,
    {List<ReadTheme> themes = const [], bool isDarkMode = false}) {
  if (prefs.readingNightMode) {
    return ReadTheme(
        backgroundColor: 'FF1C1C1E',
        textColor: 'FFD8D8D8',
        backgroundImagePath: '');
  }
  if (prefs.autoAdjustReadingTheme && themes.length >= 2) {
    return themes[isDarkMode ? 1 : 0];
  }
  return prefs.readTheme;
}

String readingBackgroundForDisplay(Prefs prefs, {required bool isDarkMode}) {
  // A bright image must not cover the night palette. Do not delete it: turning
  // night mode off restores the original image and its day/night selection.
  if (prefs.readingNightMode) return 'none';
  return prefs.bgimg.getEffectiveUrl(
      isDarkMode: isDarkMode, autoAdjust: prefs.autoAdjustReadingTheme);
}

/// A deliberate solid-colour selection must not stay hidden behind an opaque
/// background image or be replaced by the automatic day/night theme on reopen.
void selectReadingColorTheme(
  ReadTheme theme, {
  required Prefs prefs,
  required void Function(ReadTheme) apply,
  bool clearBackgroundImage = true,
}) {
  prefs.readingNightMode = false;
  prefs.autoAdjustReadingTheme = false;
  if (clearBackgroundImage) {
    prefs.bgimg = prefs.bgimg
        .copyWith(type: BgimgType.none, path: 'none', nightPath: null);
  }
  prefs.saveReadThemeToPrefs(theme);
  apply(theme);
}

void selectReadingBackground(
  BgimgModel image, {
  required Prefs prefs,
  required void Function() apply,
}) {
  prefs.readingNightMode = false;
  prefs.autoAdjustReadingTheme = false;
  prefs.bgimg = image;
  apply();
}
