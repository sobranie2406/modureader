import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';

class LongPressSelectionTile extends StatelessWidget {
  const LongPressSelectionTile(
      {super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return SwitchListTile(
      key: const ValueKey('long-press-select-paragraph'),
      contentPadding: EdgeInsets.zero,
      title: Text(ModuStrings.value(locale, 'reading_long_press_paragraph',
          'Select paragraph on long press')),
      subtitle: Text(ModuStrings.value(locale, 'reading_long_press_help',
          'Off: select the word. On: select the paragraph. Drag the selection handles to adjust either range.')),
      value: value,
      onChanged: onChanged,
    );
  }
}
