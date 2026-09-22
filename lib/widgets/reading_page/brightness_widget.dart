import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/app_brightness.dart';
import 'package:flutter/material.dart';

/// macOS must not paint over native WebViews, even with IgnorePointer: Flutter's
/// platform-view compositor excludes painted regions from native hit testing.
/// Other platforms keep [child] outside the listener while dragging.
class AppBrightnessLayer extends StatelessWidget {
  const AppBrightnessLayer(
      {super.key, required this.child, required this.controller});

  final Widget child;
  final AppBrightness controller;

  @override
  Widget build(BuildContext context) => !controller.paintsFlutterDimming
      ? child
      : Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (_, __) => ColoredBox(
                      key: const ValueKey('app-flutter-brightness-dimmer'),
                      color:
                          Colors.black.withValues(alpha: controller.dimOpacity),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
}

class BrightnessWidget extends StatelessWidget {
  const BrightnessWidget({
    super.key,
    required this.controller,
    required this.onNightModeChanged,
  });

  final AppBrightness controller;
  final VoidCallback onNightModeChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([controller, Prefs()]),
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  key: const ValueKey('brightness-auto'),
                  tooltip: l10n.readingBrightnessFollowSystem,
                  isSelected: controller.followSystem,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.brightness_auto_outlined),
                  selectedIcon: const Icon(Icons.brightness_auto),
                  onPressed: () =>
                      controller.setFollowSystem(!controller.followSystem),
                ),
                Expanded(
                  child: Slider(
                    min: AppBrightness.minimum,
                    max: 1,
                    value: controller.level,
                    label: '${(controller.level * 100).round()}%',
                    semanticFormatterCallback: (v) => '${(v * 100).round()}%',
                    onChanged: controller.setLevel,
                    onChangeEnd: (_) => unawaited(controller.save()),
                  ),
                ),
                IconButton.filledTonal(
                  key: const ValueKey('brightness-night'),
                  tooltip: l10n.readingPageStyleNightMode,
                  isSelected: Prefs().readingNightMode,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.dark_mode_outlined),
                  selectedIcon: const Icon(Icons.dark_mode),
                  onPressed: () {
                    Prefs().readingNightMode = !Prefs().readingNightMode;
                    onNightModeChanged();
                  },
                ),
              ],
            ),
            Text(
              controller.followSystem
                  ? l10n.readingBrightnessFollowSystem
                  : '${(controller.level * 100).round()}%',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Text(
              controller.nativeDimmingUnavailable
                  ? (Localizations.localeOf(context).languageCode == 'zh'
                      ? '亮度调节暂不可用，已保留系统亮度以确保阅读操作正常。'
                      : 'Brightness adjustment is unavailable. System brightness is preserved so reader input remains usable.')
                  : controller.usesWindowBrightness
                      ? l10n.readingBrightnessWindowHint
                      : l10n.readingBrightnessDimHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
