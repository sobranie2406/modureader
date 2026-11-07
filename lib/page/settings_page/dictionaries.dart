import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_common.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_sources.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:path/path.dart' as p;

// Android's MIME allowlist cannot represent MDX/IFO/IDX/DICT/SYN reliably.
// The importer validates the selected extensions and file contents itself.
FileType dictionaryPickerType(TargetPlatform platform) =>
    platform == TargetPlatform.android ? FileType.any : FileType.custom;

const dictionaryExtensions = [
  'mdx',
  'mdd',
  'css',
  'js',
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'svg',
  'mp3',
  'wav',
  'ogg',
  'm4a',
  'aac',
  'woff',
  'woff2',
  'ttf',
  'zip',
  'ifo',
  'idx',
  'gz',
  'dict',
  'dz',
  'syn'
];

class DictionarySettings extends StatefulWidget {
  const DictionarySettings({super.key, this.store});
  final LocalDictionaryStore? store;
  @override
  State<DictionarySettings> createState() => _DictionarySettingsState();
}

class _DictionarySettingsState extends State<DictionarySettings> {
  late final store = widget.store ?? defaultDictionaryStore();
  List<LocalDictionary> _items = [];
  bool _loading = true, _busy = false;
  int _count = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await store.list();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = dictionaryError(context, e);
          _loading = false;
        });
      }
    }
  }

  Future<String?> _name(String initial) async {
    final controller = TextEditingController(
        text: initial.substring(0, initial.length.clamp(0, 80)));
    ModalRoute<dynamic>? route;
    try {
      return await showDialog<String>(
          animationStyle: AppMotion.style,
          context: context,
          builder: (context) {
            route = ModalRoute.of(context);
            return AlertDialog(
                title:
                    Text(ModuStrings.text(context, '字典名称', 'Dictionary name')),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 80,
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        Navigator.pop(context, value.trim());
                      }
                    }),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
                  TextButton(
                      onPressed: () {
                        if (controller.text.trim().isNotEmpty) {
                          Navigator.pop(context, controller.text.trim());
                        }
                      },
                      child: Text(ModuStrings.text(context, '保存', 'Save')))
                ]);
          });
    } finally {
      // The dialog's reverse transition still references its controller.
      await route?.completed;
      controller.dispose();
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _count = 0;
    });
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = dictionaryError(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() => _run(() async {
        final pickerType = dictionaryPickerType(defaultTargetPlatform);
        final selection = await FilePicker.platform.pickFiles(
            allowMultiple: true,
            type: pickerType,
            allowedExtensions:
                pickerType == FileType.custom ? dictionaryExtensions : null,
            withData: false);
        if (selection == null || !mounted) return;
        if (selection.files.any((f) => f.path == null)) {
          throw const DictionaryFailure('io');
        }
        final main = selection.files.firstWhere(
            (f) => ['mdx', 'ifo', 'zip'].contains(f.extension?.toLowerCase()),
            orElse: () => selection.files.first);
        final name = await _name(p.basenameWithoutExtension(main.name));
        if (name == null) return;
        await store.importFiles(selection.paths.cast<String>(), name,
            onProgress: (count) {
          if (mounted) setState(() => _count = count);
        });
      });

  Future<void> _delete(LocalDictionary item) async {
    final confirmed = await showDialog<bool>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (context) => AlertDialog(
                title: Text(
                    ModuStrings.text(context, '删除字典？', 'Delete dictionary?')),
                content: Text(ModuStrings.format(
                    context,
                    '仅删除默读中的“{name}”及其查询索引，不删除原始字典文件。',
                    'Remove “{name}” and its lookup index from Modu only. Original source files are not deleted.',
                    values: {'name': item.name})),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(ModuStrings.text(context, '删除', 'Delete')))
                ]));
    if (confirmed == true && mounted) await _run(() => store.delete(item.id));
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        SettingsSection.content(
          title: Text(ModuStrings.text(
              context, '字典来源与导入', 'Dictionary sources and import')),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SettingHelp(
                title: Text(ModuStrings.text(context, '说明', 'Help')),
                description: Text(ModuStrings.text(
                    context,
                    "导入字典后即可离线查词，也可选择在线字典。",
                    "Import a dictionary for offline lookup, or choose an online dictionary."))),
            TextButton.icon(
                onPressed: _busy || _loading
                    ? null
                    : () => showDictionarySources(context, _items),
                icon: const Icon(Icons.checklist),
                label: Text(ModuStrings.text(context, '查询来源 / 在线字典',
                    'Query sources / online dictionaries'))),
            const SizedBox(height: 12),
            SettingHelp(
                title: Text(ModuStrings.text(context, '说明', 'Help')),
                description: Text(ModuStrings.text(
                    context,
                    "选择 MDX 和配套 MDD 文件，或选择 StarDict 文件。有资源子目录时，请将整本字典打包为 ZIP 导入。",
                    "Select an MDX and its MDD files, or StarDict files. Use a ZIP to include resource subfolders."))),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: _busy || _loading ? null : _import,
                icon: const Icon(Icons.file_open_outlined),
                label: Text(
                    ModuStrings.text(context, '导入字典', 'Import dictionary'))),
            if (_busy) ...[
              const SizedBox(height: 12),
              const EinkStaticIndicator(child: LinearProgressIndicator()),
              Text(ModuStrings.format(context, '正在处理字典，已导入 {count} 条…',
                  'Processing dictionary: {count} entries…',
                  values: {'count': _count}))
            ],
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            if (_loading)
              const Center(
                  child:
                      EinkStaticIndicator(child: CircularProgressIndicator())),
            if (!_loading && _items.isEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(ModuStrings.text(
                      context, '尚未导入字典', 'No dictionaries imported'))),
          ]),
        ),
        if (_items.isNotEmpty)
          SettingsSectionTitle(
              child: Text(ModuStrings.text(
                  context, '已安装字典', 'Installed dictionaries'))),
        for (final item in _items)
          Card(
              margin: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              child: Column(children: [
                SwitchListTile(
                    value: item.enabled,
                    onChanged: _busy
                        ? null
                        : (enabled) =>
                            _run(() => store.enable(item.id, enabled)),
                    title: Text(item.name),
                    subtitle: Text(
                        '${item.format} · ${item.count} ${ModuStrings.text(context, '条词目', 'entries')}')),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              final name = await _name(item.name);
                              if (name != null && mounted) {
                                await _run(() => store.rename(item.id, name));
                              }
                            },
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(ModuStrings.text(context, '改名', 'Rename'))),
                  TextButton.icon(
                      onPressed: _busy ? null : () => _delete(item),
                      icon: const Icon(Icons.delete_outline),
                      label: Text(ModuStrings.text(context, '删除', 'Delete'))),
                ]),
              ])),
      ]);
}
