import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/widgets/reading_page/reader_menu_appearance.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/unified_query.dart';
import 'package:anx_reader/widgets/ai/skill_template_draft_tile.dart';
import 'package:anx_reader/page/settings_page/dictionaries.dart';
import 'package:anx_reader/page/settings_page/translate.dart';
import 'package:anx_reader/page/settings_page/selection_search.dart';
import 'package:anx_reader/page/settings_page/selection_toolbar.dart';
import 'package:anx_reader/page/settings_page/ai_reading_skills.dart';
import 'package:flutter/material.dart';

class UnifiedQuerySettings extends StatefulWidget {
  const UnifiedQuerySettings({super.key, this.section, this.draftScreen});
  final QuerySection? section;
  final String? draftScreen;
  @override
  State<UnifiedQuerySettings> createState() => _UnifiedQuerySettingsState();
}

class _UnifiedQuerySettingsState extends State<UnifiedQuerySettings> {
  late final prefs = UnifiedQueryPreferences.load(Prefs().prefs);
  late final knowledge = TextEditingController(text: prefs.knowledgePrompt);
  late final classical = TextEditingController(text: prefs.classicalPrompt);
  Future<void> writes = Future.value();
  String? error;
  String t(String zh, String en) => ModuStrings.text(context, zh, en);
  @override
  void dispose() {
    knowledge.dispose();
    classical.dispose();
    super.dispose();
  }

  Future<void> save() async {
    prefs.knowledgePrompt = knowledge.text.trim();
    prefs.classicalPrompt = classical.text.trim();
    writes = writes.then((_) async {
      await prefs.save(Prefs().prefs);
      if (mounted) setState(() => error = null);
    }).catchError((Object e) {
      if (mounted) {
        setState(() {
          error = t('保存失败，请重试', 'Save failed. Please retry.');
        });
      }
    });
    await writes;
  }

  Widget destination(String title, Widget body) => ListTile(
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) =>
                  Scaffold(appBar: AppBar(title: Text(title)), body: body))));

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    return Scaffold(
      appBar: AppBar(
          title: Text(section == null
              ? t('综合查询设置', 'Lookup settings')
              : t(section.zh, section.en))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (section == null) ...[
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(t('拖动调整汇总顺序，调整后使用自定义排序。',
                  'Drag to reorder overview results; reordering switches to custom order.'))),
          ReorderableListView.builder(
              key: const ValueKey('query-section-order'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: prefs.order.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  prefs.order.insert(newIndex, prefs.order.removeAt(oldIndex));
                  prefs.smartOrder = false;
                });
                save();
              },
              itemBuilder: (context, index) {
                final s = prefs.order[index];
                return Row(key: ValueKey('query-order-${s.name}'), children: [
                  ReorderableDragStartListener(
                      key: ValueKey('query-drag-${s.name}'),
                      index: index,
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(Icons.drag_indicator,
                              semanticLabel: t('拖动排序', 'Drag to reorder')))),
                  Expanded(
                      child: CheckboxListTile(
                          key: ValueKey('query-include-${s.name}'),
                          title: Text(t(s.zh, s.en)),
                          value: prefs.included.contains(s),
                          onChanged: (v) {
                            setState(() {
                              v == true
                                  ? prefs.included.add(s)
                                  : prefs.included.remove(s);
                            });
                            save();
                          })),
                ]);
              }),
          SwitchListTile(
              key: const ValueKey('query-smart-order'),
              title: SettingHelp(
                  title: Text(t('按查询文本智能排序', 'Order by query text')),
                  description: Text(t("按相关程度排序；关闭后使用自定义顺序。",
                      "Sort by relevance, or turn off to use your own order."))),
              value: prefs.smartOrder,
              onChanged: (v) {
                setState(() => prefs.smartOrder = v);
                save();
              }),
          ListTile(
              title: Text(t('独立划词按钮开关', 'Standalone selection actions')),
              subtitle: Text(t('字典、翻译、AI 知识等入口仍可单独开启。',
                  'Dictionary, translation and AI knowledge shortcuts remain available.')),
              onTap: () => showSelectionToolbarSettings(context,
                  readerAppearance: ReaderMenuAppearance.translucent(context))),
        ],
        if (section == null ||
            section == QuerySection.knowledge ||
            section == QuerySection.classical ||
            section == QuerySection.translation)
          SwitchListTile(
              title: Text(t('结合选文上下文', 'Include selection context')),
              subtitle: Text(t('仅 AI 和翻译使用；百科和联网搜索不发送上下文。',
                  'For AI and translation only; never sent to encyclopedia or web search.')),
              value: prefs.useContext,
              onChanged: (v) {
                setState(() => prefs.useContext = v);
                save();
              }),
        if (section == null ||
            section == QuerySection.knowledge ||
            section == QuerySection.classical) ...[
          for (final s in [QuerySection.knowledge, QuerySection.classical])
            if (section == null || section == s)
              SkillTemplateDraftTile(
                  screen: widget.draftScreen ?? 'lookup.${s.name}',
                  legacyDefault: prefs.manualAi,
                  title:
                      '${t(s.zh, s.en)} · ${t('编辑后发送', 'Edit before sending')}'),
          if (section == null || section == QuerySection.knowledge)
            TextField(
                controller: knowledge,
                onChanged: (_) => save(),
                maxLines: 3,
                maxLength: 8000,
                decoration: InputDecoration(
                    labelText: t('AI 知识提示词（留空使用原模板）',
                        'AI knowledge prompt (empty: existing template)'))),
          if (section == null || section == QuerySection.classical)
            TextField(
                controller: classical,
                onChanged: (_) => save(),
                maxLines: 3,
                maxLength: 8000,
                decoration: InputDecoration(
                    labelText: t('文言文翻译提示词（留空使用原模板）',
                        'Classical translation prompt (empty: existing template)'))),
        ],
        if (section == null || section == QuerySection.encyclopedia) ...[
          SwitchListTile(
              title: Text(t('维基百科摘要', 'Wikipedia excerpts')),
              value: prefs.wikipedia,
              onChanged: (v) {
                setState(() => prefs.wikipedia = v);
                save();
              }),
          SwitchListTile(
              title: Text(t('百度百科原站入口', 'Baidu Baike website link')),
              value: prefs.baiduLink,
              onChanged: (v) {
                setState(() => prefs.baiduLink = v);
                save();
              }),
        ],
        if (section == null || section == QuerySection.dictionary)
          destination(t('字典与查询来源', 'Dictionaries and sources'),
              const DictionarySettings()),
        if (section == null || section == QuerySection.translation)
          destination(
              t('翻译服务设置', 'Translation settings'), const TranslateSetting()),
        if (section == null || section == QuerySection.web)
          destination(t('联网搜索引擎', 'Web search engines'),
              const SelectionSearchSettings()),
        if (section == null || section == QuerySection.book)
          destination(t('本书 AI 阅读技能', 'Book AI reading skills'),
              const AiReadingSkillsSettings(draftScreen: 'lookup.book')),
        if (error != null)
          Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 16),
        if (error != null)
          TextButton(onPressed: save, child: Text(t('重试', 'Retry'))),
        const SizedBox(height: 32),
      ]),
    );
  }
}
