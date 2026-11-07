import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/weread/weread_api.dart';
import 'package:flutter/material.dart';
import 'weread_common.dart';

class WereadLinkPage extends StatefulWidget {
  const WereadLinkPage(
      {super.key, required this.title, required this.author, this.apiFactory});
  final String title, author;
  final WereadApi Function(String)? apiFactory;
  @override
  State<WereadLinkPage> createState() => _WereadLinkPageState();
}

class _WereadLinkPageState extends State<WereadLinkPage> {
  late final _title = TextEditingController(text: widget.title);
  late final _author = TextEditingController(text: widget.author);
  final _results = <Map<String, dynamic>>[];
  WereadApi? _api;
  bool _busy = false, _searched = false, _more = false;
  int _cursor = 0;
  String? _error;

  @override
  void dispose() {
    _api?.close();
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _request(
      Future<void> Function(WereadApi, bool Function()) action) async {
    if (_busy) return;
    if (!Prefs().wereadEnabled || Prefs().wereadApiKey.isEmpty) {
      setState(() =>
          _error = wereadError(context, const WereadException('unauthorized')));
      return;
    }
    final key = Prefs().wereadApiKey;
    final api = _api = widget.apiFactory?.call(key) ?? WereadApi(key);
    bool valid() =>
        mounted && Prefs().wereadEnabled && Prefs().wereadApiKey == key;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(api, valid);
    } catch (e) {
      if (mounted) setState(() => _error = wereadError(context, e));
    } finally {
      api.close();
      if (identical(_api, api)) _api = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _search({bool more = false}) => _request((api, valid) async {
        final page = await api.search(_title.text, _author.text,
            cursor: more ? _cursor : 0);
        if (!valid()) return;
        setState(() {
          if (!more) _results.clear();
          final ids = _results.map((row) => row['bookId']).toSet();
          _results.addAll(page.books.where((row) => ids.add(row['bookId'])));
          _cursor = page.cursor;
          _more = page.hasMore;
          _searched = true;
        });
      });

  Future<void> _choose(Map<String, dynamic> candidate) =>
      _request((api, valid) async {
        final info = await api.info(candidate['bookId'] as String);
        // Search responses may carry the documented launch link when info does not.
        for (final field in ['readerLink', 'deepLink']) {
          if (info[field] == null && candidate[field] != null) {
            info[field] = candidate[field];
          }
        }
        if (!mounted || !valid()) return;
        final confirmed = await confirmWeread(
            context,
            ModuStrings.text(context, '确认书籍版本并关联', 'Confirm edition and link'),
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ModuStrings.text(
                      context,
                      '本地书籍：${widget.title}\n作者：${widget.author}',
                      'Local book: ${widget.title}\nAuthor: ${widget.author}')),
                  const Divider(),
                  wereadPublication(context, info),
                  const SizedBox(height: 12),
                  Text(ModuStrings.text(context, "请核对书名、作者和版本后关联。",
                      "Check the title, author and edition before linking.")),
                ]));
        if (mounted && confirmed && valid()) Navigator.pop(context, info);
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Text(ModuStrings.text(context, '关联微信读书', 'Link WeRead book'))),
        body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                TextField(
                    controller: _title,
                    enabled: !_busy,
                    decoration: InputDecoration(
                        labelText: ModuStrings.text(context, '书名', 'Title')),
                    onChanged: (_) => setState(() => _more = false)),
                TextField(
                    controller: _author,
                    enabled: !_busy,
                    decoration: InputDecoration(
                        labelText: ModuStrings.text(context, '作者', 'Author')),
                    onChanged: (_) => setState(() => _more = false)),
                const SizedBox(height: 12),
                FilledButton.icon(
                    onPressed: _busy ? null : () => _search(),
                    icon: const Icon(Icons.search),
                    label: Text(
                        ModuStrings.text(context, '搜索候选书籍', 'Search books'))),
                if (_busy) Text(ModuStrings.text(context, '查询中…', 'Loading…')),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.all(12), child: Text(_error!)),
                if (_searched && _results.isEmpty)
                  Text(ModuStrings.text(context, '未找到，可修改书名或只用书名搜索。',
                      'No results. Try another title or leave the author blank.')),
                for (final info in _results)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(wereadText(info['title'])),
                    subtitle: Text([
                      wereadText(info['author']),
                      wereadText(info['publisher'])
                    ].where((s) => s.isNotEmpty).join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : () => _choose(info),
                  ),
                if (_more)
                  TextButton(
                      onPressed: _busy ? null : () => _search(more: true),
                      child:
                          Text(ModuStrings.text(context, '加载更多', 'Load more'))),
              ]),
            )),
      );
}
