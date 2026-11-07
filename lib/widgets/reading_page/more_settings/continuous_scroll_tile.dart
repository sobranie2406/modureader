import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';

class ContinuousScrollTile extends StatefulWidget {
  const ContinuousScrollTile({super.key, required this.onChanged});

  final ValueChanged<bool> onChanged;

  @override
  State<ContinuousScrollTile> createState() => _ContinuousScrollTileState();
}

class _ContinuousScrollTileState extends State<ContinuousScrollTile> {
  @override
  Widget build(BuildContext context) => SwitchListTile(
        key: const ValueKey('continuous-scroll'),
        contentPadding: EdgeInsets.zero,
        title: SettingHelpTitle(
            title: ModuStrings.text(
                context, '跨章节连续滚动', 'Scroll continuously across chapters'),
            description: ModuStrings.text(context, "关闭后逐章滚动，章末点击翻页进入下一章。",
                "Turn off to scroll one chapter at a time. Tap to enter the next chapter.")),
        value: Prefs().continuousScroll,
        onChanged: (value) {
          setState(() => Prefs().continuousScroll = value);
          widget.onChanged(value);
        },
      );
}
