import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/material.dart';

class TapOnlyPageTurnTile extends StatelessWidget {
  const TapOnlyPageTurnTile(
      {super.key, required this.value, required this.onChanged, this.platform});

  final bool value;
  final ValueChanged<bool> onChanged;
  final AnxPlatformEnum? platform;

  @override
  Widget build(BuildContext context) {
    final current = platform ?? AnxPlatform.type;
    if (![AnxPlatformEnum.android, AnxPlatformEnum.ios, AnxPlatformEnum.ohos]
        .contains(current)) return const SizedBox.shrink();
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return SwitchListTile(
      key: const ValueKey('tap-only-page-turn'),
      contentPadding: EdgeInsets.zero,
      title: Text(zh ? '仅点击翻页' : 'Tap-only page turning'),
      subtitle: Text(zh
          ? '开启后，分页模式下滑动、拖动不翻页，也不触发上下拉手势；关闭后可滑动翻页。不影响选词、快速标记和滚动阅读模式。'
          : 'In page mode, disable swipe navigation and pull gestures. Turn off to allow swipes. Text selection, quick mark and scrolling mode are unchanged.'),
      value: value,
      onChanged: onChanged,
    );
  }
}
