import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/page/settings_page/selection_search.dart';
import 'package:anx_reader/page/settings_page/translate.dart';
import 'package:anx_reader/page/settings_page/narrate.dart';
import 'package:anx_reader/page/settings_page/dictionaries.dart';
import 'package:anx_reader/widgets/context_menu/selection_toolbar_labels.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';

Future<void> showSelectionToolbarSettings(BuildContext context) =>
    showReaderPopup(context,
        enableDrag: false,
        builder: (context) => Scaffold(
            appBar: AppBar(
                title: Text(ModuStrings.text(context, '划词工具栏', 'Selection toolbar')),
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
      if (mounted)
        setState(() =>
            _error = ModuStrings.text(context, '保存失败，请检查配置后重试。', 'Could not save toolbar settings.'));
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

  void _reorder(int from, int to, bool annotations) {
    if (_busy) return;
    final config = Prefs().selectionToolbar;
    final list = [...(annotations ? config.annotations : config.items)];
    list.insert(to, list.removeAt(from));
    _save(annotations
        ? config.copyWith(annotations: list)
        : config.copyWith(items: list));
  }

  Future<void> _edit(
      [SelectionToolbarItem? item, bool annotations = false]) async {
    final result = await showDialog<_ToolbarEditResult>(
        context: context, builder: (_) => _ToolbarItemEditor(item: item));
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
        context: context,
        builder: (context) => AlertDialog(
                title: Text(ModuStrings.text(context, '恢复默认工具栏？', 'Restore default toolbar?')),
                content: Text(ModuStrings.text(context, '恢复内置按钮、预设模板和颜色；预设 AI 模板默认关闭，自建 AI 命令保留。', 'Reset built-in actions, templates and colours. AI templates start disabled; your own commands are kept.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(ModuStrings.text(context, '恢复默认', 'Restore defaults')))
                ]));
    if (confirmed == true && mounted)
      await _save(Prefs().selectionToolbar.restoreDefaults());
  }

  Widget _list(List<SelectionToolbarItem> items, bool annotations) =>
      SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverReorderableList(
              key: ValueKey(annotations
                  ? 'selection-annotation-order'
                  : 'selection-action-order'),
              itemCount: items.length,
              onReorderItem: (a, b) => _reorder(a, b, annotations),
              itemBuilder: (context, index) {
                final item = items[index];
                final preset = SelectionToolbarConfig.templateItems
                    .any((p) => p.id == item.id);
                return Card(
                    key: ValueKey('toolbar-item-${item.id}'),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    elevation: 0,
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
                                      semanticLabel:
                                          ModuStrings.text(context, '拖动排序', 'Drag to reorder')))),
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
                                                          ? ModuStrings.text(context, '预设 AI 模板 · 可编辑', 'AI template · Editable')
                                                          : ModuStrings.text(context, '自定义 AI 命令', 'Custom AI command'),
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall),
                                              ]))))),
                          IconButton(
                              key: ValueKey('toolbar-edit-${item.id}'),
                              tooltip: ModuStrings.text(context, '编辑参数', 'Edit parameters'),
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
                                tooltip: ModuStrings.text(context, '更多', 'More'),
                                enabled: !_busy,
                                onSelected: (_) => _delete(item),
                                itemBuilder: (_) => [
                                      PopupMenuItem(
                                          value: 'delete',
                                          child: Text(ModuStrings.text(context, '删除', 'Delete')))
                                    ]),
                        ])));
              }));

  Widget _section(Widget child) => SliverToBoxAdapter(
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: child));

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Prefs(),
      builder: (context, _) {
        final config = Prefs().selectionToolbar;
        return CustomScrollView(
          key: const ValueKey('selection-toolbar-scroll'),
          primary: false,
          slivers: [
            _section(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ModuStrings.text(context, '自定义划词菜单的按钮显示和顺序。长按卡片或拖动左侧手柄排序，点击编辑图标调整参数。', 'Choose which selection actions appear and in what order. Hold a card or drag its handle; edit parameters using the pencil.')),
              const SizedBox(height: 12),
              SwitchListTile(
                  key: const ValueKey('selection-toolbar-enabled'),
                  contentPadding: EdgeInsets.zero,
                  title:
                      Text(ModuStrings.text(context, '选中文字时显示工具栏', 'Show toolbar when selecting text')),
                  value: config.enabled,
                  onChanged: _busy
                      ? null
                      : (value) => _save(config.copyWith(enabled: value))),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ModuStrings.text(context, '直接显示的按钮数量', 'Visible action count')),
                  subtitle: Text(ModuStrings.text(context, '其余已启用按钮放入“更多”，小屏幕会自动减少直接显示数量。', 'Remaining enabled actions appear under More. Smaller screens fit fewer buttons.')),
                  trailing: DropdownButton<int>(
                      key: const ValueKey('selection-toolbar-visible-count'),
                      value: config.visibleCount,
                      items: [
                        for (var n = 1; n <= 8; n++)
                          DropdownMenuItem(value: n, child: Text('$n'))
                      ],
                      onChanged: _busy
                          ? null
                          : (value) =>
                              _save(config.copyWith(visibleCount: value)))),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                    key: const ValueKey('toolbar-add-ai'),
                    icon: const Icon(Icons.add),
                    label: Text(ModuStrings.text(context, '新建 AI 命令', 'New AI command')),
                    onPressed: _busy ||
                            config.items
                                    .where((i) =>
                                        i.isCustom &&
                                        !SelectionToolbarConfig.templateItems
                                            .any((p) => p.id == i.id))
                                    .length >=
                                24
                        ? null
                        : () => _edit()),
                OutlinedButton.icon(
                    key: const ValueKey('toolbar-restore'),
                    icon: const Icon(Icons.restore),
                    label: Text(ModuStrings.text(context, '恢复默认', 'Restore defaults')),
                    onPressed: _busy ? null : _restore),
              ]),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 24),
              Text(ModuStrings.text(context, '工具按钮与 AI 模板', 'Actions and AI templates'),
                  style: Theme.of(context).textTheme.titleLarge),
            ])),
            _list(config.items, false),
            _section(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ModuStrings.text(context, '批注工具', 'Annotation tools'),
                  style: Theme.of(context).textTheme.titleLarge),
              Text(ModuStrings.text(context, '单独控制批注栏的按钮和顺序，不影响已有笔记。', 'Configure the annotation row without changing existing notes.')),
            ])),
            _list(config.annotations, true),
            _section(Text(ModuStrings.text(context, '搜索、翻译、字典和朗读共用各自功能的设置。AI 划词模板在此独立管理，默认关闭，使用当前 AI 服务，只发送选中文字；无需新增 API Key。每次提问开启新对话，共用阅读 AI 弹出框，回答完成后回到第一段。此配置随全局设置备份导出和导入。', 'AI selection templates are managed here separately, disabled by default and use your current AI provider. Each question starts a new conversation in the reader AI popup, returning to the answer start on completion. Search, translation, dictionary and speech share their feature settings. Toolbar configuration is included in global settings backups.'))),
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
  String? _error;
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
    final item = (widget.item ??
            SelectionToolbarItem(
                'custom-${DateTime.now().microsecondsSinceEpoch}', 'aiCommand'))
        .copyWith(
            name: _name.text.trim(),
            icon: _icon,
            prompt: _prompt.text.trim(),
            skillId: _skillId);
    if (item.isCustom && (item.name.isEmpty || item.prompt.isEmpty)) {
      setState(() => _error = ModuStrings.text(context, '请填写名称和提示词。', 'Enter a name and prompt.'));
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
        if (mounted)
          setState(() => _error = ModuStrings.text(context, '填写 1–20 个不重复的六位颜色值，例如 66CCFF。', 'Enter 1–20 unique six-digit RGB colours, e.g. 66CCFF.'));
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
                        maxLength: 30,
                        decoration: InputDecoration(
                            labelText: ModuStrings.text(context, '名称', 'Name'),
                            hintText: widget.item == null
                                ? null
                                : selectionToolbarLabel(context, widget.item!),
                            helperText: widget.item?.isCustom == false
                                ? ModuStrings.text(context, '留空使用默认名称', 'Leave blank for the default name')
                                : null)),
                    const SizedBox(height: 12),
                    Text(ModuStrings.text(context, '图标', 'Icon')),
                    Wrap(spacing: 4, children: [
                      for (final entry in selectionToolbarIcons.entries)
                        IconButton(
                            key: ValueKey('toolbar-icon-${entry.key}'),
                            isSelected: _icon == entry.key,
                            tooltip: entry.key,
                            icon: Icon(entry.value),
                            onPressed: () => setState(() => _icon = entry.key))
                    ]),
                    if (ai) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          key: const ValueKey('toolbar-ai-mode'),
                          isExpanded: true,
                          initialValue: _skillId,
                          decoration: InputDecoration(
                              labelText: ModuStrings.text(context, '处理方式', 'Processing mode')),
                          items: [
                            DropdownMenuItem(
                                value: 'selection_toolbar',
                                child:
                                    Text(ModuStrings.text(context, '仅处理选中文字', 'Selected text only'))),
                            DropdownMenuItem(
                                value: 'ai_dictionary',
                                child: Text(ModuStrings.text(context, 'AI 词典（知识优先／联网补充）', 'AI dictionary (knowledge / web lookup)'))),
                            for (final id in [
                              'concept_explainer',
                              'smart_translator',
                              'vocabulary_helper',
                              'mindmap'
                            ])
                              if (_skillId == id)
                                DropdownMenuItem(value: id, child: Text(id))
                          ],
                          onChanged: (value) =>
                              setState(() => _skillId = value!)),
                      const SizedBox(height: 12),
                      TextField(
                          key: const ValueKey('toolbar-prompt'),
                          controller: _prompt,
                          minLines: 5,
                          maxLines: 12,
                          maxLength: 8000,
                          decoration: InputDecoration(
                              labelText: ModuStrings.text(context, '提示词', 'Prompt'),
                              border: const OutlineInputBorder(),
                              helperText: ModuStrings.text(context, '用 {selection} 引用选中文字；没有占位符也会附上原文。', 'Use {selection} for selected text. Text is also included without a placeholder.'))),
                      if (widget.item?.action == 'ai')
                        Text(ModuStrings.text(context, '留空时只打开 AI 对话；填写提示词后点击即执行。', 'Leave blank to open chat; enter a prompt to run it on tap.')),
                    ],
                    if (widget.item?.action == 'colors') ...[
                      TextField(
                          key: const ValueKey('toolbar-colors'),
                          controller: _colors,
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                              labelText: ModuStrings.text(context, '颜色列表（逗号分隔）', 'Colours (comma separated)'))),
                    ],
                    if (['search', 'translate', 'dictionary', 'narrate']
                        .contains(widget.item?.action))
                      TextButton.icon(
                          icon: const Icon(Icons.settings_outlined),
                          onPressed: _featureSettings,
                          label: Text(
                              ModuStrings.text(context, '配置此功能的参数', 'Configure feature parameters'))),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
            FilledButton(
                key: const ValueKey('toolbar-editor-save'),
                onPressed: _save,
                child: Text(ModuStrings.text(context, '保存', 'Save')))
          ]);
}
