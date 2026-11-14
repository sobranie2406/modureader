import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:flutter/material.dart';

class ScrollPagePercentTile extends StatefulWidget {
  const ScrollPagePercentTile({super.key, required this.onChanged});

  final ValueChanged<int> onChanged;

  @override
  State<ScrollPagePercentTile> createState() => _ScrollPagePercentTileState();
}

class _ScrollPagePercentTileState extends State<ScrollPagePercentTile> {
  late int _percent = Prefs().scrollPagePercent;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: SettingHelpTitle(
              title: ModuStrings.text(context, '滚动翻页幅度', 'Scroll page step'),
              description: zh
                  ? '每次翻页移动一屏的 $_percent%；开启行对齐时，以此为上限并保留一行。不影响手指滚动。'
                  : 'Move $_percent% of a screen per turn. With line alignment, this is the maximum step and one line stays visible. Free scrolling is unchanged.'),
          trailing: Text('$_percent%'),
        ),
        Slider(
          key: const ValueKey('scroll-page-percent'),
          value: _percent.toDouble(),
          min: 80,
          max: 100,
          divisions: 20,
          label: '$_percent%',
          semanticFormatterCallback: (value) => '${value.round()}%',
          onChanged: (value) => setState(() => _percent = value.round()),
          onChangeEnd: (value) {
            final percent = value.round();
            Prefs().scrollPagePercent = percent;
            widget.onChanged(percent);
          },
        ),
      ],
    );
  }
}
