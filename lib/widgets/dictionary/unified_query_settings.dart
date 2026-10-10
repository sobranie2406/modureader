import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/unified_query.dart';
import 'package:anx_reader/page/settings_page/dictionaries.dart';
import 'package:anx_reader/page/settings_page/translate.dart';
import 'package:anx_reader/page/settings_page/selection_search.dart';
import 'package:anx_reader/page/settings_page/selection_toolbar.dart';
import 'package:anx_reader/page/settings_page/ai_reading_skills.dart';
import 'package:flutter/material.dart';

class UnifiedQuerySettings extends StatefulWidget {
  const UnifiedQuerySettings({super.key, this.section});
  final QuerySection? section;
  @override
  State<UnifiedQuerySettings> createState() => _UnifiedQuerySettingsState();
}

class _UnifiedQuerySettingsState extends State<UnifiedQuerySettings> {
  late final prefs = UnifiedQueryPreferences.load(Prefs().prefs);
  late final knowledge = TextEditingController(text: prefs.knowledgePrompt);
  late final classical = TextEditingController(text: prefs.classicalPrompt);
  bool saving = false;
  String? error;
  String t(String zh, String en) => ModuStrings.text(context, zh, en);
  @override
  void dispose() {
    knowledge.dispose();
    classical.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    prefs.knowledgePrompt = knowledge.text.trim();
    prefs.classicalPrompt = classical.text.trim();
    try {
      await prefs.save(Prefs().prefs);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = t('保存失败，请重试', 'Save failed. Please retry.');
        });
      }
    }
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
          Text(t('选择综合页汇总的内容。其他标签仍可单独打开；关闭汇总不会删除字典或服务设置。',
              'Choose results for the overview. Other tabs remain available; disabling a summary does not delete sources.')),
          for (final s in QuerySection.comprehensive)
            CheckboxListTile(
                key: ValueKey('query-include-${s.name}'),
                title: Text(t(s.zh, s.en)),
                value: prefs.included.contains(s),
                onChanged: (v) => setState(() {
                      v == true
                          ? prefs.included.add(s)
                          : prefs.included.remove(s);
                    })),
          SwitchListTile(
              title: Text(t('按查询文本智能排序', 'Order by query text')),
              subtitle: Text(t('在本机按词语、短语或长句排序，不调用 AI。',
                  'Local word/phrase/sentence rules; no AI request.')),
              value: prefs.smartOrder,
              onChanged: (v) => setState(() => prefs.smartOrder = v)),
          ListTile(
              title: Text(t('独立划词按钮开关', 'Standalone selection actions')),
              subtitle: Text(t('字典、翻译、AI 知识等入口仍可单独开启。',
                  'Dictionary, translation and AI knowledge shortcuts remain available.')),
              onTap: () => showSelectionToolbarSettings(context)),
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
              onChanged: (v) => setState(() => prefs.useContext = v)),
        if (section == null ||
            section == QuerySection.knowledge ||
            section == QuerySection.classical) ...[
          SwitchListTile(
              key: const ValueKey('query-manual-ai'),
              title:
                  Text(t('AI 提问先编辑，点击发送', 'Edit AI questions before sending')),
              subtitle: Text(t('关闭后首次打开 AI 知识／文言文翻译即发送，可能产生服务费用。',
                  'When off, opening AI knowledge/classical translation sends immediately and may incur provider charges.')),
              value: prefs.manualAi,
              onChanged: (v) => setState(() => prefs.manualAi = v)),
          if (section == null || section == QuerySection.knowledge)
            TextField(
                controller: knowledge,
                maxLines: 3,
                maxLength: 8000,
                decoration: InputDecoration(
                    labelText: t('AI 知识提示词（留空使用原模板）',
                        'AI knowledge prompt (empty: existing template)'))),
          if (section == null || section == QuerySection.classical)
            TextField(
                controller: classical,
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
              onChanged: (v) => setState(() => prefs.wikipedia = v)),
          SwitchListTile(
              title: Text(t('百度百科原站入口', 'Baidu Baike website link')),
              value: prefs.baiduLink,
              onChanged: (v) => setState(() => prefs.baiduLink = v)),
          Text(t('开启百科后，进入综合查询即自动查询，仅发送查询词。百度百科通过原站阅读，不抓取或绕过验证。',
              'Enabled encyclopedia sources are queried automatically when opening Look up; only the query is sent. Baidu opens the original website.')),
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
              const AiReadingSkillsSettings()),
        if (error != null)
          Text(error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: saving ? null : save, child: Text(t('保存', 'Save'))),
        const SizedBox(height: 32),
      ]),
    );
  }
}
