import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/book.dart';
import 'package:modu_reader/service/plugins/article_capture.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/utils/get_path/get_temp_dir.dart';
import 'package:modu_reader/utils/save_file_to_download.dart';
import 'package:modu_reader/widgets/markdown/styled_markdown.dart';

Future<void> showArticleCapturePage(BuildContext context,
        {required String pluginId}) =>
    Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => ArticleCapturePage(pluginId: pluginId)));

class ArticleCapturePage extends ConsumerStatefulWidget {
  const ArticleCapturePage(
      {super.key,
      required this.pluginId,
      this.host,
      this.service,
      this.onExport,
      this.onImport});
  final String pluginId;
  final PluginHost? host;
  final ArticleCaptureService? service;
  final Future<void> Function(CapturedArticle)? onExport;
  final Future<void> Function(CapturedArticle)? onImport;

  @override
  ConsumerState<ArticleCapturePage> createState() => _ArticleCapturePageState();
}

class _ArticleCapturePageState extends ConsumerState<ArticleCapturePage>
    with WidgetsBindingObserver {
  final _url = TextEditingController();
  late final PluginHost _host = widget.host ?? PluginHost.instance;
  late final ArticleCaptureService _service =
      widget.service ?? ArticleCaptureService();
  PluginCancelToken? _cancel;
  CapturedArticle? _article;
  String? _status;
  bool _busy = false;
  bool _capturing = false;
  int _generation = 0;

  bool get _available =>
      _host.isScriptRunnable(widget.pluginId) &&
      (_host
              .manifestFor(widget.pluginId)
              ?.capabilities
              .contains(kArticleCaptureCapability) ??
          false);
  String _text(String zh, String en) => ModuStrings.text(context, zh, en);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _host.addListener(_pluginChanged);
    Prefs().addListener(_pluginChanged);
  }

  void _pluginChanged() {
    if (!mounted) return;
    if (!_available) {
      _cancel?.cancel();
      _generation++;
      _article = null;
      _busy = false;
      _capturing = false;
      _status = null;
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || !_capturing) return;
    _cancel?.cancel();
    _generation++;
    if (mounted) {
      setState(() {
        _busy = false;
        _capturing = false;
        _status = null;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    _cancel?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _host.removeListener(_pluginChanged);
    Prefs().removeListener(_pluginChanged);
    _url.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!_available || _busy) return;
    final generation = ++_generation;
    _cancel?.cancel();
    final token = _cancel = PluginCancelToken();
    setState(() {
      _busy = true;
      _capturing = true;
      _article = null;
      _status = null;
    });
    try {
      final article = await _service.fetch(_url.text.trim(), cancel: token);
      if (!mounted || generation != _generation || !_available) return;
      setState(() {
        _article = article;
      });
    } on ArticleCaptureFailure catch (error) {
      if (!mounted || generation != _generation || !_available) return;
      setState(() {
        _status = switch (error.code) {
          'url' => _text('请输入 HTTPS 网页地址。', 'Enter an HTTPS webpage address.'),
          'empty' => _text('没有找到可保存的正文。', 'No article text found.'),
          'size' => _text('网页内容过大。', 'This page is too large.'),
          'timeout' => _text('获取超时，请重试。', 'The request timed out. Try again.'),
          'cancelled' => null,
          _ => _text('无法获取网页，请检查地址后重试。',
              'Unable to capture this page. Check the address and try again.'),
        };
      });
    } catch (_) {
      if (mounted && generation == _generation && _available) {
        setState(() {
          _status =
              _text('无法获取网页，请重试。', 'Unable to capture this page. Try again.');
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _capturing = false;
        });
      }
    }
  }

  String _fileName(CapturedArticle article) {
    final title =
        article.title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
    final safe = title.isEmpty
        ? 'Article'
        : title.substring(0, title.length.clamp(0, 80));
    return '$safe-${DateTime.now().microsecondsSinceEpoch}.md';
  }

  Future<void> _save({required bool export}) async {
    final article = _article;
    if (!_available || _busy || article == null) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _status = null;
    });
    Directory? directory;
    try {
      final callback = export ? widget.onExport : widget.onImport;
      if (callback != null) {
        await callback(article);
      } else if (export) {
        await saveFileToDownload(
            bytes: utf8.encode(article.markdown),
            fileName: _fileName(article),
            mimeType: 'text/markdown');
      } else {
        directory =
            await (await getAnxTempDir()).createTemp('article-capture-');
        final file = File('${directory.path}/${_fileName(article)}');
        await file.writeAsString(article.markdown, flush: true);
        if (!mounted || generation != _generation || !_available) return;
        await importBook(file, ref);
      }
      if (!mounted || generation != _generation || !_available) return;
      setState(() {
        _status = export ? null : _text('已加入书架。', 'Added to your bookshelf.');
      });
    } catch (_) {
      if (mounted && generation == _generation && _available) {
        setState(() {
          _status = _text('保存失败，请重试。', 'Unable to save. Try again.');
        });
      }
    } finally {
      if (directory != null) {
        try {
          if (await directory.exists()) await directory.delete(recursive: true);
        } on FileSystemException {
          // The importer may already have removed its staging directory.
        }
      }
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _capturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _available;
    return Scaffold(
      appBar: AppBar(title: Text(_text('网页稍后阅读', 'Web clipper'))),
      body: !available
          ? Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_text('插件已停用。', 'This plugin is disabled.'))))
          : ListView(
              children: [
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                            key: const ValueKey('article-url'),
                            controller: _url,
                            enabled: !_busy,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.go,
                            autocorrect: false,
                            onSubmitted: (_) => unawaited(_fetch()),
                            decoration: InputDecoration(
                                labelText: _text('网页地址', 'Webpage address'),
                                hintText: 'https://',
                                border: const OutlineInputBorder())),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          FilledButton.icon(
                              key: const ValueKey('article-fetch'),
                              onPressed: _busy ? null : _fetch,
                              icon: const Icon(Icons.article_outlined),
                              label: Text(_text('获取正文', 'Capture'))),
                          if (_capturing)
                            TextButton(
                                key: const ValueKey('article-cancel'),
                                onPressed: () {
                                  _cancel?.cancel();
                                  _generation++;
                                  setState(() {
                                    _busy = false;
                                    _capturing = false;
                                    _status = null;
                                  });
                                },
                                child: Text(_text('取消', 'Cancel'))),
                          if (_article != null) ...[
                            OutlinedButton.icon(
                                key: const ValueKey('article-export'),
                                onPressed:
                                    _busy ? null : () => _save(export: true),
                                icon: const Icon(Icons.save_alt),
                                label: Text(
                                    _text('导出 Markdown', 'Export Markdown'))),
                            OutlinedButton.icon(
                                key: const ValueKey('article-import'),
                                onPressed:
                                    _busy ? null : () => _save(export: false),
                                icon: const Icon(Icons.library_add_outlined),
                                label: Text(_text('加入书架', 'Add to bookshelf'))),
                          ],
                        ]),
                        if (_busy)
                          const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: LinearProgressIndicator()),
                        if (_status != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(_status!)),
                      ],
                    )),
                if (_article != null)
                  Padding(
                      key: const ValueKey('article-preview'),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: StyledMarkdown(data: _article!.markdown)),
              ],
            ),
    );
  }
}
