import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

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
  String t(String zh, String en) => dictionaryLabel(context, zh, en);

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
          context: context,
          builder: (context) {
            route = ModalRoute.of(context);
            return AlertDialog(
                title: Text(t('字典名称', 'Dictionary name')),
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
                      child: Text(t('取消', 'Cancel'))),
                  TextButton(
                      onPressed: () {
                        if (controller.text.trim().isNotEmpty) {
                          Navigator.pop(context, controller.text.trim());
                        }
                      },
                      child: Text(t('保存', 'Save')))
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
        final selection = await FilePicker.platform.pickFiles(
            allowMultiple: true,
            type: FileType.custom,
            allowedExtensions: [
              'mdx',
              'zip',
              'ifo',
              'idx',
              'gz',
              'dict',
              'dz',
              'syn'
            ],
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
        context: context,
        builder: (context) => AlertDialog(
                title: Text(t('删除字典？', 'Delete dictionary?')),
                content: Text(t('仅删除默读中的“${item.name}”及其查询索引，不删除原始字典文件。',
                    'Remove “${item.name}” and its lookup index from Modu only. Original source files are not deleted.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(t('取消', 'Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(t('删除', 'Delete')))
                ]));
    if (confirmed == true && mounted) await _run(() => store.delete(item.id));
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(24), children: [
        Text(t('自定义字典', 'Custom dictionaries'),
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(t(
            '应用不内嵌字典。请导入有权使用的本地字典；选中文字后点“字典”即可离线查询所有已启用的字典。字典仅保存在本机，不参加 WebDAV 同步或设置备份。',
            'No dictionaries are bundled. Import dictionaries you are licensed to use, then select text and tap Dictionary to search enabled dictionaries offline. Dictionaries stay on this device and are excluded from WebDAV sync and settings backups.')),
        const SizedBox(height: 12),
        Text(t(
            '支持：MDX 1/2（非 LZO、非加密正文，≤256 MiB）；StarDict 2.4.2/3.0.0（IFO + IDX/IDX.GZ + DICT/DICT.DZ，可选 SYN），也支持单本字典 ZIP。仅显示文字释义；不执行脚本、不加载外部资源，暂不支持 MDD 图片/音频和 DSL。',
            'Supported: MDX 1/2 (no LZO or encrypted records, ≤256 MiB); StarDict 2.4.2/3.0.0 (IFO + IDX/IDX.GZ + DICT/DICT.DZ, optional SYN), or a ZIP with one dictionary. Text definitions only: no scripts or external resources. MDD images/audio and DSL are not supported yet.')),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: _busy || _loading ? null : _import,
            icon: const Icon(Icons.file_open_outlined),
            label: Text(t('导入字典', 'Import dictionary'))),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          Text(t('正在处理字典，已导入 $_count 条…',
              'Processing dictionary: $_count entries…'))
        ],
        if (_error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        if (_loading) const Center(child: CircularProgressIndicator()),
        if (!_loading && _items.isEmpty)
          Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(t('尚未导入字典', 'No dictionaries imported'))),
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
                    '${item.format} · ${item.count} ${t('条词目', 'entries')}')),
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
                  label: Text(t('改名', 'Rename'))),
              TextButton.icon(
                  onPressed: _busy ? null : () => _delete(item),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(t('删除', 'Delete'))),
            ]),
          ])),
      ]);
}
