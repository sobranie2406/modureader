import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/enums/translation_mode.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'classical_translation_icon.dart';

/// Translation controls belong to the reader toolbar, never the text surface.
class TranslationToolbarAction extends StatelessWidget {
  const TranslationToolbarAction({
    super.key,
    this.mode,
    this.classical = false,
    required this.onOpenSettings,
    required this.onStop,
  });

  final ValueListenable<TranslationModeEnum>? mode;
  final bool classical;
  final VoidCallback onOpenSettings;
  final VoidCallback onStop;

  Widget _button(BuildContext context, TranslationModeEnum current) {
    final tooltip = classical
        ? ModuStrings.text(context, '文言文翻译', 'Classical Chinese')
        : L10n.of(context).settingsTranslate;
    final icon = classical
        ? const ClassicalTranslationIcon()
        : const Icon(Icons.translate_outlined);
    final key = ValueKey(classical
        ? 'reader-classical-translation-button'
        : 'reader-translation-button');
    if (current == TranslationModeEnum.off) {
      return IconButton(
        key: key,
        tooltip: tooltip,
        icon: icon,
        onPressed: onOpenSettings,
      );
    }
    return PopupMenuButton<bool>(
      clipBehavior: Clip.antiAlias,
      popUpAnimationStyle: AppMotion.style,
      key: key,
      tooltip: tooltip,
      icon: Badge(child: icon),
      onSelected: (stop) => stop ? onStop() : onOpenSettings(),
      itemBuilder: (_) => [
        PopupMenuItem(
          key: ValueKey(classical
              ? 'reader-toolbar-stop-classical-translation'
              : 'reader-toolbar-stop-translation'),
          value: true,
          child: Text(ModuStrings.text(context, '停止翻译', 'Stop translation')),
        ),
        PopupMenuItem(
          value: false,
          child:
              Text(ModuStrings.text(context, '翻译设置', 'Translation settings')),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final listenable = mode;
    return listenable == null
        ? _button(context, TranslationModeEnum.off)
        : ValueListenableBuilder<TranslationModeEnum>(
            valueListenable: listenable,
            builder: (context, current, _) => _button(context, current),
          );
  }
}
