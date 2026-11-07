import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/page/settings_page/selection_search.dart';
import 'package:anx_reader/page/settings_page/settings_page.dart';
import 'package:anx_reader/page/settings_page/translate.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/page/settings_page/dictionaries.dart';
import 'package:anx_reader/widgets/context_menu/selection_toolbar_labels.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';

Future<void> showSelectionToolbarSettings(BuildContext context,
        {bool readerAppearance = false}) =>
    showReaderPopup(context,
        readerAppearance: readerAppearance,
        allowWindowAdjustment: true,
        enableDrag: false,
        builder: (context) => Scaffold(
            appBar: AppBar(
                title: Text(
                    ModuStrings.text(context, '划词工具栏', 'Selection toolbar')),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context))
                ]),
            body: const SelectionToolbarSettings()));

class SelectionToolbarSettings extends StatefulWidget {
  const SelectionToolbarSettings({super.key});
  @override
  State<SelectionToolbarSettings> createState() =>
      _SelectionToolbarSettingsState();
}

class _ToolbarEditResult {
  const _ToolbarEditResult(this.item, this.colors);
  final SelectionToolbarItem item;
  final List<String>? colors;
}

class _SelectionToolbarSettingsState extends State<SelectionToolbarSettings> {
  bool _busy = false;
  String? _error;
  String t(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  Future<void> _save(SelectionToolbarConfig config) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Prefs().saveSelectionToolbar(config);
    } catch (_) {
      if (mounted) {
        setState(() => _error = ModuStrings.text(
            context, '保存失败，请检查配置后重试。', 'Could not save toolbar settings.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _replace(SelectionToolbarItem item, bool annotations) {
    final config = Prefs().selectionToolbar;
    final updated = [
      for (final old in annotations ? config.annotations : config.items)
        old.id == item.id ? item : old
    ];
    _save(annotations
        ? config.copyWith(annotations: updated)
        : config.copyWith(items: updated));
  }

  void _reorder(
      int from, int to, bool annotations, List<SelectionToolbarItem> group) {
    if (_busy) return;
    final config = Prefs().selectionToolbar;
    final reordered = [...group];
    reordered.insert(to, reordered.removeAt(from));
    final ids = group.map((i) => i.id).toSet();
    var index = 0;
    // Reorder only this group's slots, preserving saved cross-group ordering.
    final list = [
      for (final item in annotations ? config.annotations : config.items)
        ids.contains(item.id) ? reordered[index++] : item
    ];
    _save(annotations
        ? config.copyWith(annotations: list)
        : config.copyWith(items: list));
  }

  Future<void> _edit(
      [SelectionToolbarItem? item, bool annotations = false]) async {
    final result = await showDialog<_ToolbarEditResult>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (_) => _ToolbarItemEditor(item: item));
    if (result == null || !mounted) return;
    final config = Prefs().selectionToolbar;
    final updated = item == null
        ? [...config.items, result.item]
        : [
            for (final old in annotations ? config.annotations : config.items)
              old.id == result.item.id ? result.item : old
          ];
    await _save((annotations
            ? config.copyWith(annotations: updated)
            : config.copyWith(items: updated))
        .copyWith(colors: result.colors));
  }

  Future<void> _delete(SelectionToolbarItem item) async {
    final confirmed = await showDialog<bool>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (context) => AlertDialog(
                title: Text(t('删除“${item.name}”？', 'Delete “${item.name}”?')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(ModuStrings.text(context, '删除', 'Delete')))
                ]));
    if (confirmed != true || !mounted) return;
    final config = Prefs().selectionToolbar;
    await _save(config.copyWith(
        items: config.items.where((i) => i.id != item.id).toList()));
  }

  Future<void> _restore() async {
    final confirmed = await showDialog<bool>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (context) => AlertDialog(
                title: Text(ModuStrings.text(
                    context, '恢复默认工具栏？', 'Restore default toolbar?')),
                content: Text(ModuStrings.text(context, "恢复内置按钮和颜色，保留自建 AI 命令？",
                    "Reset built-in buttons and colors while keeping custom AI commands?")),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(ModuStrings.text(
                          context, '恢复默认', 'Restore defaults')))
                ]));
    if (confirmed == true && mounted) {
      await _save(Prefs().selectionToolbar.restoreDefaults());
    }
  }

  Widget _list(List<SelectionToolbarItem> items, bool annotations,
          {bool optional = false}) =>
      SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 9),
          sliver: SliverReorderableList(
              key: ValueKey(annotations
                  ? 'selection-annotation-order'
                  : optional
                      ? 'selection-optional-order'
                      : 'selection-action-order'),
              itemCount: items.length,
              onReorderItem: (a, b) => _reorder(a, b, annotations, items),
              itemBuilder: (context, index) {
                final item = items[index];
                final preset = SelectionToolbarConfig.templateItems
                    .any((p) => p.id == item.id);
                return Card(
                    key: ValueKey('toolbar-item-${item.id}'),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                            color:
                                Theme.of(context).colorScheme.outlineVariant)),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Row(children: [
                          ReorderableDragStartListener(
                              index: index,
                              enabled: !_busy,
                              child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(Icons.drag_indicator,
                                      semanticLabel: ModuStrings.text(context,
                                          '拖动排序', 'Drag to reorder')))),
                          Icon(selectionToolbarIcon(item)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: ReorderableDelayedDragStartListener(
                                  index: index,
                                  enabled: !_busy,
                                  child: InkWell(
                                      onTap: _busy
                                          ? null
                                          : () => _edit(item, annotations),
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8),
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                    selectionToolbarLabel(
                                                        context, item),
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleMedium),
                                                if (item.isCustom)
                                                  Text(
                                                      preset
                                                          ? ModuStrings.text(
                                                              context,
                                                              '预设 AI 模板 · 可编辑',
                                                              'AI template · Editable')
                                                          : ModuStrings.text(
                                                              context,
                                                              '自定义 AI 命令',
                                                              'Custom AI command'),
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall),
                                              ]))))),
                          IconButton(
                              key: ValueKey('toolbar-edit-${item.id}'),
                              tooltip: ModuStrings.text(
                                  context, '编辑参数', 'Edit parameters'),
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: _busy
                                  ? null
                                  : () => _edit(item, annotations)),
                          Switch(
                              key: ValueKey('toolbar-toggle-${item.id}'),
                              value: item.enabled,
                              onChanged: _busy
                                  ? null
                                  : (value) => _replace(
                                      item.copyWith(enabled: value),
                                      annotations)),
                          if (item.isCustom)
                            PopupMenuButton<String>(
                                popUpAnimationStyle: AppMotion.style,
                                tooltip:
                                    ModuStrings.text(context, '更多', 'More'),
                                enabled: !_busy,
                                onSelected: (_) => _delete(item),
                                itemBuilder: (_) => [
                                      PopupMenuItem(
                                          value: 'delete',
                                          child: Text(ModuStrings.text(
                                              context, '删除', 'Delete')))
                                    ]),
                        ])));
              }));

  Widget _section(Widget child) => SliverToBoxAdapter(
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: child));

  void _openLookupSettings(String title, Widget page) {
    Navigator.of(context).push(MotionCupertinoPageRoute<void>(
      builder: (context) => SettingsPageBody(
        title: title,
        isMobile: true,
        sections: Material(type: MaterialType.transparency, child: page),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Prefs(),
      builder: (context, _) {
        final config = Prefs().selectionToolbar;
        final primaryIds = SelectionToolbarConfig.defaultItems
            .where((item) => item.enabled)
            .map((item) => item.id)
            .toSet();
        return CustomScrollView(
          key: const ValueKey('selection-toolbar-scroll'),
          primary: false,
          slivers: [
            SliverToBoxAdapter(
                child: SettingsSection.content(
                    title: Text(
                        ModuStrings.text(context, '工具栏设置', 'Toolbar settings')),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SettingHelp(
                              title: Text(ModuStrings.text(
                                  context, "排列按钮", "Arrange actions")),
                              description: Text(ModuStrings.text(
                                  context,
                                  "拖动手柄排序，点击编辑按钮调整。",
                                  "Drag the handles to reorder. Tap Edit to change an action."))),
                          const SizedBox(height: 12),
                          SwitchListTile(
                              key: const ValueKey('selection-toolbar-enabled'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(ModuStrings.text(
                                  context,
                                  '选中文字时显示工具栏',
                                  'Show toolbar when selecting text')),
                              value: config.enabled,
                              onChanged: _busy
                                  ? null
                                  : (value) =>
                                      _save(config.copyWith(enabled: value))),
                          ListTile(
                              key: const ValueKey('selection-search-settings'),
                              textColor:
                                  Theme.of(context).colorScheme.onSurface,
                              iconColor: Theme.of(context).colorScheme.primary,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.travel_explore),
                              title: Text(ModuStrings.text(
                                  context, '选词搜索', 'Selection search')),
                              subtitle: Text(ModuStrings.text(
                                  context,
                                  '内置浏览器 · 自定义搜索引擎',
                                  'In-app browser · Custom search engines')),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openLookupSettings(
                                  ModuStrings.text(
                                      context, '选词搜索', 'Selection search'),
                                  const SelectionSearchSettings())),
                          ListTile(
                              key: const ValueKey(
                                  'selection-dictionary-settings'),
                              textColor:
                                  Theme.of(context).colorScheme.onSurface,
                              iconColor: Theme.of(context).colorScheme.primary,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.menu_book_outlined),
                              title: Text(ModuStrings.text(
                                  context, '自定义字典', 'Custom dictionaries')),
                              subtitle: Text(ModuStrings.text(
                                  context,
                                  '本地导入 · 查询来源 · 离线选词查询',
                                  'Local import · Query sources · Offline lookup')),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => _openLookupSettings(
                                  ModuStrings.text(
                                      context, '自定义字典', 'Custom dictionaries'),
                                  const DictionarySettings())),
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(ModuStrings.text(context, '直接显示的按钮数量',
                                  'Visible action count')),
                              subtitle: Text(ModuStrings.text(
                                  context,
                                  "放不下的按钮收进“更多”。",
                                  "Extra buttons appear in More.")),
                              trailing: DropdownButton<int>(
                                  key: const ValueKey(
                                      'selection-toolbar-visible-count'),
                                  value: config.visibleCount,
                                  items: [
                                    for (var n = 1; n <= 8; n++)
                                      DropdownMenuItem(
                                          value: n, child: Text('$n'))
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (value) => _save(config.copyWith(
                                          visibleCount: value)))),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            FilledButton.icon(
                                key: const ValueKey('toolbar-add-ai'),
                                icon: const Icon(Icons.add),
                                label: Text(ModuStrings.text(
                                    context, '新建 AI 命令', 'New AI command')),
                                onPressed: _busy ||
                                        config.items
                                                .where((i) =>
                                                    i.isCustom &&
                                                    !SelectionToolbarConfig
                                                        .templateItems
                                                        .any((p) =>
                                                            p.id == i.id))
                                                .length >=
                                            24
                                    ? null
                                    : () => _edit()),
                            OutlinedButton.icon(
                                key: const ValueKey('toolbar-restore'),
                                icon: const Icon(Icons.restore),
                                label: Text(ModuStrings.text(
                                    context, '恢复默认', 'Restore defaults')),
                                onPressed: _busy ? null : _restore),
                          ]),
                          if (_error != null)
                            Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                        ]))),
            SliverToBoxAdapter(
                child: SettingsSectionTitle(
                    child: Text(ModuStrings.text(context, '常用工具（默认开启）',
                        'Common tools (on by default)')))),
            _list(config.items.where((i) => primaryIds.contains(i.id)).toList(),
                false),
            SliverToBoxAdapter(
                child: SettingsSectionTitle(
                    child: Text(ModuStrings.text(
                        context, '批注工具', 'Annotation tools')))),
            _list(config.annotations, true),
            SliverToBoxAdapter(
                child: SettingsSectionTitle(
                    child: Text(ModuStrings.text(context, '可选工具与 AI 模板（默认关闭）',
                        'Optional tools and AI templates (off by default)')))),
            _list(
                config.items.where((i) => !primaryIds.contains(i.id)).toList(),
                false,
                optional: true),
            _section(SettingHelpTitle(
                title: ModuStrings.text(context, 'AI 模板', 'AI templates'),
                description: ModuStrings.value(Localizations.localeOf(context),
                    'selection_ai_help', '启用模板后，可设置内容范围和联网搜索。'))),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
      });
}

class _ToolbarItemEditor extends StatefulWidget {
  const _ToolbarItemEditor({this.item});
  final SelectionToolbarItem? item;
  @override
  State<_ToolbarItemEditor> createState() => _ToolbarItemEditorState();
}

class _ToolbarItemEditorState extends State<_ToolbarItemEditor> {
  bool _languageInitialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_languageInitialized) {
      _languageInitialized = true;
      final locale = Localizations.localeOf(context);
      _name.text = widget.item?.localizedName(locale) ?? '';
      _prompt.text = widget.item?.localizedPrompt(locale) ?? '';
    }
  }

  late final _name = TextEditingController(text: widget.item?.name);
  late final _prompt = TextEditingController(text: widget.item?.prompt);
  late final _colors =
      TextEditingController(text: Prefs().selectionToolbar.colors.join(', '));
  late String _icon = widget.item?.icon.isNotEmpty == true
      ? widget.item!.icon
      : (widget.item?.action ?? 'ai');
  late String _skillId = widget.item?.skillId ?? 'selection_toolbar';
  late SelectionAiScope _scope = widget.item?.scope ?? SelectionAiScope.context;
  late bool _webSearch = widget.item?.webSearch ?? false;
  String? _error;
  bool _textEdited = false;
  Future<void> _optionWrites = Future.value();

  void _saveOptions() {
    if (widget.item == null) return;
    final id = widget.item!.id;
    final icon = _icon, skillId = _skillId;
    final scope = _scope;
    final webSearch = _webSearch;
    _optionWrites = _optionWrites.then((_) async {
      final config = Prefs().selectionToolbar;
      SelectionToolbarItem update(SelectionToolbarItem item) => item.id == id
          ? item.copyWith(
              icon: icon, skillId: skillId, scope: scope, webSearch: webSearch)
          : item;
      await Prefs().saveSelectionToolbar(config.copyWith(
        items: config.items.map(update).toList(),
        annotations: config.annotations.map(update).toList(),
      ));
      if (mounted) setState(() => _error = null);
    }).catchError((Object error) {
      if (mounted) {
        setState(() =>
            _error = t('自动保存失败，请重试。', 'Could not auto-save. Please retry.'));
      }
    });
  }

  bool get ai => widget.item == null || widget.item!.isAi;
  String t(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _colors.dispose();
    super.dispose();
  }

  Future<void> _featureSettings() async {
    final page = switch (widget.item?.action) {
      'search' => const SelectionSearchSettings(),
      'translate' => const TranslateSetting(),
      'dictionary' => const DictionarySettings(),
      'narrate' => const NarrateSettings(),
      _ => null,
    };
    if (page == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (context) => Scaffold(
            appBar: AppBar(
                title: Text(selectionToolbarLabel(context, widget.item!))),
            body: page)));
  }

  Future<void> _save() async {
    await _optionWrites;
    if (!mounted) return;
    final item = (widget.item ??
            SelectionToolbarItem(
                'custom-${DateTime.now().microsecondsSinceEpoch}', 'aiCommand'))
        .copyWith(
            name: _name.text.trim(),
            icon: _icon,
            prompt: _prompt.text.trim(),
            scope: _scope,
            webSearch: _webSearch,
            skillId: _skillId);
    if (item.isCustom && (item.name.isEmpty || item.prompt.isEmpty)) {
      setState(() => _error =
          ModuStrings.text(context, '请填写名称和提示词。', 'Enter a name and prompt.'));
      return;
    }
    List<String>? colors;
    if (widget.item?.action == 'colors') {
      colors = _colors.text
          .split(RegExp(r'[\s,，;；]+'))
          .where((c) => c.isNotEmpty)
          .map((c) => c.replaceFirst('#', '').toUpperCase())
          .toList();
      try {
        Prefs().selectionToolbar.copyWith(colors: colors).validate();
      } catch (_) {
        if (mounted) {
          setState(() => _error = ModuStrings.text(
              context,
              '填写 1–20 个不重复的六位颜色值，例如 66CCFF。',
              'Enter 1–20 unique six-digit RGB colours, e.g. 66CCFF.'));
        }
        return;
      }
    }
    if (mounted) Navigator.pop(context, _ToolbarEditResult(item, colors));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.item == null
              ? ModuStrings.text(context, '新建 AI 命令', 'New AI command')
              : ModuStrings.text(context, '编辑工具参数', 'Edit action parameters')),
          content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    TextField(
                        key: const ValueKey('toolbar-name'),
                        controller: _name,
                        onChanged: (_) => setState(() => _textEdited = true),
                        maxLength: 30,
                        decoration: InputDecoration(
                          labelText: ModuStrings.text(context, '名称', 'Name'),
                          hintText: widget.item == null
                              ? null
                              : selectionToolbarLabel(context, widget.item!),
                        )),
                    const SizedBox(height: 12),
                    Text(ModuStrings.text(context, '图标', 'Icon')),
                    Wrap(spacing: 4, children: [
                      for (final entry in selectionToolbarIcons.entries)
                        IconButton(
                            key: ValueKey('toolbar-icon-${entry.key}'),
                            isSelected: _icon == entry.key,
                            tooltip: entry.key,
                            icon: Icon(entry.value),
                            onPressed: () {
                              setState(() => _icon = entry.key);
                              _saveOptions();
                            })
                    ]),
                    if (ai) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          key: const ValueKey('toolbar-ai-mode'),
                          isExpanded: true,
                          initialValue: _skillId,
                          decoration: InputDecoration(
                              labelText: ModuStrings.text(
                                  context, '处理方式', 'Processing mode')),
                          items: [
                            DropdownMenuItem(
                                value: 'selection_toolbar',
                                child: Text(ModuStrings.value(
                                    Localizations.localeOf(context),
                                    'selection_ai_prompt_mode',
                                    '提示词处理'))),
                            DropdownMenuItem(
                                value: 'ai_dictionary',
                                child: Text(ModuStrings.value(
                                    Localizations.localeOf(context),
                                    'skill_ai_dictionary_name',
                                    'AI 知识'))),
                            for (final id in [
                              'concept_explainer',
                              'smart_translator',
                              'vocabulary_helper',
                              'mindmap'
                            ])
                              if (_skillId == id)
                                DropdownMenuItem(value: id, child: Text(id))
                          ],
                          onChanged: (value) {
                            setState(() => _skillId = value!);
                            _saveOptions();
                          }),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<SelectionAiScope>(
                        key: const ValueKey('toolbar-ai-scope'),
                        initialValue: _scope,
                        isExpanded: true,
                        decoration: InputDecoration(
                            labelText: ModuStrings.value(
                                Localizations.localeOf(context),
                                'selection_ai_scope',
                                '内容范围')),
                        items: [
                          for (final scope in SelectionAiScope.values)
                            DropdownMenuItem(
                                value: scope,
                                child: Text(ModuStrings.value(
                                    Localizations.localeOf(context),
                                    'selection_ai_scope_${scope.name}',
                                    scope == SelectionAiScope.selection
                                        ? '仅选中文字'
                                        : '结合上下文'))),
                        ],
                        onChanged: (value) {
                          setState(() => _scope = value!);
                          _saveOptions();
                        },
                      ),
                      const SizedBox(height: 12),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                                key: const ValueKey('toolbar-prompt'),
                                controller: _prompt,
                                onChanged: (_) =>
                                    setState(() => _textEdited = true),
                                minLines: 5,
                                maxLines: 12,
                                maxLength: 8000,
                                decoration: InputDecoration(
                                  labelText: ModuStrings.text(
                                      context, '提示词', 'Prompt'),
                                  border: const OutlineInputBorder(),
                                )),
                            SettingHelpTitle(
                                title: ModuStrings.text(context, "说明", "Help"),
                                description: ModuStrings.text(
                                    context,
                                    '用 {selection} 引用选中文字；没有占位符也会附上原文。',
                                    'Use {selection} for selected text. Text is also included without a placeholder.'))
                          ]),
                      CheckboxListTile(
                        key: const ValueKey('toolbar-ai-web-search'),
                        contentPadding: EdgeInsets.zero,
                        value: _webSearch,
                        title: SettingHelpTitle(
                            title: ModuStrings.value(
                                Localizations.localeOf(context),
                                'selection_ai_web_search',
                                '联网搜索'),
                            description: ModuStrings.value(
                                Localizations.localeOf(context),
                                'selection_ai_web_search_help',
                                '查询词典和百科，由 AI 整理并附上来源。')),
                        onChanged: (value) {
                          setState(() => _webSearch = value!);
                          _saveOptions();
                        },
                      ),
                      if (widget.item?.action == 'ai')
                        Text(ModuStrings.text(
                            context,
                            '留空时只打开 AI 对话；填写提示词后点击即执行。',
                            'Leave blank to open chat; enter a prompt to run it on tap.')),
                    ],
                    if (widget.item?.action == 'colors') ...[
                      TextField(
                          key: const ValueKey('toolbar-colors'),
                          controller: _colors,
                          onChanged: (_) => setState(() => _textEdited = true),
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                              labelText: ModuStrings.text(context, '颜色列表（逗号分隔）',
                                  'Colours (comma separated)'))),
                    ],
                    if (['search', 'translate', 'dictionary', 'narrate']
                        .contains(widget.item?.action))
                      TextButton.icon(
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: _featureSettings,
                          label: Text(ModuStrings.text(context, '配置此功能的参数',
                              'Configure feature parameters'))),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(widget.item == null || _textEdited
                    ? ModuStrings.text(context, '取消', 'Cancel')
                    : ModuStrings.text(context, '关闭', 'Close'))),
            if (_error != null && widget.item != null)
              TextButton(
                  onPressed: _saveOptions, child: Text(t('重试', 'Retry'))),
            if (widget.item == null || _textEdited)
              FilledButton(
                  key: const ValueKey('toolbar-editor-save'),
                  onPressed: _save,
                  child: Text(ModuStrings.text(context, '保存', 'Save')))
          ]);
}
