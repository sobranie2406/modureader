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
        .where((entry) => entry.value == _prompt)
        .map((entry) => entry.key)
        .firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Material(
        type: MaterialType.transparency,
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(t('启用语音提示词', 'Enable speech instructions')),
          value: enabled,
          onChanged: legacy
              ? null
              : (value) => _change('instructionsEnabled', value.toString()),
          subtitle: Text(legacy
              ? t('tts-1 / tts-1-hd 不支持提示词；保留描述但不发送。',
                  'tts-1 / tts-1-hd do not support instructions. Your description is kept but not sent.')
              : t('第三方接口若不支持 instructions，可关闭此项；已写的描述会保留。',
                  'Turn off if your provider does not support instructions. Your description will be retained.')),
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey('openai-template-$selected'),
        initialValue: selected ?? '',
        isExpanded: true,
        decoration: InputDecoration(
          labelText: t('描述预设', 'Description template'),
          helperText: t('默读提供的可编辑模板，选择后替换下方描述，不改变 Voice 音色。',
              'Editable Modu templates replace the description without changing Voice.'),
          helperMaxLines: 3,
        ),
        items: [
          DropdownMenuItem(
              value: '',
              child: Text(t('自定义（保留当前描述）', 'Custom (keep current text)'))),
          for (final name in OpenAiVoicePresets.templates.keys)
            DropdownMenuItem(value: name, child: Text(name)),
        ],
        onChanged: (value) {
          final prompt = OpenAiVoicePresets.templates[value];
          if (prompt != null) _change('instructions', prompt);
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
          labelText:
              t('语音描述 / 朗读风格（可选）', 'Speech description / style (optional)'),
          helperText: t('描述音色质感、语气、情绪、语速或停顿。留空使用默认风格，提示词不会拼入朗读正文。',
              'Describe timbre, tone, emotion, pace or pauses. Leave empty for the default style. Instructions are not added to the spoken text.'),
          helperMaxLines: 4,
        ),
        onChanged: (value) => _change('instructions', value),
      ),
      Align(
          alignment: Alignment.centerRight,
          child: TextButton(
              onPressed:
                  _prompt.isEmpty ? null : () => _change('instructions', ''),
              child: Text(t('清空描述', 'Clear description')))),
      Text(t('常用提示词（点击追加，可继续编辑）',
          'Prompt suggestions (tap to append, then edit)')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final entry in OpenAiVoicePresets.phrases.entries)
          ActionChip(
              label: Text(entry.key),
              onPressed: () {
                if (_prompt.contains(entry.value)) return;
                _change(
                    'instructions',
                    [_prompt.trim(), entry.value]
                        .where((s) => s.isNotEmpty)
                        .join('\n'));
              }),
      ]),
      const SizedBox(height: 8),
      Text(t(
          '同段相邻句合成，高亮和前后跳转按小段，长段自动拆分。启用提示词时自动附加匀速听书要求（留空描述也会发送）；实际效果取决于模型。关闭提示词或使用 tts-1 / tts-1-hd 时不发送。',
          'Adjacent sentences are synthesized as passages, with passage highlighting and navigation; long paragraphs are split. When instructions are enabled, steady narration is requested even with an empty description. Results depend on the model. No instructions are sent when disabled or for tts-1 / tts-1-hd.')),
      Text(t(
          '效果取决于服务商和模型，提示词不能代替 Voice 音色或克隆声音。使用提示词控制语速、音高时，请把播放器语速与音调设为 1.0，避免冲突。点击“保存设置”后生效。',
          'Results depend on the provider and model; prompts do not replace Voice or clone a voice. Set the player rate and pitch to 1.0 when controlling them with text to avoid conflicts. Use Save settings to apply.')),
    ]);
  }
}
