import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/utils/theme_mode_to_string.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:flutter/material.dart';

class ChangeThemeMode extends StatefulWidget {
  const ChangeThemeMode({super.key});

  @override
  ChangeThemeModeState createState() => ChangeThemeModeState();
}

class ChangeThemeModeState extends State<ChangeThemeMode> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: Prefs(),
        builder: (context, _) {
          // Always read from preferences so two mounted instances can never
          // show different selections.
          final themeMode = themeModeToString(Prefs().themeMode);
          return AnxSegmentedButton<String>(
            enabled: !Prefs().eInkMode,
            segments: <SegmentButtonItem<String>>[
              SegmentButtonItem(
                value: 'system',
                label: L10n.of(context).settingsSystemMode,
                icon: const Icon(Icons.brightness_auto),
              ),
              SegmentButtonItem(
                value: 'dark',
                label: L10n.of(context).settingsDarkMode,
                icon: const Icon(Icons.brightness_2),
              ),
              SegmentButtonItem(
                value: 'light',
                label: L10n.of(context).settingsLightMode,
                icon: const Icon(Icons.brightness_5),
              ),
            ],
            selected: {Prefs().eInkMode ? 'light' : themeMode},
            onSelectionChanged: Prefs().eInkMode
                ? null
                : (Set<String> newSelection) {
                    Prefs().saveThemeModeToPrefs(newSelection.first);
                    setState(() {});
                  },
          );
        });
  }
}
