import 'package:anx_reader/enums/translation_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Translation controls belong to the reader toolbar, never the text surface.
class TranslationToolbarAction extends StatelessWidget {
  const TranslationToolbarAction({
    super.key,
    this.mode,
    required this.onOpenSettings,
    required this.onStop,
  });

  final ValueListenable<TranslationModeEnum>? mode;
  final VoidCallback onOpenSettings;
  final VoidCallback onStop;

  Widget _button(BuildContext context, TranslationModeEnum current) {
    final tooltip = L10n.of(context).settingsTranslate;
    if (current == TranslationModeEnum.off) {
      return IconButton(
        key: const ValueKey('reader-translation-button'),
        tooltip: tooltip,
        icon: const Icon(Icons.translate_outlined),
        onPressed: onOpenSettings,
      );
    }
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return PopupMenuButton<bool>(
      key: const ValueKey('reader-translation-button'),
      tooltip: tooltip,
      icon: const Badge(child: Icon(Icons.translate_outlined)),
      onSelected: (stop) => stop ? onStop() : onOpenSettings(),
      itemBuilder: (_) => [
        PopupMenuItem(
          key: const ValueKey('reader-toolbar-stop-translation'),
          value: true,
          child: Text(zh ? '停止翻译' : 'Stop translation'),
        ),
        PopupMenuItem(
          value: false,
          child: Text(zh ? '翻译设置' : 'Translation settings'),
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
