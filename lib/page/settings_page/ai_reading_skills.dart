import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/models/user_prompt.dart';
import 'package:anx_reader/providers/user_prompts.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/service/ai/reading_skill_prompt_store.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiReadingSkillsSettings extends ConsumerStatefulWidget {
  const AiReadingSkillsSettings({super.key});

  @override
  ConsumerState<AiReadingSkillsSettings> createState() =>
      _AiReadingSkillsSettingsState();
}

class _AiReadingSkillsSettingsState
    extends ConsumerState<AiReadingSkillsSettings> {
  static const _featurePrompts = <_FeaturePrompt>[
    _FeaturePrompt(
      prompt: AiPrompts.test,
      name: 'AI 配置测试',
      description: '用于检查模型服务是否能正常回答',
      variables: ['language_locale'],
    ),
    _FeaturePrompt(
      prompt: AiPrompts.summaryThePreviousContent,
      name: '回忆前文',
      description: '继续阅读时自动概括之前的内容',
      variables: ['previous_content'],
    ),
    _FeaturePrompt(
      prompt: AiPrompts.translate,
      name: '翻译与词典',
      description: '用于阅读页选词翻译和语境解释',
      variables: ['text', 'to_locale', 'from_locale', 'contextText'],
    ),
    _FeaturePrompt(
      prompt: AiPrompts.fullTextTranslate,
      name: '全文翻译',
      description: '用于阅读页的全文翻译功能',
      variables: ['text', 'to_locale', 'from_locale'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final customSkills = ref.watch(userPromptsProvider);
    return settingsSections(
      sections: [
        SettingsSection(
          title: const Text('内置阅读技能'),
          tiles: [
            CustomSettingsTile(
              child: Material(
                color: Colors.transparent,
                child: Column(
                  children: [
                    _hint(
                      '阅读界面只显示已启用的技能。点击技能可查看和修改提示词。',
                    ),
                    for (final skill in readAnySkills) _builtInSkillTile(skill),
                  ],
                ),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: const Text('自定义技能'),
          tiles: [
            CustomSettingsTile(
              child: Material(
                color: Colors.transparent,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '自定义技能会与内置技能一起出现在阅读 AI 面板中。',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            key: const ValueKey('add-custom-reading-skill'),
                            onPressed: () => _showCustomSkillDialog(),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('新建技能'),
                          ),
                        ],
                      ),
                    ),
                    if (customSkills.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('还没有自定义技能'),
                      )
                    else
                      for (var index = 0; index < customSkills.length; index++)
                        _customSkillTile(
                          customSkills[index],
                          index,
                          customSkills.length,
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: const Text('功能提示词'),
          tiles: [
            CustomSettingsTile(
              child: Material(
                color: Colors.transparent,
                child: Column(
                  children: [
                    _hint('这些提示词由自动回忆、翻译等内置功能使用，不会显示为阅读技能按钮。'),
                    for (final item in _featurePrompts)
                      ListTile(
                        leading: const Icon(Icons.code_outlined),
                        title: Text(item.name),
                        subtitle: Text(item.description),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showFeaturePromptDialog(item),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }

  Widget _builtInSkillTile(ReadAnySkill skill) {
    final enabled = Prefs().isReadAnySkillEnabled(skill.id);
    return ListTile(
      key: ValueKey('reading-skill-${skill.id}'),
      leading: Icon(_skillIcon(skill.id)),
      title: Text(skill.name),
      subtitle: Text(skill.description),
      onTap: () => _showBuiltInSkillDialog(skill),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '查看提示词',
            onPressed: () => _showBuiltInSkillDialog(skill),
            icon: const Icon(Icons.edit_outlined),
          ),
          Switch(
            key: ValueKey('reading-skill-switch-${skill.id}'),
            value: enabled,
            onChanged: (value) {
              Prefs().setReadAnySkillEnabled(skill.id, value);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _customSkillTile(UserPrompt skill, int index, int count) {
    final notifier = ref.read(userPromptsProvider.notifier);
    return ListTile(
      key: ValueKey('custom-reading-skill-${skill.id}'),
      leading: const Icon(Icons.person_outline),
      title: Text(skill.name),
      subtitle: Text(
        skill.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _showCustomSkillDialog(skill: skill),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: skill.enabled,
            onChanged: (_) => notifier.toggleEnabled(skill.id),
          ),
          PopupMenuButton<_CustomSkillAction>(
            tooltip: '更多操作',
            onSelected: (action) {
              switch (action) {
                case _CustomSkillAction.edit:
                  _showCustomSkillDialog(skill: skill);
                  break;
                case _CustomSkillAction.moveUp:
                  notifier.movePrompt(skill.id, true);
                  break;
                case _CustomSkillAction.moveDown:
                  notifier.movePrompt(skill.id, false);
                  break;
                case _CustomSkillAction.delete:
                  _confirmDeleteCustomSkill(skill);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _CustomSkillAction.edit,
                child: Text('编辑提示词'),
              ),
              PopupMenuItem(
                value: _CustomSkillAction.moveUp,
                enabled: index > 0,
                child: const Text('上移'),
              ),
              PopupMenuItem(
                value: _CustomSkillAction.moveDown,
                enabled: index < count - 1,
                child: const Text('下移'),
              ),
              const PopupMenuItem(
                value: _CustomSkillAction.delete,
                child: Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showBuiltInSkillDialog(ReadAnySkill skill) async {
    final controller = TextEditingController(
      text: ReadingSkillPromptStore.promptFor(skill),
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${skill.name}·提示词'),
        content: _promptEditor(controller),
        actions: [
          TextButton(
            onPressed: () {
              ReadingSkillPromptStore.reset(skill);
              controller.text = skill.defaultPrompt.trim();
              setState(() {});
            },
            child: const Text('恢复默认'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final prompt = controller.text.trim();
              if (!_validatePrompt(prompt)) return;
              ReadingSkillPromptStore.save(skill, prompt);
              Navigator.pop(dialogContext);
              setState(() {});
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _showFeaturePromptDialog(_FeaturePrompt item) async {
    final controller =
        TextEditingController(text: Prefs().getAiPrompt(item.prompt));
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${item.name}·提示词'),
        content: _promptEditor(controller, variables: item.variables),
        actions: [
          TextButton(
            onPressed: () {
              Prefs().deleteAiPrompt(item.prompt);
              controller.text = item.prompt.getPrompt().trim();
            },
            child: const Text('恢复默认'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final prompt = controller.text.trim();
              if (!_validatePrompt(prompt)) return;
              Prefs().saveAiPrompt(item.prompt, prompt);
              Navigator.pop(dialogContext);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Widget _promptEditor(
    TextEditingController controller, {
    List<String> variables = const [],
  }) {
    return SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('reading-skill-prompt-editor'),
              controller: controller,
              minLines: 8,
              maxLines: 16,
              decoration: const InputDecoration(
                labelText: '提示词',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (variables.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('可用变量'),
              Wrap(
                spacing: 8,
                children: [
                  for (final variable in variables)
                    ActionChip(
                      label: Text('{{$variable}}'),
                      onPressed: () => _insertVariable(controller, variable),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _insertVariable(TextEditingController controller, String variable) {
    final selection = controller.selection;
    final start = selection.isValid ? selection.start : controller.text.length;
    final end = selection.isValid ? selection.end : controller.text.length;
    final token = '{{$variable}}';
    controller.value = controller.value.copyWith(
      text: controller.text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  Future<void> _showCustomSkillDialog({UserPrompt? skill}) async {
    final nameController = TextEditingController(text: skill?.name ?? '');
    final promptController = TextEditingController(text: skill?.content ?? '');
    var enabled = skill?.enabled ?? true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(skill == null ? '新建自定义技能' : '编辑自定义技能'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const ValueKey('custom-skill-name-editor'),
                    controller: nameController,
                    maxLength: 50,
                    decoration: const InputDecoration(
                      labelText: '技能名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('custom-skill-prompt-editor'),
                    controller: promptController,
                    minLines: 8,
                    maxLines: 16,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      labelText: '提示词',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('在阅读 AI 面板中启用'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final prompt = promptController.text.trim();
                if (name.isEmpty || prompt.isEmpty) {
                  _showRequiredFieldsMessage();
                  return;
                }
                final notifier = ref.read(userPromptsProvider.notifier);
                if (skill == null) {
                  notifier.addPrompt(name: name, content: prompt);
                  if (!enabled) {
                    final added = ref.read(userPromptsProvider).last;
                    notifier.toggleEnabled(added.id);
                  }
                } else {
                  notifier.updatePrompt(
                    skill.copyWith(
                      name: name,
                      content: prompt,
                      enabled: enabled,
                    ),
                  );
                }
                Navigator.pop(dialogContext);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    promptController.dispose();
  }

  Future<void> _confirmDeleteCustomSkill(UserPrompt skill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除自定义技能'),
        content: Text('确定删除“${skill.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(userPromptsProvider.notifier).deletePrompt(skill.id);
    }
  }

  bool _validatePrompt(String prompt) {
    if (prompt.isNotEmpty) return true;
    _showRequiredFieldsMessage();
    return false;
  }

  void _showRequiredFieldsMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('技能名称和提示词不能为空')),
    );
  }

  IconData _skillIcon(String skillId) {
    return switch (skillId) {
      'smart_summary' => Icons.summarize_outlined,
      'book_summary' => Icons.menu_book_rounded,
      'concept_explainer' => Icons.lightbulb_outline,
      'argument_analyzer' => Icons.account_tree_outlined,
      'character_tracker' => Icons.groups_outlined,
      'quote_collector' => Icons.format_quote_outlined,
      'reading_guide' => Icons.explore_outlined,
      'smart_translator' => Icons.translate_outlined,
      'vocabulary_helper' => Icons.spellcheck_outlined,
      'mindmap' => Icons.hub_outlined,
      _ => Icons.extension_outlined,
    };
  }
}

class _FeaturePrompt {
  const _FeaturePrompt({
    required this.prompt,
    required this.name,
    required this.description,
    required this.variables,
  });

  final AiPrompts prompt;
  final String name;
  final String description;
  final List<String> variables;
}

enum _CustomSkillAction { edit, moveUp, moveDown, delete }
