import 'package:flutter/material.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/widgets/reading_page/style_widget.dart';
import 'package:modu_reader/widgets/settings/setting_help_title.dart';

class AutoScrollTile extends StatelessWidget {
  const AutoScrollTile({super.key, this.forceScroll = false});
  final bool forceScroll;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Prefs(),
      builder: (context, _) => !forceScroll &&
              Prefs().pageTurnStyle != PageTurn.scroll
          ? const SizedBox.shrink()
          : SwitchListTile(
              key: const ValueKey('auto-scroll-enabled'),
              contentPadding: EdgeInsets.zero,
              title: Prefs().eInkMode
                  ? SettingHelpTitle(
                      title: ModuStrings.text(context, '自动滚动翻页', 'Auto scroll'),
                      description: ModuStrings.text(
                          context,
                          '电纸书模式按当前阅读速度间隔滚动，不连续刷屏。',
                          'E-ink mode scrolls in timed steps at the selected reading speed.'))
                  : Text(ModuStrings.text(context, '自动滚动翻页', 'Auto scroll')),
              value: Prefs().autoScrollEnabled,
              onChanged: (value) => Prefs().autoScrollEnabled = value));
}
