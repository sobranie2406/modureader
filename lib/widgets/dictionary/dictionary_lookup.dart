import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/page/settings_page/dictionaries.dart';
import 'package:modu_reader/service/dictionary/local_dictionary.dart';
import 'package:modu_reader/widgets/dictionary/dictionary_common.dart';
import 'package:modu_reader/widgets/dictionary/dictionary_sources.dart';
import 'package:modu_reader/widgets/dictionary/dictionary_original.dart';
import 'package:modu_reader/service/dictionary/dictionary_preferences.dart';
import 'package:modu_reader/service/dictionary/online_dictionary.dart';
import 'package:modu_reader/service/dictionary/dictionary_source_registry.dart';
import 'package:modu_reader/service/plugins/plugin_dictionary_transform.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:modu_reader/utils/toast/common.dart';
import 'package:url_launcher/url_launcher.dart';

class DictionaryLookup extends StatefulWidget {
  const DictionaryLookup(
      {super.key,
      required this.word,
      this.store,
      this.onlineService,
      this.transforms,
      this.embedded = false});
  final bool embedded;
  final String word;
  final LocalDictionaryStore? store;
  final OnlineDictionaryService? onlineService;
  final PluginDictionaryTransform? transforms;
  @override
  State<DictionaryLookup> createState() => _DictionaryLookupState();
}

class _DictionaryLookupState extends State<DictionaryLookup> {
  late final store = widget.store ?? defaultDictionaryStore();
  late final input = TextEditingController(text: widget.word.trim());
  late final online = widget.onlineService ?? OnlineDictionaryService();
  late final transforms = widget.transforms ?? PluginDictionaryTransform();
  final _requests = <CancelToken>[];
  final _onlineEntries = <OnlineDictionary, List<DictionaryEntry>>{};
  final _pending = <OnlineDictionary>{};
  final _failed = <OnlineDictionary>{};
  List<LocalDictionary> _dictionaries = [];
  DictionaryPreferences _preferences = DictionaryPreferences();
  List<DictionaryEntry> _entries = [];
  bool _busy = true, _hasDictionaries = false;
  String? _error;
  int _generation = 0;
  String t(String zh, String en) => dictionaryLabel(context, zh, en);

  /// Labels come from the registry so a future plugin source renders here too;
  /// the enum is only iterated for stable ordering.
  String _label(OnlineDictionary source) {
    final entry = DictionarySourceRegistry.current.byId(source.name);
    if (entry == null) return t(source.zh, source.en);
    return t(entry.labelZh, entry.labelEn);
  }

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _generation++;
    transforms.cancel();
    for (final request in _requests) {
      request.cancel();
    }
    if (widget.onlineService == null) online.close();
    input.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final generation = ++_generation;
    transforms.cancel();
    for (final request in _requests) {
      request.cancel();
    }
    _requests.clear();
    final word = input.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _entries = [];
      _onlineEntries.clear();
      _pending.clear();
      _failed.clear();
    });
    try {
      final dictionaries = await store.list();
      final preferences = await DictionaryPreferences.load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _dictionaries = dictionaries;
        _preferences = preferences;
        _hasDictionaries = dictionaries.any((d) =>
                d.enabled &&
                (preferences.localIds == null ||
                    preferences.localIds!.contains(d.id))) ||
            preferences.online.isNotEmpty;
        if (word.length > 256) {
          _error = ModuStrings.text(context, '请选择不超过 256 个字符的词语，或在上方修改查询内容。',
              'Select a word of up to 256 characters, or edit the query above.');
        }
      });
      if (word.isEmpty || word.length > 256) return;
      Future<List<String>>? variants;
      Future<List<String>> candidates() =>
          variants ??= transforms.candidates(word,
              isContextValid: () => mounted && generation == _generation);
      _pending.addAll(preferences.online);
      // Start independently so a slow/unavailable online source never hides local results.
      for (final source in preferences.online) {
        _searchOnline(source, word, generation, candidates);
      }
      final entries =
          await store.lookup(word, dictionaryIds: preferences.localIds);
      if (!mounted || generation != _generation) return;
      setState(() => _entries = entries);
      final missing = dictionaries
          .where((d) =>
              d.enabled &&
              (preferences.localIds == null ||
                  preferences.localIds!.contains(d.id)) &&
              !entries.any((e) => e.dictionaryId == d.id))
          .map((d) => d.id)
          .toSet();
      if (missing.isNotEmpty) {
        for (final candidate in await candidates()) {
          if (!mounted || generation != _generation) return;
          final matches = await store.lookup(candidate, dictionaryIds: missing);
          if (!mounted || generation != _generation) return;
          final accepted =
              matches.where((e) => missing.contains(e.dictionaryId)).toList();
          missing.removeAll(accepted.map((e) => e.dictionaryId));
          setState(() => _entries = [..._entries, ...accepted]);
          if (missing.isEmpty) break;
        }
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = dictionaryError(context, e));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _searchOnline(OnlineDictionary source, String word,
      int generation, Future<List<String>> Function() candidates) async {
    final token = CancelToken();
    _requests.add(token);
    try {
      var entries = await online.lookup(source, word, cancelToken: token);
      if (!mounted || generation != _generation) return;
      if (entries.isEmpty) {
        for (final candidate in await candidates()) {
          if (!mounted || generation != _generation) return;
          entries = await online.lookup(source, candidate, cancelToken: token);
          if (entries.isNotEmpty) break;
        }
      }
      if (mounted && generation == _generation) {
        setState(() => _onlineEntries[source] = entries);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failed.add(source));
      }
    } finally {
      _requests.remove(token);
      if (mounted && generation == _generation) {
        setState(() => _pending.remove(source));
      }
    }
  }

  Future<void> _sources() async {
    if (await showDictionarySources(context, _dictionaries) && mounted) {
      await _search();
    }
  }

  Future<void> _open(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {/* Show a local error without exposing the request URL. */}
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(t('无法打开来源链接。', 'Could not open source link.'))));
    }
  }

  Future<void> _copy(DictionaryEntry entry) async {
    final text = [
      entry.word,
      compactDictionaryText(entry.definition),
      '${t('来源', 'Source')}：${entry.dictionary}',
      if (entry.attribution != null) entry.attribution!,
      if (entry.sourceUri != null) entry.sourceUri.toString(),
      if (entry.license != null) entry.license!,
      if (entry.licenseUri != null) entry.licenseUri.toString(),
    ].where((part) => part.isNotEmpty).join('\n\n');
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) AnxToast.show(t('已复制', 'Copied'));
    } catch (_) {
      if (mounted) {
        AnxToast.show(t('复制失败，请重试', 'Could not copy. Please retry.'));
      }
    }
  }

  Future<void> _settings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
            appBar: AppBar(
                title: Text(
                    ModuStrings.text(context, '自定义字典', 'Custom dictionaries'))),
            body: DictionarySettings(store: store))));
    if (mounted) await _search();
  }

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        if (!widget.embedded)
          Row(children: [
            const SizedBox(width: 16),
            const Icon(Icons.menu_book_outlined),
            const SizedBox(width: 8),
            Expanded(
                child: Text(ModuStrings.text(context, '字典查询', 'Dictionary'),
                    style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
                onPressed: _settings,
                tooltip:
                    ModuStrings.text(context, '管理字典', 'Manage dictionaries'),
                icon: const Icon(Icons.settings_outlined)),
            IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: ModuStrings.text(context, '关闭', 'Close'),
                icon: const Icon(Icons.close)),
          ]),
        if (!widget.embedded)
          Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                  controller: input,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText:
                          ModuStrings.text(context, '查询词语', 'Look up a word'),
                      suffixIcon: IconButton(
                          onPressed: _search,
                          icon: const Icon(Icons.search),
                          tooltip:
                              ModuStrings.text(context, '查询', 'Search'))))),
        TextButton.icon(
            onPressed: _busy ? null : _sources,
            icon: const Icon(Icons.checklist),
            label: Text(t('查询字典（可单选或多选）', 'Query dictionaries (one or more)'))),
        if (_busy) const EinkStaticIndicator(child: LinearProgressIndicator()),
        Flexible(
            fit: widget.embedded ? FlexFit.loose : FlexFit.tight,
            child: ListView(
                shrinkWrap: widget.embedded,
                primary: false,
                physics: widget.embedded
                    ? const NeverScrollableScrollPhysics()
                    : null,
                padding: EdgeInsets.all(widget.embedded ? 4 : 12),
                children: [
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (!_busy && _error == null && !_hasDictionaries) ...[
                    Text(_dictionaries.any((d) => d.enabled)
                        ? t('尚未选择查询字典，请点击上方「查询字典」选择。',
                            'No dictionaries selected. Choose query dictionaries above.')
                        : t('尚无已启用的字典。请先导入或启用本地字典。',
                            'No enabled dictionaries. Import or enable a local dictionary first.')),
                    TextButton(
                        onPressed: _settings,
                        child: Text(ModuStrings.text(context, '导入 / 管理字典',
                            'Import / manage dictionaries'))),
                  ] else if (!_busy &&
                      _error == null &&
                      _entries.isEmpty &&
                      _onlineEntries.values.every((e) => e.isEmpty) &&
                      _pending.isEmpty &&
                      _failed.isEmpty)
                    Text(ModuStrings.text(context, '未找到完全匹配的词条，可修改词语后重试。',
                        'No exact match. Edit the word and try again.')),
                  for (final source in OnlineDictionary.values)
                    if (_pending.contains(source))
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                              '${_label(source)} · ${t('查询中…', 'Looking up…')}')),
                  for (final source in OnlineDictionary.values)
                    if (_failed.contains(source))
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(_label(source)),
                          subtitle: Text(t("在线查询失败，请重试。",
                              "Online lookup failed. Try again.")),
                          trailing: TextButton(
                              onPressed: _search,
                              child: Text(t('重试', 'Retry')))),
                  for (final source in _preferences.online)
                    if (_onlineEntries[source]?.isEmpty == true)
                      Text(
                          '${_label(source)} · ${t('未找到词条', 'No entry found')}'),
                  if (!_busy && _error == null)
                    for (final dictionary in _dictionaries)
                      if (dictionary.enabled &&
                          (_preferences.localIds == null ||
                              _preferences.localIds!.contains(dictionary.id)) &&
                          !_entries.any(
                              (entry) => entry.dictionaryId == dictionary.id))
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                                '${dictionary.name} · ${t('无条目', 'No entry found')}')),
                  for (final entry in [
                    ..._entries,
                    ...OnlineDictionary.values
                        .expand((s) => _onlineEntries[s] ?? <DictionaryEntry>[])
                  ])
                    Card(
                        elevation: widget.embedded ? 0 : null,
                        margin: widget.embedded
                            ? const EdgeInsets.only(bottom: 6)
                            : null,
                        shape: widget.embedded
                            ? const RoundedRectangleBorder()
                            : null,
                        child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.dictionary,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                              fontSize: 12, height: 1.4)),
                                  const SizedBox(height: 4),
                                  SelectableText(entry.word,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          height: 1.3,
                                          fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 4),
                                  if (entry.html != null &&
                                      entry.dictionaryId != null)
                                    DictionaryOriginal(
                                        key: ObjectKey(entry),
                                        store: store,
                                        entry: entry)
                                  else
                                    SelectableText(
                                        entry.definition.isEmpty
                                            ? ModuStrings.text(
                                                context,
                                                "此词条没有文字释义。",
                                                "This entry has no text definition.")
                                            : entry.dictionaryId != null
                                                ? compactDictionaryText(
                                                    entry.definition)
                                                : entry.definition,
                                        style: const TextStyle(
                                            fontSize: 14, height: 1.4)),
                                  const Divider(height: 12),
                                  Text(
                                      '${t('来源', 'Source')}：${entry.dictionary}${entry.sourceUri == null ? ' · ${t('本地导入', 'Imported locally')}' : ''}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                              fontSize: 12, height: 1.4)),
                                  if (entry.attribution != null)
                                    Text(
                                        '${entry.attribution} · ${t('释义摘录，已去除格式及例句', 'Definitions excerpted; formatting and examples removed')}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                fontSize: 12, height: 1.4)),
                                  if (entry.sourceUri != null)
                                    Wrap(spacing: 8, children: [
                                      TextButton(
                                          onPressed: () =>
                                              _open(entry.sourceUri!),
                                          child: Text(t('原词条 / 贡献者',
                                              'Original / contributors'))),
                                      if (entry.licenseUri != null &&
                                          entry.license != null)
                                        TextButton(
                                            onPressed: () =>
                                                _open(entry.licenseUri!),
                                            child: Text(entry.license!)),
                                    ]),
                                  Align(
                                      alignment: AlignmentDirectional.centerEnd,
                                      child: IconButton(
                                          tooltip: t('复制词条与释义',
                                              'Copy entry and definition'),
                                          onPressed: () => _copy(entry),
                                          icon: const Icon(Icons.copy_outlined,
                                              size: 20))),
                                ]))),
                ])),
      ]);
}
