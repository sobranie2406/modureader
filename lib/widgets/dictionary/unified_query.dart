import 'dart:async';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/models/unified_query.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/service/ai/dictionary_web_search.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:anx_reader/widgets/ai/reading_skill_chips.dart';
import 'package:anx_reader/widgets/context_menu/translation_menu.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_lookup.dart';
import 'package:anx_reader/widgets/dictionary/unified_query_settings.dart';
import 'package:anx_reader/widgets/reading_page/selection_search_browser.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

class UnifiedQuery extends StatefulWidget {
  const UnifiedQuery(
      {super.key, required this.text, this.contextText, this.panelBuilder});
  final String text;
  final String? contextText;
  // Allows layout/lifecycle regression tests without contacting real services.
  final Widget Function(QuerySection, String)? panelBuilder;
  @override
  State<UnifiedQuery> createState() => _UnifiedQueryState();
}

class _UnifiedQueryState extends State<UnifiedQuery> {
  late final input = TextEditingController(text: widget.text.trim());
  late String query = widget.text.trim();
  late var prefs = UnifiedQueryPreferences.load(Prefs().prefs);
  QuerySection? tab;
  final panels = <QuerySection, Widget>{};
  int revision = 0;
  String t(String zh, String en) => ModuStrings.text(context, zh, en);
  String label(QuerySection section) => t(section.zh, section.en);
  String? get sourceContext => prefs.useContext && query == widget.text.trim()
      ? widget.contextText
      : null;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void search() {
    final next = input.text.trim();
    if (next.isEmpty) return;
    setState(() {
      query = next;
      revision++;
      panels.clear();
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> settings([QuerySection? section]) async {
    await Navigator.push(
        context,
        MaterialPageRoute<bool>(
            builder: (_) => UnifiedQuerySettings(section: section)));
    if (!mounted) return;
    // Preserve ongoing chat and unsent drafts. New prompt/context/auto-send
    // preferences apply to the next query, not an already composed question.
    setState(() {
      prefs = UnifiedQueryPreferences.load(Prefs().prefs);
      for (final s in [
        QuerySection.dictionary,
        QuerySection.translation,
        QuerySection.encyclopedia,
        QuerySection.web
      ]) {
        if (section == null || section == s) panels.remove(s);
      }
    });
  }

  SelectionToolbarItem template(String id) =>
      Prefs().selectionToolbar.items.where((i) => i.id == id).firstOrNull ??
      SelectionToolbarConfig.templateItems.singleWhere((i) => i.id == id);

  Widget panel(QuerySection section) {
    if (widget.panelBuilder != null) {
      return widget.panelBuilder!(section, query);
    }
    switch (section) {
      case QuerySection.dictionary:
        return DictionaryLookup(word: query, embedded: true);
      case QuerySection.encyclopedia:
        return _Encyclopedia(
            query: query, wikipedia: prefs.wikipedia, baidu: prefs.baiduLink);
      case QuerySection.translation:
        return TranslationMenu(
            content: query, contextText: sourceContext, embedded: true);
      case QuerySection.web:
        return _StartLookup(
            label: t('联网搜索', 'Search online'),
            notice: t('仅将查询词发送给所选搜索引擎。',
                'Sends only the query to the selected search engine.'),
            builder: () => SelectionSearchBrowser(text: query));
      case QuerySection.knowledge:
      case QuerySection.classical:
      case QuerySection.book:
        if (!EnvVar.enableAIFeature) {
          return Center(
              child:
                  Text(t('当前版本未启用 AI。', 'AI is unavailable in this edition.')));
        }
        final book = section == QuerySection.book;
        final item = template(section == QuerySection.classical
            ? 'custom-preset-classical-chinese'
            : 'custom-preset-dictionary');
        final override = section == QuerySection.classical
            ? prefs.classicalPrompt
            : prefs.knowledgePrompt;
        final command =
            override.isEmpty ? item : item.copyWith(prompt: override);
        final prompt = command.promptForSelection(query,
            locale: Localizations.localeOf(context));
        // Each tab owns its conversation; switching tabs never clears another
        // chat or mixes classical translation into the reader's existing AI.
        return ProviderScope(
            overrides: [
              aiChatProvider(AiChatScope.reader).overrideWith(AiChat.new)
            ],
            child: AiChatStream(
                scope: AiChatScope.reader,
                title: label(section),
                embedded: true,
                inlineResults: section == QuerySection.knowledge,
                showSkillControls: section != QuerySection.classical,
                initialDraftOnly: prefs.manualAi,
                initialMessage: book
                    ? query
                    : (override.isNotEmpty && !override.contains('{selection}')
                        ? '$prompt\n\n${t('选文', 'Selection')}: $query'
                        : prompt),
                initialSourceText: query,
                initialSourceContext: sourceContext,
                initialSelectionRequest: !book,
                initialSkillId: book ? null : command.skillId,
                newConversation: true,
                sendImmediate: !book && !prefs.manualAi,
                quickPromptChips: book
                    ? configuredReadingSkillChips(
                        Localizations.localeOf(context))
                    : const [],
                quickPromptChipsBuilder: book
                    ? () => configuredReadingSkillChips(
                        Localizations.localeOf(context))
                    : null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final body =
        theme.textTheme.bodyMedium!.copyWith(fontSize: 15, height: 1.65);
    return Theme(
        data: theme.copyWith(
            textTheme: theme.textTheme.copyWith(
                bodyMedium: body,
                bodyLarge: body,
                bodySmall:
                    body.copyWith(fontSize: 12, color: colors.onSurfaceVariant),
                titleSmall:
                    body.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
                titleMedium:
                    body.copyWith(fontSize: 19, fontWeight: FontWeight.w500),
                labelLarge:
                    body.copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
            iconTheme: theme.iconTheme.copyWith(size: 20),
            cardTheme: CardThemeData(
                elevation: 0,
                color: colors.surface,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                    side: BorderSide(color: colors.outlineVariant))),
            textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)))),
        child: DefaultTextStyle(
            style: body, child: Builder(builder: _buildContent)));
  }

  Widget _buildContent(BuildContext context) {
    final visible = tab == null ? queryOrder(query, prefs) : [tab!];
    for (final s in visible) {
      panels.putIfAbsent(
          s, () => KeyedSubtree(key: UniqueKey(), child: panel(s)));
    }
    final order = [
      ...visible,
      ...QuerySection.values.where((s) => !visible.contains(s))
    ];
    return SafeArea(
        top: false,
        child: Column(children: [
          Row(children: [
            const SizedBox(width: 16),
            const Icon(Icons.manage_search),
            const SizedBox(width: 8),
            Expanded(
                child: Text(t('综合查询', 'Look up'),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontSize: 22, fontWeight: FontWeight.w500))),
            IconButton(
                key: const ValueKey('query-settings'),
                tooltip: t('查询设置', 'Lookup settings'),
                onPressed: () => settings(),
                icon: const Icon(Icons.settings_outlined)),
            IconButton(
                tooltip: t('关闭', 'Close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close)),
          ]),
          if (tab != QuerySection.book)
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: TextField(
                    key: const ValueKey('unified-query-input'),
                    controller: input,
                    style: const TextStyle(fontSize: 18, height: 1.4),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => search(),
                    decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(13)),
                        labelText: t('查询内容', 'Query'),
                        suffixIcon: IconButton(
                            onPressed: search,
                            icon: const Icon(Icons.search))))),
          if (sourceContext?.trim().isNotEmpty == true &&
              tab != QuerySection.book)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(sourceContext!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall))),
          SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                for (final s in [null, ...QuerySection.values])
                  Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                          key: ValueKey('query-tab-${s?.name ?? 'all'}'),
                          showCheckmark: false,
                          side: BorderSide.none,
                          backgroundColor: Colors.transparent,
                          selectedColor: Theme.of(context).colorScheme.primary,
                          shape: const StadiumBorder(),
                          labelStyle: TextStyle(
                              fontSize: 14,
                              color: tab == s
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                          label:
                              Text(s == null ? t('综合', 'Overview') : label(s)),
                          selected: tab == s,
                          onSelected: (_) => setState(() {
                                tab = s;
                                FocusScope.of(context).unfocus();
                              }))),
              ])),
          if (tab == null)
            Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                        prefs.smartOrder
                            ? t('本机智能排序 · 各来源独立显示',
                                'Local ordering · separate sources')
                            : t('按栏目顺序显示', 'Category order'),
                        style: Theme.of(context).textTheme.bodySmall))),
          Expanded(child: LayoutBuilder(builder: (context, viewport) {
            if (visible.isEmpty) {
              return Center(
                  child: Text(t('尚未选择综合查询内容，请在设置中勾选。',
                      'Choose overview sources in settings.')));
            }
            return SingleChildScrollView(
                key: ValueKey('query-scroll-$revision'),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(children: [
                  for (final s in order)
                    if (panels.containsKey(s))
                      Offstage(
                          key: ValueKey('query-panel-${s.name}-$revision'),
                          offstage: !visible.contains(s),
                          child: TickerMode(
                              enabled: visible.contains(s),
                              child: SizedBox(
                                  height: QuerySection.comprehensive.contains(s)
                                      ? null
                                      : viewport.maxHeight,
                                  child: Card(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      clipBehavior: Clip.hardEdge,
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            SizedBox(
                                                height: 48,
                                                child: Row(children: [
                                                  const SizedBox(width: 12),
                                                  Icon(
                                                      switch (s) {
                                                        QuerySection
                                                              .dictionary =>
                                                          Icons
                                                              .menu_book_outlined,
                                                        QuerySection
                                                              .encyclopedia =>
                                                          Icons
                                                              .local_library_outlined,
                                                        QuerySection
                                                              .translation =>
                                                          Icons.translate,
                                                        QuerySection
                                                              .knowledge =>
                                                          Icons
                                                              .auto_awesome_outlined,
                                                        QuerySection
                                                              .classical =>
                                                          Icons.history_edu,
                                                        QuerySection.book => Icons
                                                            .chat_bubble_outline,
                                                        QuerySection.web =>
                                                          Icons.public,
                                                      },
                                                      size: 18,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                      child: Text(label(s),
                                                          style:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .titleSmall)),
                                                  if (tab == null)
                                                    IconButton(
                                                        tooltip:
                                                            t('展开', 'Expand'),
                                                        icon: const Icon(
                                                            Icons.open_in_full,
                                                            size: 18),
                                                        onPressed: () =>
                                                            setState(
                                                                () => tab = s)),
                                                  IconButton(
                                                      tooltip: t('${s.zh}设置',
                                                          '${s.en} settings'),
                                                      icon: const Icon(
                                                          Icons
                                                              .settings_outlined,
                                                          size: 18),
                                                      onPressed: () =>
                                                          settings(s)),
                                                ])),
                                            if (QuerySection.comprehensive
                                                .contains(s))
                                              panels[s]!
                                            else
                                              Expanded(child: panels[s]!),
                                          ]))))),
                ]));
          })),
        ]));
  }
}

class _StartLookup extends StatefulWidget {
  const _StartLookup(
      {required this.label, required this.notice, required this.builder});
  final String label, notice;
  final Widget Function() builder;
  @override
  State<_StartLookup> createState() => _StartLookupState();
}

class _StartLookupState extends State<_StartLookup> {
  Widget? content;
  @override
  Widget build(BuildContext context) =>
      content ??
      Center(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(widget.notice),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => setState(() => content = widget.builder()),
                    child: Text(widget.label)),
              ])));
}

class _Encyclopedia extends StatefulWidget {
  const _Encyclopedia(
      {required this.query, required this.wikipedia, required this.baidu});
  final String query;
  final bool wikipedia, baidu;
  @override
  State<_Encyclopedia> createState() => _EncyclopediaState();
}

class _EncyclopediaState extends State<_Encyclopedia> {
  final cancel = Completer<void>();
  DictionarySearchResult? result;
  bool busy = false;
  String t(String zh, String en) => ModuStrings.text(context, zh, en);
  @override
  void initState() {
    super.initState();
    if (widget.wikipedia) search();
  }

  @override
  void dispose() {
    cancel.complete();
    super.dispose();
  }

  Future<void> search() async {
    setState(() => busy = true);
    final next = await DictionaryWebSearch().search(widget.query,
        cancelled: cancel.future, sites: const {'wikipedia'});
    if (mounted) {
      setState(() {
        result = next;
        busy = false;
      });
    }
  }

  Future<void> open(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(t('无法打开链接', 'Could not open link'))));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.wikipedia) ...[
              Text(t('向维基百科自动查询，仅发送查询词，不发送上下文。',
                  'Automatically queries Wikipedia with the query only, never book context.')),
              TextButton(
                  onPressed: busy ? null : search,
                  child: Text(busy
                      ? t('查询中…', 'Looking up…')
                      : t('查询百科', 'Look up encyclopedia'))),
            ],
            if (result != null && result!.hits.isEmpty)
              Text(result!.hasFailures
                  ? t('百科暂时不可用，请重试。', 'Encyclopedia unavailable. Please retry.')
                  : t('未找到匹配词条。', 'No matching entry.')),
            for (final hit in result?.hits ?? <DictionarySearchHit>[]) ...[
              Text(hit.title, style: Theme.of(context).textTheme.titleMedium),
              SelectableText(hit.snippet),
              Text(t('来源：维基百科贡献者 · 摘录',
                  'Source: Wikipedia contributors · excerpt')),
              Wrap(children: [
                TextButton(
                    onPressed: () => open(hit.url),
                    child: Text(t('原词条 / 贡献者', 'Original / contributors'))),
                TextButton(
                    onPressed: () => open(Uri.parse(
                        'https://creativecommons.org/licenses/by-sa/4.0/')),
                    child: const Text('CC BY-SA 4.0')),
              ]),
              const Divider(),
            ],
            if (widget.baidu)
              TextButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () => open(Uri.https('baike.baidu.com',
                      '/search/word', {'word': widget.query})),
                  label: Text(t('在百度百科原站查询', 'Search Baidu Baike website'))),
            if (!widget.wikipedia && !widget.baidu)
              Text(t(
                  '请在百科设置中启用来源。', 'Enable sources in encyclopedia settings.')),
          ]));
}
