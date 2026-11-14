import 'package:flutter/material.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/widgets/reading_page/style_widget.dart';

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
              title: Text(ModuStrings.text(context, '自动滚动翻页', 'Auto scroll')),
              value: Prefs().autoScrollEnabled,
              onChanged: (value) => Prefs().autoScrollEnabled = value));
}
