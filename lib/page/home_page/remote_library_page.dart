import 'dart:io';

import 'package:anx_reader/page/settings_page/remote_library.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/md5_service.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RemoteLibraryPage extends ConsumerStatefulWidget {
  const RemoteLibraryPage({super.key});
  @override
  ConsumerState<RemoteLibraryPage> createState() => _RemoteLibraryPageState();
}

class _RemoteLibraryPageState extends ConsumerState<RemoteLibraryPage> {
  WebdavLibrary? _client;
  Uri? _directory;
  List<LibraryEntry> _entries = [];
  CancelToken? _listing, _download;
  String? _error, _activeName;
  String _filter = '';
  bool _loading = true, _importing = false;
  int _received = 0, _total = -1;
  final _imported = <String>{};
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  String t(String cn, String en) => zh ? cn : en;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final connection = await LibraryConnectionStore.load();
    if (!mounted) return;
    _listing?.cancel();
    _client?.close();
    _client = null;
    setState(() {
      _entries = [];
      _directory = null;
      _error = null;
    });
    if (connection == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      _client = WebdavLibrary(connection);
      await _browse(_client!.root);
    } catch (error) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = libraryError(error, zh);
        });
    }
  }

  Future<void> _browse(Uri directory) async {
    _listing?.cancel();
    final token = CancelToken();
    _listing = token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _client!.list(directory, cancelToken: token);
      if (!mounted || token.isCancelled) return;
      setState(() {
        _entries = entries;
        _directory = directory;
      });
    } catch (error) {
      if (mounted && !token.isCancelled)
        setState(() => _error = libraryError(error, zh));
    } finally {
      if (mounted && !token.isCancelled) setState(() => _loading = false);
    }
  }

  Future<void> _settings() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => Scaffold(
                appBar: AppBar(title: Text(t('书库 WebDAV', 'Library WebDAV'))),
                body: const RemoteLibrarySettings())));
    if (mounted) await _connect();
  }

  void _message(String value) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _getBook(LibraryEntry entry) async {
    if (_activeName != null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final token = CancelToken();
    _download = token;
    setState(() {
      _activeName = entry.name;
      _received = 0;
      _total = -1;
    });
    Directory? temporary;
    try {
      temporary = await (await getAnxTempDir()).createTemp('modu-webdav-');
      // URI-derived immediate-child names are checked by the service, and the
      // unique staging directory prevents clobbering a user's local book.
      final localName =
          entry.name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
      final file = File('${temporary.path}/$localName');
      await _client!.download(entry, file, token, (received, total) {
        if (mounted)
          setState(() {
            _received = received;
            _total = total;
          });
      });
      if (!mounted || token.isCancelled) return;
      setState(() => _importing = true);
      final hash = await MD5Service.calculateFileMd5(file.path);
      if (!mounted) return;
      final duplicate =
          hash == null ? null : await MD5Service.checkDuplicateByMd5(hash);
      if (!mounted) return;
      if (duplicate != null &&
          !duplicate.isDeleted &&
          File(duplicate.fileFullPath).existsSync()) {
        _message(t('书架中已存在这本书，无需重复导入。',
            'This book is already available on your bookshelf.'));
      } else {
        await importBook(file, ref,
            onImported: () =>
                container.read(bookListProvider.notifier).refresh());
        _message(
            t('已下载并导入本地书架。', 'Downloaded and imported to your bookshelf.'));
      }
      if (mounted) setState(() => _imported.add(entry.uri.toString()));
    } catch (error) {
      if (mounted)
        _message(token.isCancelled
            ? t('下载已取消。', 'Download cancelled.')
            : _importing
                ? t('文件已下载，但书籍解析失败。请检查格式、是否加密或文件是否损坏。',
                    'Download completed, but import failed. Check the format, encryption or file integrity.')
                : libraryError(error, zh));
    } finally {
      if (temporary != null && await temporary.exists())
        await temporary.delete(recursive: true);
      if (mounted)
        setState(() {
          _activeName = null;
          _importing = false;
          _download = null;
        });
    }
  }

  @override
  void dispose() {
    _listing?.cancel();
    _download?.cancel();
    _client?.close();
    super.dispose();
  }

  String _size(int? bytes) => bytes == null
      ? '—'
      : bytes < 1024
          ? '$bytes B'
          : bytes < 1024 * 1024
              ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
              : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

  @override
  Widget build(BuildContext context) {
    final directory = _directory;
    final root = _client?.root;
    final visible = _entries
        .where((e) => e.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return Scaffold(
        appBar: AppBar(title: Text(t('远程书库', 'Remote library')), actions: [
          IconButton(
              tooltip: t('刷新', 'Refresh'),
              onPressed: _loading
                  ? null
                  : () => directory == null ? _connect() : _browse(directory),
              icon: const Icon(Icons.refresh)),
          IconButton(
              tooltip: t('书库 WebDAV 设置', 'Library WebDAV settings'),
              onPressed: _activeName == null ? _settings : null,
              icon: const Icon(Icons.settings_outlined)),
        ]),
        body: Column(children: [
          if (root != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  IconButton(
                      tooltip: t('上一级', 'Parent folder'),
                      icon: const Icon(Icons.arrow_upward),
                      onPressed:
                          _loading || directory == null || directory == root
                              ? null
                              : () => _browse(directory.resolve('../'))),
                  TextButton(
                      onPressed: _loading ? null : () => _browse(root),
                      child: Text(t('根目录', 'Root'))),
                  Expanded(
                      child: SelectableText(
                          directory == null
                              ? '/'
                              : '/${directory.pathSegments.skip(root.pathSegments.length - 1).join('/')}',
                          maxLines: 2)),
                ])),
          if (root != null)
            Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                    onChanged: (value) => setState(() => _filter = value),
                    decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText:
                            t('筛选当前目录中的文件', 'Filter files in this folder'),
                        border: const OutlineInputBorder()))),
          if (_activeName != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Text(_importing
                            ? t('正在导入：$_activeName', 'Importing: $_activeName')
                            : '$_activeName · ${_size(_received)} / ${_size(_total < 0 ? null : _total)}')),
                    TextButton(
                        onPressed:
                            _importing ? null : () => _download?.cancel(),
                        child: Text(t('取消', 'Cancel')))
                  ]),
                  LinearProgressIndicator(
                      value: _importing || _total <= 0
                          ? null
                          : (_received / _total).clamp(0, 1)),
                ])),
          Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_error!),
                                    const SizedBox(height: 16),
                                    OutlinedButton(
                                        onPressed: _settings,
                                        child: Text(t('检查连接设置',
                                            'Check connection settings')))
                                  ])))
                      : root == null
                          ? Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                  const Icon(Icons.folder_open_outlined,
                                      size: 64),
                                  const SizedBox(height: 16),
                                  Text(
                                      t('连接 WebDAV，浏览远程目录并将书籍下载到本地书架。',
                                          'Connect WebDAV to browse and import books into your local bookshelf.'),
                                      textAlign: TextAlign.center),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                      onPressed: _settings,
                                      child: Text(t('配置书库 WebDAV',
                                          'Configure library WebDAV')))
                                ]))
                          : visible.isEmpty
                              ? Center(
                                  child: Text(t('当前目录没有匹配的文件。',
                                      'No matching files in this folder.')))
                              : ListView.builder(
                                  padding: const EdgeInsets.only(bottom: 96),
                                  itemCount: visible.length,
                                  itemBuilder: (context, index) {
                                    final entry = visible[index];
                                    final imported = _imported
                                        .contains(entry.uri.toString());
                                    return ListTile(
                                        leading: Icon(entry.isDirectory
                                            ? Icons.folder_outlined
                                            : entry.isBook
                                                ? Icons.menu_book_outlined
                                                : Icons
                                                    .insert_drive_file_outlined),
                                        title: Text(entry.name),
                                        subtitle: Text(entry.isDirectory
                                            ? t('文件夹', 'Folder')
                                            : '${_size(entry.size)}${entry.isBook ? '' : t(' · 不支持导入', ' · Import not supported')}'),
                                        onTap: entry.isDirectory
                                            ? () => _browse(entry.uri)
                                            : null,
                                        trailing: entry.isDirectory
                                            ? const Icon(Icons.chevron_right)
                                            : !entry.isBook
                                                ? null
                                                : IconButton(
                                                    tooltip: imported
                                                        ? t('本次已导入',
                                                            'Imported this session')
                                                        : t('下载并导入书架',
                                                            'Download and import'),
                                                    onPressed: _activeName !=
                                                                null ||
                                                            imported
                                                        ? null
                                                        : () => _getBook(entry),
                                                    icon: Icon(imported
                                                        ? Icons
                                                            .check_circle_outline
                                                        : Icons
                                                            .download_outlined)));
                                  })),
          if (_activeName != null)
            Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                    t('下载期间离开此标签页会取消下载；导入开始后请等待完成。',
                        'Leaving this tab cancels a download; please wait once import starts.'),
                    style: Theme.of(context).textTheme.bodySmall)),
        ]));
  }
}
