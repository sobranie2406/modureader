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

  String _text(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

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
        .where((entry) => entry.value == _prompt)
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
          value: model,
          isExpanded: true,
          decoration: InputDecoration(labelText: _text('语音模式', 'Speech mode')),
          items: [
            DropdownMenuItem(
                value: models[0],
                child: Text(_text('官方预置音色', 'Preset voices'))),
            DropdownMenuItem(
                value: models[1], child: Text(_text('文字设计音色', 'Voice design'))),
            if (!models.contains(model))
              DropdownMenuItem(
                  value: model,
                  child: Text(_text(
                      '旧模型不受支持，请重新选择', 'Unsupported model — select another'))),
          ],
          onChanged: (value) {
            if (value != null) _change('model', value);
          },
        ),
        const SizedBox(height: 12),
        if (!design)
          DropdownButtonFormField<String>(
            key: const ValueKey('mimo-voice'),
            value: voice,
            isExpanded: true,
            decoration:
                InputDecoration(labelText: _text('预置音色', 'Preset voice')),
            items: [
              for (final item in voices)
                DropdownMenuItem(
                  value: item.shortName,
                  child: Text(item.shortName == 'mimo_default'
                      ? _text('默认音色（由服务地区决定）', 'Default voice (regional)')
                      : '${item.name} · ${item.locale == 'zh-CN' ? _text('中文', 'Chinese') : _text('英文', 'English')}'),
                ),
              if (!voices.any((item) => item.shortName == voice))
                DropdownMenuItem(
                    value: voice,
                    child: Text(_text('旧音色不受支持，请重新选择',
                        'Unsupported voice — select another'))),
            ],
            onChanged: (value) {
              if (value != null) _change('voice', value);
            },
          )
        else
          Text(_text('此模式通过描述设计声音，不使用预置音色。切回时保留原音色选择。',
              'Design a voice with text. The preset voice is retained for switching back, but is not sent in this mode.')),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey('mimo-template-$design-$selected'),
          value: selected ?? '',
          isExpanded: true,
          decoration: InputDecoration(
            labelText: _text('描述预设', 'Description template'),
            helperText: _text('默读提供的可编辑模板；选择后替换下方描述。',
                'Editable Modu templates. Selecting one replaces the description below.'),
            helperMaxLines: 3,
          ),
          items: [
            DropdownMenuItem(
                value: '',
                child:
                    Text(_text('自定义（保留当前描述）', 'Custom (keep current text)'))),
            for (final name in templates.keys)
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: (value) {
            if (templates.containsKey(value)) {
              _change('stylePrompt', templates[value]!);
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
                ? _text('音色描述（必填）', 'Voice description (required)')
                : _text('语音描述 / 朗读风格（可选）', 'Speech style (optional)'),
            helperText: design
                ? _text('建议 1–4 句，描述性别、年龄感、音色、语气和节奏，避免相互矛盾。',
                    'Use 1–4 sentences about gender, age, timbre, tone and pace. Avoid conflicting descriptions.')
                : _text('描述语气、情绪和节奏；留空使用音色默认风格。',
                    'Describe tone, emotion and pace, or leave empty for the default style.'),
            helperMaxLines: 4,
            errorText: design && _prompt.trim().isEmpty
                ? _text(
                    '请填写描述或选择一个预设', 'Enter a description or select a template')
                : null,
          ),
          onChanged: (value) => _change('stylePrompt', value),
        ),
        const SizedBox(height: 12),
        Text(_text('常用提示词（点击追加，可继续编辑）',
            'Prompt suggestions (tap to append, then edit)')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final entry in MimoVoicePresets.phrases.entries)
              ActionChip(
                label: Text(entry.key),
                onPressed: () {
                  if (_prompt.contains(entry.value)) return;
                  _change(
                      'stylePrompt',
                      [_prompt.trim(), entry.value]
                          .where((text) => text.isNotEmpty)
                          .join('\n'));
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(_text('描述不会作为正文朗读。若描述了语速或音高，建议把播放器对应滑块保持默认，避免指令冲突。修改后点击“保存设置”生效。',
            'Descriptions are instructions, not spoken text. Keep rate/pitch sliders at default when controlling them here to avoid conflicts. Use Save settings to apply.')),
      ],
    );
  }
}
