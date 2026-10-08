import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/convert_chinese_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/reading_rules.dart';
import 'package:flutter/material.dart';

/// Quick access to the same conversion preference used by advanced settings.
class ChineseConversionButton extends StatelessWidget {
  const ChineseConversionButton({super.key, required this.onChanged});

  final ValueChanged<ReadingRules> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final labels = {
      ConvertChineseMode.none: l10n.readingPageOriginal,
      ConvertChineseMode.t2s: l10n.readingPageSimplified,
      ConvertChineseMode.s2t: l10n.readingPageTraditional,
    };
    return ListenableBuilder(
      listenable: Prefs(),
      builder: (context, _) {
        final selected = Prefs().readingRules.convertChineseMode;
        return PopupMenuButton<ConvertChineseMode>(
          tooltip: l10n.readingPageConvertChinese,
          initialValue: selected,
          onSelected: (mode) {
            if (mode == Prefs().readingRules.convertChineseMode) return;
            final rules =
                Prefs().readingRules.copyWith(convertChineseMode: mode);
            Prefs().readingRules = rules;
            onChanged(rules);
          },
          itemBuilder: (_) => labels.entries
              .map((entry) => CheckedPopupMenuItem(
                    value: entry.key,
                    checked: entry.key == selected,
                    child: Text(entry.value),
                  ))
              .toList(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.translate,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 2),
                Text(labels[selected]!,
                    style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
        );
      },
    );
  }
}
