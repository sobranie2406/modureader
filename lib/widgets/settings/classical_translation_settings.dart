import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/ai_provider.dart';
import 'package:modu_reader/service/translate/classical_translation.dart';
import 'package:flutter/material.dart';
import 'translation_api_settings.dart';
import 'package:modu_reader/widgets/settings/settings_tile.dart';

class ClassicalTranslationSettings extends StatefulWidget {
  const ClassicalTranslationSettings(
      {super.key,
      this.showCredentials = true,
      this.onChanged,
      this.onConfigure});
  final bool showCredentials;
  final VoidCallback? onChanged;
  final VoidCallback? onConfigure;
  @override
  State<ClassicalTranslationSettings> createState() =>
      _ClassicalTranslationSettingsState();
}

class _ClassicalTranslationSettingsState
    extends State<ClassicalTranslationSettings> {
  String label(String zh, String en) => ModuStrings.text(context, zh, en);
  Widget choice<T>(
          {required Key key,
          required String title,
          required IconData icon,
          required T? value,
          required Map<T, String> options,
          required void Function(T) onChanged,
          String? hint}) =>
      SettingsTile.navigation(
          key: key,
          leading: Icon(icon),
          title: Text(title),
          value: Text(options[value] ?? hint ?? label('未配置', 'Not configured')),
          enabled: options.isNotEmpty,
          onPressed: (_) async {
            final selected = await showDialog<T>(
                context: context,
                builder: (context) =>
                    SimpleDialog(title: Text(title), children: [
                      for (final option in options.entries)
                        SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, option.key),
                            child: Row(children: [
                              Expanded(child: Text(option.value)),
                              if (option.key == value) const Icon(Icons.check)
                            ]))
                    ]));
            if (selected != null && mounted) onChanged(selected);
          });
  void changed() {
    setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = Prefs();
    final models = <AiProvider>[];
    for (final raw in prefs.getAiProviders()) {
      try {
        final model =
            AiProvider.fromJson(Map<String, dynamic>.from(raw as Map));
        if (model.enabled &&
            model.hasValidKey &&
            model.model.trim().isNotEmpty) {
          models.add(model);
        }
      } catch (_) {
        /* Malformed legacy providers are repaired in AI settings. */
      }
    }
    final engine = prefs.classicalTranslationEngine;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          choice<ClassicalTranslationDirection>(
              key: ValueKey(
                  'classical-direction-${prefs.classicalTranslationDirection.name}'),
              value: prefs.classicalTranslationDirection,
              icon: Icons.swap_horiz,
              title: label('翻译方向', 'Translation direction'),
              options: {
                ClassicalTranslationDirection.toModern:
                    label('文言文 → 现代汉语', 'Classical → Modern Chinese'),
                ClassicalTranslationDirection.toClassical:
                    label('现代汉语 → 文言文', 'Modern → Classical Chinese'),
              },
              onChanged: (value) {
                prefs.classicalTranslationDirection = value;
                changed();
              }),
          choice<ClassicalTranslationEngine>(
              key: ValueKey('classical-engine-${engine.name}'),
              value: engine,
              icon: Icons.translate_outlined,
              title: label('翻译引擎', 'Translation engine'),
              options: {
                ClassicalTranslationEngine.ai: 'AI',
                ClassicalTranslationEngine.baidu:
                    label('百度翻译', 'Baidu Translate'),
                ClassicalTranslationEngine.microsoft: 'Microsoft Translator',
              },
              onChanged: (value) {
                prefs.classicalTranslationEngine = value;
                changed();
              }),
          if (engine == ClassicalTranslationEngine.ai) ...[
            choice<String>(
                key: ValueKey(
                    'classical-model-${prefs.classicalTranslationAiService}'),
                value: models
                        .any((m) => m.id == prefs.classicalTranslationAiService)
                    ? prefs.classicalTranslationAiService
                    : null,
                icon: Icons.smart_toy_outlined,
                title: label('AI 模型', 'AI model'),
                hint:
                    label('请先在 AI 设置中配置模型', 'Configure a model in AI settings'),
                options: {
                  for (final m in models) m.id: '${m.title} · ${m.model}'
                },
                onChanged: (value) {
                  prefs.classicalTranslationAiService = value;
                  changed();
                }),
          ],
          if (widget.showCredentials && engine != ClassicalTranslationEngine.ai)
            TranslationApiSettings(
                key: ValueKey(engine),
                engine: engine,
                onChanged: widget.onChanged),
          if (!widget.showCredentials && widget.onConfigure != null)
            TextButton.icon(
                onPressed: widget.onConfigure,
                icon: const Icon(Icons.settings_outlined),
                label: Text(label('配置翻译服务', 'Configure translation service'))),
          const SizedBox(height: 8),
        ]);
  }
}
