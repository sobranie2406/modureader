import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/tts/mimo_voice_presets.dart';
import 'package:anx_reader/service/tts/readany_compatible_tts_backend.dart';
import 'package:flutter/material.dart';

/// Edits the same draft as the connection form. Never saves or starts synthesis.
class MimoVoiceSettings extends StatefulWidget {
  const MimoVoiceSettings({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<MimoVoiceSettings> createState() => _MimoVoiceSettingsState();
}

class _MimoVoiceSettingsState extends State<MimoVoiceSettings> {
  late final TextEditingController _description;

  @override
  void initState() {
    super.initState();
    _description = TextEditingController(text: _prompt);
  }

  String get _prompt => widget.config['stylePrompt']?.toString() ?? '';

  @override
  void didUpdateWidget(covariant MimoVoiceSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_description.text != _prompt) {
      _description.value = TextEditingValue(
        text: _prompt,
        selection: TextSelection.collapsed(offset: _prompt.length),
      );
    }
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  void _change(String key, String value) =>
      widget.onChanged({...widget.config, key: value});

  @override
  Widget build(BuildContext context) {
    final model = widget.config['model']?.toString() ?? MimoVoicePresets.model;
    final design = model == MimoVoicePresets.designModel;
    final templates =
        design ? MimoVoicePresets.designs : MimoVoicePresets.styles;
    final selected = templates.entries
        .where((entry) => ModuStrings.isBundledText(entry.value, _prompt))
        .map((entry) => entry.key)
        .firstOrNull;
    final voice = widget.config['voice']?.toString() ?? 'mimo_default';
    final voices = XiaomiMimoTtsProvider().bundledVoices;
    const models = [MimoVoicePresets.model, MimoVoicePresets.designModel];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('mimo-model'),
          initialValue: model,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: ModuStrings.text(context, '语音模式', 'Speech mode')),
          items: [
            DropdownMenuItem(
                value: models[0],
                child:
                    Text(ModuStrings.text(context, '官方预置音色', 'Preset voices'))),
            DropdownMenuItem(
                value: models[1],
                child:
                    Text(ModuStrings.text(context, '文字设计音色', 'Voice design'))),
            if (!models.contains(model))
              DropdownMenuItem(
                  value: model,
                  child: Text(ModuStrings.text(context, '旧模型不受支持，请重新选择',
                      'Unsupported model — select another'))),
          ],
          onChanged: (value) {
            if (value != null) _change('model', value);
          },
        ),
        const SizedBox(height: 12),
        if (!design)
          DropdownButtonFormField<String>(
            key: const ValueKey('mimo-voice'),
            initialValue: voice,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: ModuStrings.text(context, '预置音色', 'Preset voice')),
            items: [
              for (final item in voices)
                DropdownMenuItem(
                  value: item.shortName,
                  child: Text(item.shortName == 'mimo_default'
                      ? ModuStrings.text(
                          context, '默认音色（由服务地区决定）', 'Default voice (regional)')
                      : '${item.name} · ${item.locale == 'zh-CN' ? ModuStrings.text(context, '中文', 'Chinese') : ModuStrings.text(context, '英文', 'English')}'),
                ),
              if (!voices.any((item) => item.shortName == voice))
                DropdownMenuItem(
                    value: voice,
                    child: Text(ModuStrings.text(context, '旧音色不受支持，请重新选择',
                        'Unsupported voice — select another'))),
            ],
            onChanged: (value) {
              if (value != null) _change('voice', value);
            },
          ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('mimo-template-$design-$selected'),
          initialValue: selected ?? '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText:
                ModuStrings.text(context, '描述预设', 'Description template'),
          ),
          items: [
            DropdownMenuItem(
                value: '',
                child: Text(ModuStrings.text(
                    context, '自定义（保留当前描述）', 'Custom (keep current text)'))),
            for (final name in templates.keys)
              DropdownMenuItem(
                  value: name,
                  child: Text(ModuStrings.text(context, name, name))),
          ],
          onChanged: (value) {
            if (templates.containsKey(value)) {
              _change(
                  'stylePrompt',
                  ModuStrings.text(
                      context, templates[value]!, templates[value]!));
            }
          },
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('mimo-description'),
          controller: _description,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: design
                ? ModuStrings.text(
                    context, '音色描述（必填）', 'Voice description (required)')
                : ModuStrings.text(
                    context, '语音描述 / 朗读风格（可选）', 'Speech style (optional)'),
            errorText: design && _prompt.trim().isEmpty
                ? ModuStrings.text(context, '请填写描述或选择一个预设',
                    'Enter a description or select a template')
                : null,
          ),
          onChanged: (value) => _change('stylePrompt', value),
        ),
        const SizedBox(height: 12),
        Text(ModuStrings.text(
            context, '常用提示词', 'Prompt suggestions (tap to append, then edit)')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final entry in MimoVoicePresets.phrases.entries)
              ActionChip(
                label: Text(ModuStrings.text(context, entry.key, entry.key)),
                onPressed: () {
                  final phrase =
                      ModuStrings.text(context, entry.value, entry.value);
                  if (_prompt.contains(phrase)) return;
                  _change(
                      'stylePrompt',
                      [_prompt.trim(), phrase]
                          .where((text) => text.isNotEmpty)
                          .join('\n'));
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        SettingHelp(
            title: Text(ModuStrings.text(context, "声音设置", "Voice settings")),
            description: Text(ModuStrings.text(
                context,
                "修改描述后点击“保存设置”。朗读时可直接调整语速和音调。",
                "Save your description, then adjust rate and pitch during narration."))),
      ],
    );
  }
}
