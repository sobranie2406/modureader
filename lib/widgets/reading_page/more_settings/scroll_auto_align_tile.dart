import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';

class ScrollAutoAlignTile extends StatefulWidget {
  const ScrollAutoAlignTile({super.key, required this.onChanged});

  final ValueChanged<bool> onChanged;

  @override
  State<ScrollAutoAlignTile> createState() => _ScrollAutoAlignTileState();
}

class _ScrollAutoAlignTileState extends State<ScrollAutoAlignTile> {
  @override
  Widget build(BuildContext context) => SwitchListTile(
        key: const ValueKey('scroll-auto-align'),
        contentPadding: EdgeInsets.zero,
        title: SettingHelpTitle(
            title:
                ModuStrings.text(context, '滚动翻页自动对齐', 'Auto-align scrolling'),
            description: ModuStrings.text(context, "滚动停止时，将文字对齐页面边缘。",
                "Align text to the page edge when scrolling stops.")),
        value: Prefs().scrollAutoAlign,
        onChanged: (value) {
          setState(() => Prefs().scrollAutoAlign = value);
          widget.onChanged(value);
        },
      );
}
