import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/material.dart';

/// Platform-gated here as well as in the native-to-reader bridge.
class QuickMarkToggle extends StatelessWidget {
  const QuickMarkToggle(
      {super.key,
      required this.enabled,
      required this.onPressed,
      this.platform,
      this.showExit = false});
  final bool enabled;
  final VoidCallback? onPressed;
  final AnxPlatformEnum? platform;
  final bool showExit;

  @override
  Widget build(BuildContext context) {
    final target = platform ?? AnxPlatform.type;
    if (![AnxPlatformEnum.android, AnxPlatformEnum.ios, AnxPlatformEnum.ohos]
        .contains(target)) return const SizedBox.shrink();
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    if (showExit) {
      if (!enabled) return const SizedBox.shrink();
      return Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: TextButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.close, size: 18),
            label: Text(zh ? '快速标记中 · 退出' : 'Quick mark · Exit')),
      );
    }
    return IconButton(
      tooltip: zh
          ? (enabled ? '关闭快速标记' : '快速标记')
          : (enabled ? 'Turn off quick mark' : 'Quick mark'),
      isSelected: enabled,
      icon: const Icon(Icons.draw_outlined),
      selectedIcon: const Icon(Icons.draw),
      onPressed: onPressed,
    );
  }
}
