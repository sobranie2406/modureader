import 'package:anx_reader/l10n/modu_strings.dart';
import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/app_brightness.dart';
import 'package:flutter/material.dart';
import 'reader_menu_group.dart';
import 'package:anx_reader/widgets/settings/setting_help_title.dart';

/// Only wraps Flutter book content. Menus remain siblings outside this layer.
class AppBrightnessLayer extends StatelessWidget {
  const AppBrightnessLayer(
      {super.key, required this.child, required this.controller});

  final Widget child;
  final AppBrightness controller;

  @override
  Widget build(BuildContext context) =>
      Theme.of(context).brightness != Brightness.dark
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
                          color: Colors.black
                              .withValues(alpha: controller.dimOpacity),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, Prefs()]),
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ReaderMenuGroup(
            padding: const EdgeInsets.all(12),
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
                      onPressed: dark
                          ? () => controller
                              .setFollowSystem(!controller.followSystem)
                          : null,
                    ),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: 100,
                        divisions: 100,
                        value: controller.level * 100,
                        label: '${(controller.level * 100).round()}%',
                        semanticFormatterCallback: (v) => '${v.round()}%',
                        onChanged: dark
                            ? (value) => controller.setLevel(value / 100)
                            : null,
                        onChangeEnd: (_) => unawaited(controller.save()),
                      ),
                    ),
                    IconButton.filledTonal(
                      key: const ValueKey('brightness-night'),
                      tooltip: l10n.readingPageStyleNightMode,
                      isSelected: !Prefs().eInkMode && Prefs().readingNightMode,
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.dark_mode_outlined),
                      selectedIcon: const Icon(Icons.dark_mode),
                      onPressed: Prefs().eInkMode
                          ? null
                          : () {
                              final night = !Prefs().readingNightMode;
                              unawaited(Prefs().saveThemeModeToPrefs(
                                  night ? 'dark' : 'light'));
                              Prefs().readingNightMode = night;
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
                SettingHelp(
                    title: Text(
                        ModuStrings.text(
                            context, '深色模式书籍亮度', 'Dark-mode book brightness'),
                        style: Theme.of(context).textTheme.bodySmall),
                    description: Text(ModuStrings.text(
                        context,
                        '仅在深色模式下调暗书籍内容。菜单、工具栏、弹窗及退出阅读后的界面不受影响；100% 保持系统亮度。',
                        'Dims book content only in dark mode. Menus, toolbars, popups and screens outside reading are unaffected. 100% preserves system brightness.'))),
              ],
            )),
      ),
    );
  }
}
