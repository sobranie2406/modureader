import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/selection_search.dart';
import 'package:flutter/material.dart';

class SelectionSearchSettings extends StatefulWidget {
  const SelectionSearchSettings({super.key});
  @override
  State<SelectionSearchSettings> createState() =>
      _SelectionSearchSettingsState();
}

class _SelectionSearchSettingsState extends State<SelectionSearchSettings> {
  bool _busy = false;
  String? _error;
  String t(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  Future<void> _save(SelectionSearchConfig config) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Prefs().saveSelectionSearchSettings(config);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = t('保存失败，请检查搜索配置后重试。', 'Could not save search settings.'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([SelectionSearchEngine? engine]) async {
    final result = await showDialog<SelectionSearchEngine>(
        context: context, builder: (_) => _EngineEditor(engine: engine));
    if (result == null || !mounted) return;
    final config = Prefs().selectionSearchSettings;
    await _save(SelectionSearchConfig(selectedId: config.selectedId, custom: [
      for (final item in config.custom)
        if (item.id != result.id) item,
      result,
    ]));
  }

  Future<void> _delete(SelectionSearchEngine engine) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(t('删除“${engine.name}”？', 'Delete “${engine.name}”?')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(t('取消', 'Cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(t('删除', 'Delete'))),
              ],
            ));
    if (confirmed != true || !mounted) return;
    final config = Prefs().selectionSearchSettings;
    await _save(SelectionSearchConfig(
        selectedId: config.selectedId == engine.id ? 'bing' : config.selectedId,
        custom: config.custom.where((item) => item.id != engine.id).toList()));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: Prefs(),
      builder: (context, _) {
        final config = Prefs().selectionSearchSettings;
        final zh = Localizations.localeOf(context).languageCode == 'zh';
        return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            children: [
              Text(t('选词搜索将在默读内打开。选择默认引擎，也可以在搜索窗口中随时切换。关键词会发送给所选网站，网站可用性取决于网络。',
                  'Selection search opens inside Modu. Choose a default or switch in the search window. The selected website receives your query; availability depends on your network.')),
              const SizedBox(height: 16),
              for (final engine in config.engines)
                ListTile(
                  leading: Icon(engine.id == config.selectedId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off),
                  title: Text(engine.label(zh)),
                  subtitle: Text(engine.template),
                  onTap: _busy
                      ? null
                      : () => _save(SelectionSearchConfig(
                          selectedId: engine.id, custom: config.custom)),
                  trailing: config.custom.any((e) => e.id == engine.id)
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              tooltip: t('编辑', 'Edit'),
                              onPressed: _busy ? null : () => _edit(engine),
                              icon: const Icon(Icons.edit_outlined)),
                          IconButton(
                              tooltip: t('删除', 'Delete'),
                              onPressed: _busy ? null : () => _delete(engine),
                              icon: const Icon(Icons.delete_outline)),
                        ])
                      : null,
                ),
              FilledButton.icon(
                  onPressed: _busy || config.custom.length >= 20
                      ? null
                      : () => _edit(),
                  icon: const Icon(Icons.add),
                  label: Text(t('添加自定义搜索引擎', 'Add custom search engine'))),
              const SizedBox(height: 12),
              Text(t(
                  '可添加最多 20 个自定义引擎。使用 {query} 表示选中的文字，例如 https://www.baidu.com/s?wd={query}。配置可随全局设置导出。',
                  'Add up to 20 engines. Use {query} for selected text, e.g. https://www.baidu.com/s?wd={query}. These settings are included in global settings exports.')),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ]);
      });
}

class _EngineEditor extends StatefulWidget {
  const _EngineEditor({this.engine});
  final SelectionSearchEngine? engine;
  @override
  State<_EngineEditor> createState() => _EngineEditorState();
}

class _EngineEditorState extends State<_EngineEditor> {
  late final _name = TextEditingController(text: widget.engine?.name);
  late final _url = TextEditingController(text: widget.engine?.template);
  String? _error;
  String t(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _save() {
    final engine = SelectionSearchEngine(
        widget.engine?.id ?? 'custom-${DateTime.now().microsecondsSinceEpoch}',
        _name.text.trim(),
        _url.text.trim());
    try {
      engine.validate();
    } catch (_) {
      setState(() => _error = t(
          '请填写名称和含 {query} 的 HTTP(S) 地址；占位符不能放在域名中，地址不能含账号密码。',
          'Enter a name and an HTTP(S) URL containing {query} in its path or query, without credentials.'));
      return;
    }
    Navigator.pop(context, engine);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(t('自定义搜索引擎', 'Custom search engine')),
        content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: _name,
                  maxLength: 60,
                  decoration: InputDecoration(labelText: t('名称', 'Name'))),
              TextField(
                  controller: _url,
                  maxLength: 2048,
                  minLines: 2,
                  maxLines: 4,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                      labelText:
                          t('搜索地址（含 {query}）', 'Search URL (with {query})'))),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('取消', 'Cancel'))),
          FilledButton(onPressed: _save, child: Text(t('保存', 'Save')))
        ],
      );
}
