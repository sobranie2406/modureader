import 'package:anx_reader/page/settings_page/dictionaries.dart';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_common.dart';
import 'package:flutter/material.dart';

class DictionaryLookup extends StatefulWidget {
  const DictionaryLookup({super.key, required this.word, this.store});
  final String word;
  final LocalDictionaryStore? store;
  @override
  State<DictionaryLookup> createState() => _DictionaryLookupState();
}

class _DictionaryLookupState extends State<DictionaryLookup> {
  late final store = widget.store ?? defaultDictionaryStore();
  late final input = TextEditingController(text: widget.word.trim());
  List<DictionaryEntry> _entries = [];
  bool _busy = true, _hasDictionaries = false;
  String? _error;
  int _generation = 0;
  String t(String zh, String en) => dictionaryLabel(context, zh, en);
  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _generation++;
    input.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final generation = ++_generation;
    final word = input.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _entries = [];
    });
    try {
      final dictionaries = await store.list();
      final entries = await store.lookup(word);
      if (!mounted || generation != _generation) return;
      setState(() {
        _hasDictionaries = dictionaries.any((d) => d.enabled);
        _entries = entries;
        if (word.length > 256) {
          _error = t('请选择不超过 256 个字符的词语，或在上方修改查询内容。',
              'Select a word of up to 256 characters, or edit the query above.');
        }
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = dictionaryError(context, e));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _settings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
            appBar: AppBar(title: Text(t('自定义字典', 'Custom dictionaries'))),
            body: DictionarySettings(store: store))));
    if (mounted) await _search();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [
          const SizedBox(width: 16),
          const Icon(Icons.menu_book_outlined),
          const SizedBox(width: 8),
          Expanded(
              child: Text(t('字典查询', 'Dictionary'),
                  style: Theme.of(context).textTheme.titleLarge)),
          IconButton(
              onPressed: _settings,
              tooltip: t('管理字典', 'Manage dictionaries'),
              icon: const Icon(Icons.settings_outlined)),
          IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: t('关闭', 'Close'),
              icon: const Icon(Icons.close)),
        ]),
        Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
                controller: input,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: t('查询词语', 'Look up a word'),
                    suffixIcon: IconButton(
                        onPressed: _search,
                        icon: const Icon(Icons.search),
                        tooltip: t('查询', 'Search'))))),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (!_busy && _error == null && !_hasDictionaries) ...[
            Text(t('尚无已启用的字典。请先导入或启用本地字典。',
                'No enabled dictionaries. Import or enable a local dictionary first.')),
            TextButton(
                onPressed: _settings,
                child: Text(t('导入 / 管理字典', 'Import / manage dictionaries'))),
          ] else if (!_busy && _error == null && _entries.isEmpty)
            Text(t('未找到完全匹配的词条，可修改词语后重试。',
                'No exact match. Edit the word and try again.')),
          for (final entry in _entries)
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.dictionary,
                              style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 8),
                          SelectableText(entry.word,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          SelectableText(
                              entry.definition.isEmpty
                                  ? t('此词条没有文字释义，可能仅包含暂不支持的多媒体资源。',
                                      'No text definition; this entry may contain unsupported media only.')
                                  : entry.definition,
                              style:
                                  const TextStyle(fontSize: 16, height: 1.5)),
                        ]))),
        ])),
      ]);
}
