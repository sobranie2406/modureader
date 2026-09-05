import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/bgimg_type.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/models/bgimg.dart';

/// A deliberate solid-colour selection must not stay hidden behind an opaque
/// background image or be replaced by the automatic day/night theme on reopen.
void selectReadingColorTheme(
  ReadTheme theme, {
  required Prefs prefs,
  required void Function(ReadTheme) apply,
  bool clearBackgroundImage = true,
}) {
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
  prefs.autoAdjustReadingTheme = false;
  prefs.bgimg = image;
  apply();
}
