import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/custom_css_profile.dart';
import 'package:modu_reader/page/settings_page/weread_settings.dart';
import 'package:modu_reader/service/weread/weread_api.dart';
import 'package:modu_reader/service/weread/weread_store.dart';
import 'package:modu_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'weread_common.dart';
import 'weread_link_page.dart';
import 'weread_info_panel.dart';

typedef AdoptWereadMetadata = Future<void> Function(
    {String? description, Uint8List? cover});

class WereadBookCard extends StatefulWidget {
  const WereadBookCard(
      {super.key,
      required this.book,
      required this.onAdopt,
      this.store,
      this.apiFactory});
  final Book book;
  final AdoptWereadMetadata onAdopt;
  final WereadStore? store;
  final WereadApi Function(String)? apiFactory;
  @override
  State<WereadBookCard> createState() => _WereadBookCardState();
}

class _WereadBookCardState extends State<WereadBookCard> {
  late final _store =
      widget.store ?? WereadStore(customCssBookKey(widget.book));
  Map<String, dynamic> _data = WereadData.empty();
  bool _busy = false, _loaded = false;
  String? _error;
  WereadApi? _api;
  int _epoch = 0;
  late String _settingsIdentity;
  final _pendingSections = <String, String>{};
  String? _autoLoading;
  String get _identity => '${Prefs().wereadEnabled}:${Prefs().wereadApiKey}';

  @override
  void initState() {
    super.initState();
    _settingsIdentity = _identity;
    Prefs().addListener(_settingsChanged);
    _read();
  }

  void _settingsChanged() {
    if (_settingsIdentity == _identity) return;
    _settingsIdentity = _identity;
    _epoch++;
    _pendingSections.clear();
    _api?.close();
    _api = null;
    setState(() {
      _busy = false;
      _error = null;
    });
    _read();
  }

  @override
  void dispose() {
    _epoch++;
    _api?.close();
    Prefs().removeListener(_settingsChanged);
    super.dispose();
  }

  Future<void> _read() async {
    final epoch = _epoch;
    try {
      final data = await _store.read();
      if (mounted && epoch == _epoch) {
        setState(() {
          _data = data;
          _loaded = true;
        });
        final info = WereadData.content(data, 'info');
        // Repair caches whose valid gateway score was discarded by older builds.
        if (info['newRating'] == null &&
            wereadInt(info['newRatingCount']) > 0) {
          _queueSection('info');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = wereadError(context, e);
        });
      }
    }
  }

  Future<void> _run(Future<void> Function(bool Function()) action) async {
    if (_busy) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(() => mounted && epoch == _epoch);
    } catch (e) {
      if (mounted && epoch == _epoch) {
        setState(() => _error = wereadError(context, e));
      }
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() => _busy = false);
        _drainSections();
      }
    }
  }

  Future<void> _network(
          Future<void> Function(WereadApi api, bool Function() valid) action) =>
      _run((valid) async {
        if (!Prefs().wereadEnabled) return;
        final key = Prefs().wereadApiKey;
        final api = _api = widget.apiFactory?.call(key) ?? WereadApi(key);
        try {
          await action(
              api,
              () =>
                  valid() &&
                  Prefs().wereadEnabled &&
                  Prefs().wereadApiKey == key);
        } finally {
          api.close();
          if (identical(_api, api)) _api = null;
        }
      });

  Future<void> _link() => _run((valid) async {
        if (!Prefs().wereadEnabled || Prefs().wereadApiKey.isEmpty) {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const WereadSettingsPage()));
          return;
        }
        final info = await Navigator.push<Map<String, dynamic>>(
            context,
            MaterialPageRoute(
                builder: (_) => WereadLinkPage(
                    title: widget.book.title,
                    author: widget.book.author,
                    apiFactory: widget.apiFactory)));
        if (info == null || !valid() || !Prefs().wereadEnabled) return;
        final data = await _store.bind(info);
        if (valid()) setState(() => _data = data);
      });

  Future<void> _unlink() => _run((valid) async {
        final confirmed = await confirmWeread(
            context,
            ModuStrings.text(context, '解除微信读书关联？', 'Unlink WeRead?'),
            Text(ModuStrings.text(context, "解除书籍关联？此操作会同步到其他设备。",
                "Unlink this book? The change will sync to other devices.")));
        if (!confirmed || !valid()) return;
        final data = await _store.bind(null);
        if (valid()) setState(() => _data = data);
      });

  void _queueSection(String name) {
    final revision = WereadData.revision(_data);
    if (revision == null ||
        _autoLoading == name ||
        !Prefs().wereadEnabled ||
        Prefs().wereadApiKey.isEmpty) {
      return;
    }
    if (name != 'info' && WereadData.content(_data, name).isNotEmpty) return;
    _pendingSections[name] = revision;
    _drainSections();
  }

  Future<void> _drainSections() async {
    if (!mounted || _busy || _autoLoading != null) return;
    while (_pendingSections.isNotEmpty) {
      final name = _pendingSections.keys.first;
      final revision = _pendingSections.remove(name)!;
      if (revision != WereadData.revision(_data) || !Prefs().wereadEnabled) {
        continue;
      }
      _autoLoading = name;
      try {
        await _load(name, expectedRevision: revision, cached: true);
      } finally {
        _autoLoading = null;
      }
      if (!mounted || _busy) return;
    }
  }

  Future<void> _load(String name,
          {bool more = false, String? expectedRevision, bool cached = false}) =>
      _network((api, valid) async {
        final fresh = await _store.read();
        final id = WereadData.bookId(fresh),
            revision = WereadData.revision(fresh);
        if (!valid() || id == null || revision == null) return;
        if (expectedRevision != null && expectedRevision != revision) return;
        final previous = WereadData.content(fresh, name);
        if (cached &&
            (name == 'info'
                ? previous['newRating'] != null
                : previous.isNotEmpty)) {
          setState(() => _data = fresh);
          return;
        }
        var content = switch (name) {
          'info' => await api.info(id),
          'highlights' => await api.highlights(id),
          _ => await api.reviews(id,
              cursor: more ? wereadInt(previous['maxIdx']) : 0,
              synckey: more ? wereadInt(previous['synckey']) : 0),
        };
        if (!valid()) return;
        if (name == 'info') {
          for (final field in ['readerLink', 'deepLink']) {
            if (content[field] == null && previous[field] != null) {
              content[field] = previous[field];
            }
          }
        }
        if (more) {
          final all = <dynamic>[...?previous['items'] as List?];
          final ids = all.map((raw) => wereadMap(raw)['id']).toSet();
          for (final raw in content['items'] as List) {
            final item = wereadMap(raw);
            if (wereadText(item['id']).isEmpty || ids.add(item['id'])) {
              all.add(item);
            }
          }
          content = {
            ...content,
            'items': all.take(200).toList(),
            'hasMore': content['hasMore'] == true &&
                all.length < 200 &&
                content['maxIdx'] != previous['maxIdx']
          };
        }
        final saved = await _store.saveSection(revision, name, content);
        if (valid()) setState(() => _data = saved);
      });

  Future<void> _adoptIntro(Map<String, dynamic> info) => _run((valid) async {
        final confirmed = await confirmWeread(
            context,
            ModuStrings.text(context, '替换本地简介？', 'Replace local description?'),
            SelectableText(wereadText(info['intro'])));
        if (confirmed && valid()) {
          await widget.onAdopt(description: wereadText(info['intro']));
        }
      });

  Future<void> _adoptCover(Map<String, dynamic> info) =>
      _network((api, valid) async {
        final bytes = await api.cover(wereadText(info['cover']));
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        ui.ImageDescriptor? descriptor;
        try {
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          if (descriptor.width > 8192 ||
              descriptor.height > 8192 ||
              descriptor.width * descriptor.height > 16000000) {
            throw const WereadException('tooLarge');
          }
        } finally {
          descriptor?.dispose();
          buffer.dispose();
        }
        if (!mounted || !valid()) return;
        final confirmed = await confirmWeread(
            context,
            ModuStrings.text(context, '替换本地封面？', 'Replace local cover?'),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Image.memory(bytes, height: 240, fit: BoxFit.contain),
              const SizedBox(height: 12),
              Text(ModuStrings.text(context, '确认后使用此封面，并沿用原有书籍同步。',
                  'Use this cover after confirmation; normal book sync applies.')),
            ]));
        if (confirmed && valid()) await widget.onAdopt(cover: bytes);
      });

  Widget _time(String name) {
    final section = WereadData.section(_data, name);
    if (section.isEmpty) return const SizedBox.shrink();
    final time =
        WereadData.updated(section).toLocal().toString().split('.').first;
    return Text(
        ModuStrings.text(
            context, '来源：微信读书 · 更新：$time', 'Source: WeRead · Updated: $time'),
        style: Theme.of(context).textTheme.bodySmall);
  }

  Widget _button(String cn, String en, VoidCallback action, {IconData? icon}) =>
      TextButton.icon(
          onPressed: _busy || !_loaded ? null : action,
          icon: Icon(icon ?? Icons.refresh, size: 18),
          label: Text(ModuStrings.text(context, cn, en)));

  Widget _section(String name, String cn, String en) {
    final data = WereadData.content(_data, name);
    final items = data['items'] as List? ?? [];
    return ExpansionTile(
      key: ValueKey('$name:${WereadData.revision(_data)}'),
      onExpansionChanged: (expanded) {
        if (expanded) {
          _queueSection(name);
        } else {
          _pendingSections.remove(name);
        }
      },
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      title: Text(ModuStrings.text(context, cn, en),
          style: Theme.of(context).textTheme.titleMedium),
      children: [
        _time(name),
        if (name == 'highlights')
          Text(
              ModuStrings.text(context, "热门划线来自微信读书。",
                  "Popular highlights are from WeRead."),
              style: Theme.of(context).textTheme.bodySmall),
        Align(
            alignment: Alignment.centerLeft,
            child: _button(data.isEmpty ? '加载' : '刷新',
                data.isEmpty ? 'Load' : 'Refresh', () => _load(name))),
        if (data.isNotEmpty && items.isEmpty)
          Text(ModuStrings.text(context, '暂无内容', 'No entries')),
        for (final raw in items)
          Builder(builder: (context) {
            final item = wereadMap(raw);
            final stars = wereadInt(item['star']);
            final date = wereadInt(item['createTime']);
            final dateText = date > 0 && date < 253402300800
                ? DateTime.fromMillisecondsSinceEpoch(date * 1000)
                    .toLocal()
                    .toIso8601String()
                    .split('T')
                    .first
                : '';
            return FilledContainer(
                radius: 16,
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (name == 'highlights')
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Icon(Icons.format_quote,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                      Text(
                          name == 'highlights'
                              ? ModuStrings.text(
                                  context,
                                  '${item['count']} 人划线',
                                  '${item['count']} highlights')
                              : '${item['author']}  ${stars >= 20 && stars <= 100 ? '${stars ~/ 20}/5 ★' : ''}  $dateText',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      SelectableText(
                          wereadText(
                              item[name == 'highlights' ? 'text' : 'content']),
                          style: Theme.of(context).textTheme.bodyMedium),
                    ]));
          }),
        if (name == 'reviews' && data['hasMore'] == true)
          _button('加载更多书评', 'More reviews', () => _load(name, more: true),
              icon: Icons.expand_more),
        if (name == 'reviews' && items.length >= 200)
          Text(ModuStrings.text(context, '已缓存 200 条书评，更多内容请在微信读书查看。',
              '200 reviews cached. Open WeRead for more.')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = WereadData.bookId(_data);
    final info = WereadData.content(_data, 'info');
    final enabled = Prefs().wereadEnabled;
    final link = wereadLink(info['readerLink']) ?? wereadLink(info['deepLink']);
    return FilledContainer(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.all(12),
        child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    ModuStrings.text(context, '微信读书 · 外部资料',
                        'WeRead · External information'),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                    ModuStrings.text(context, '与我的评分、书评分开保存',
                        'Separate from your rating and review'),
                    style: Theme.of(context).textTheme.bodySmall),
                if (!_loaded) const LinearProgressIndicator(),
                if (_busy) Text(ModuStrings.text(context, '处理中…', 'Working…')),
                if (_error != null) Text(_error!),
                if (!enabled)
                  Text(ModuStrings.text(context, '未启用，可在设置 → 外观 → 关联微信读书中开启。',
                      'Disabled. Enable in Settings → Appearance → WeRead connection.')),
                Wrap(spacing: 8, children: [
                  _button(id == null ? '关联微信读书' : '更换关联',
                      id == null ? 'Link WeRead' : 'Change link', _link,
                      icon: Icons.link),
                  if (id != null)
                    _button('解除关联', 'Unlink', _unlink, icon: Icons.link_off),
                  if (enabled && id != null)
                    _button('刷新书籍资料', 'Refresh book information',
                        () => _load('info')),
                ]),
                if (enabled && id != null) ...[
                  _time('info'),
                  const Divider(height: 32),
                  if (info.isNotEmpty) ...[
                    WereadInfoPanel(
                      info: info,
                      apiFactory: widget.apiFactory,
                      coverAction:
                          wereadLink(info['cover'], cover: true) == null
                              ? null
                              : _button(
                                  '预览并替换本地封面',
                                  'Preview and replace cover',
                                  () => _adoptCover(info),
                                  icon: Icons.image_outlined),
                      descriptionAction: wereadText(info['intro']).isEmpty
                          ? null
                          : _button('采用此简介', 'Use this description',
                              () => _adoptIntro(info),
                              icon: Icons.edit_note),
                    ),
                  ],
                  const Divider(height: 24),
                  _section('highlights', '热门划线', 'Popular highlights'),
                  const Divider(height: 24),
                  _section('reviews', '读者书评', 'Reader reviews'),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: Text(
                        ModuStrings.text(context, '在微信读书打开', 'Open in WeRead')),
                    onPressed: link == null || _busy
                        ? null
                        : () => _run((valid) async {
                              if (!await launchUrl(link,
                                  mode: LaunchMode.externalApplication)) {
                                throw const WereadException('network');
                              }
                            }),
                  ),
                  if (link == null)
                    Text(
                        ModuStrings.text(
                            context, '接口未提供跳转链接', 'No launch link provided'),
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            )));
  }
}
