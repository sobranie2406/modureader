import 'package:anx_reader/config/shared_preference_provider.dart';
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
          title: Text(zh ? '滚动翻页幅度' : 'Scroll page step'),
          trailing: Text('$_percent%'),
          subtitle: Text(zh
              ? '滚动模式下，每次翻页移动一屏的 $_percent%，保留 ${100 - _percent}% 重叠内容。不影响手指自由滚动。'
              : 'Move $_percent% of a screen per page turn, with ${100 - _percent}% overlap. Free scrolling is unchanged.'),
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
