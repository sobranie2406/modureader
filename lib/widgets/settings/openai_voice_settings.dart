import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/tts/openai_voice_presets.dart';
import 'package:flutter/material.dart';

/// Shares the connection form's draft; only Save settings persists it.
class OpenAiVoiceSettings extends StatefulWidget {
  const OpenAiVoiceSettings(
      {super.key, required this.config, required this.onChanged});
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<OpenAiVoiceSettings> createState() => _OpenAiVoiceSettingsState();
}

class _OpenAiVoiceSettingsState extends State<OpenAiVoiceSettings> {
  late final _description = TextEditingController(text: _prompt);
  String get _prompt => widget.config['instructions']?.toString() ?? '';
  String t(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  void didUpdateWidget(covariant OpenAiVoiceSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_description.text != _prompt) {
      _description.value = TextEditingValue(
          text: _prompt,
          selection: TextSelection.collapsed(offset: _prompt.length));
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
    final legacy = OpenAiVoicePresets.isLegacyModel(
        widget.config['model']?.toString() ?? '');
    final enabled = OpenAiVoicePresets.sendsInstructions(widget.config);
    final selected = OpenAiVoicePresets.templates.entries
        .where((entry) => ModuStrings.isBundledText(entry.value, _prompt))
        .map((entry) => entry.key)
        .firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Material(
        type: MaterialType.transparency,
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: SettingHelp(
              title: Text(ModuStrings.text(
                  context, '启用语音提示词', 'Enable speech instructions')),
              description: Text(legacy
                  ? ModuStrings.text(
                      context,
                      'tts-1 / tts-1-hd 不支持提示词；保留描述但不发送。',
                      'tts-1 / tts-1-hd do not support instructions. Your description is kept but not sent.')
                  : ModuStrings.text(context, "接口支持 instructions 时，可用提示词调整声音。",
                      "Use voice instructions if your service supports them."))),
          value: enabled,
          onChanged: legacy
              ? null
              : (value) => _change('instructionsEnabled', value.toString()),
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey('openai-template-$selected'),
        initialValue: selected ?? '',
        isExpanded: true,
        decoration: InputDecoration(
          labelText: ModuStrings.text(context, '描述预设', 'Description template'),
        ),
        items: [
          DropdownMenuItem(
              value: '',
              child: Text(ModuStrings.text(
                  context, '自定义（保留当前描述）', 'Custom (keep current text)'))),
          for (final name in OpenAiVoicePresets.templates.keys)
            DropdownMenuItem(
                value: name,
                child: Text(ModuStrings.text(context, name, name))),
        ],
        onChanged: (value) {
          final prompt = OpenAiVoicePresets.templates[value];
          if (prompt != null) {
            _change('instructions', ModuStrings.text(context, prompt, prompt));
          }
        },
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('openai-description'),
        controller: _description,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: ModuStrings.text(context, '语音描述 / 朗读风格（可选）',
              'Speech description / style (optional)'),
        ),
        onChanged: (value) => _change('instructions', value),
      ),
      Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed:
                  _prompt.isEmpty ? null : () => _change('instructions', ''),
              child: Text(
                  ModuStrings.text(context, '清空描述', 'Clear description')))),
      Text(ModuStrings.text(
          context, '常用提示词', 'Prompt suggestions (tap to append, then edit)')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final entry in OpenAiVoicePresets.phrases.entries)
          ActionChip(
              label: Text(ModuStrings.text(context, entry.key, entry.key)),
              onPressed: () {
                final phrase =
                    ModuStrings.text(context, entry.value, entry.value);
                if (_prompt.contains(phrase)) return;
                _change(
                    'instructions',
                    [_prompt.trim(), phrase]
                        .where((s) => s.isNotEmpty)
                        .join('\n'));
              }),
      ]),
      const SizedBox(height: 8),
      SettingHelp(
          title: Text(ModuStrings.text(context, "声音设置", "Voice settings")),
          description: Text(ModuStrings.text(
              context,
              "修改描述后点击“保存设置”。用描述控制语速和音高时，将播放器倍率设为 1.0。",
              "Save settings after editing. Set playback rate and pitch to 1.0 when controlling them through instructions."))),
    ]);
  }
}
