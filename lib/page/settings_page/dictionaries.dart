import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_common.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_sources.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
      ListView(padding: const EdgeInsets.all(24), children: [
        Text(ModuStrings.text(context, '自定义字典', 'Custom dictionaries'),
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(ModuStrings.text(
            context,
            '不预装本地词典数据。请导入有权使用的字典；可选择一本或多本进行离线查询，也可按需启用免费在线词典。本地字典及查询来源选择不参加 WebDAV 同步或设置备份。',
            'No local dictionary data is bundled. Import dictionaries you are licensed to use; select one or more for offline lookup, or opt into free online dictionaries. Local dictionaries and source selections are excluded from WebDAV sync and settings backups.')),
        TextButton.icon(
            onPressed: _busy || _loading
                ? null
                : () => showDictionarySources(context, _items),
            icon: const Icon(Icons.checklist),
            label: Text(ModuStrings.text(context, '查询来源 / 在线字典',
                'Query sources / online dictionaries'))),
        const SizedBox(height: 12),
        Text(ModuStrings.text(
            context,
            '支持 MDX 1/2（非 LZO、非加密正文，≤256 MiB），可同时选择同名 MDD、图片、音频、CSS、JS；有子目录时请使用 ZIP 保留目录结构。原版内容在隔离窗口显示，只加载已导入资源，音频需点击播放；旧词典需重新导入。StarDict 2.4.2/3.0.0 仍显示文字释义；暂不支持 DSL。',
            'Supports MDX 1/2 (no LZO or encrypted records, ≤256 MiB), with matching MDD, images, audio, CSS and JS. Use ZIP to preserve subdirectories. Original content opens in isolation using imported resources only; tap to play audio. Reimport old dictionaries. StarDict 2.4.2/3.0.0 remains text-only; DSL is unsupported.')),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: _busy || _loading ? null : _import,
            icon: const Icon(Icons.file_open_outlined),
            label:
                Text(ModuStrings.text(context, '导入字典', 'Import dictionary'))),
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
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_loading)
          const Center(
              child: EinkStaticIndicator(child: CircularProgressIndicator())),
        if (!_loading && _items.isEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(ModuStrings.text(
                  context, '尚未导入字典', 'No dictionaries imported'))),
        for (final item in _items)
          Card(
              child: Column(children: [
            SwitchListTile(
                value: item.enabled,
                onChanged: _busy
                    ? null
                    : (enabled) => _run(() => store.enable(item.id, enabled)),
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
