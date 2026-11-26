import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/widgets/home_navigation_metrics.dart';
import 'dart:io';

import 'package:modu_reader/page/settings_page/remote_library.dart';
import 'package:modu_reader/providers/book_list.dart';
import 'package:modu_reader/providers/tb_groups.dart';
import 'package:modu_reader/service/book.dart';
import 'package:modu_reader/service/book_import_source.dart';
import 'package:modu_reader/service/folder_import_collections.dart';
import 'package:modu_reader/widgets/bookshelf/book_import_picker.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:modu_reader/utils/toast/common.dart';
import 'package:modu_reader/service/md5_service.dart';
import 'package:modu_reader/service/remote_library/ftp_connection.dart';
import 'package:modu_reader/service/remote_library/ftp_library.dart';
import 'package:modu_reader/service/remote_library/webdav_library.dart';
import 'package:modu_reader/service/remote_library/library_view_options.dart';
import 'package:modu_reader/widgets/remote_library_controls.dart';
import 'package:intl/intl.dart';
import 'package:modu_reader/utils/get_path/get_temp_dir.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RemoteLibraryPage extends ConsumerStatefulWidget {
  const RemoteLibraryPage(
      {super.key, this.clientFactory, this.ftpClientFactory});
  final WebdavLibrary Function(LibraryConnection)? clientFactory;
  final RemoteLibrary Function(FtpConnection)? ftpClientFactory;
  @override
  ConsumerState<RemoteLibraryPage> createState() => _RemoteLibraryPageState();
}

class _RemoteLibraryPageState extends ConsumerState<RemoteLibraryPage> {
  RemoteLibrary? _client;
  RemoteLibrarySource _source = RemoteLibrarySource.webdav;
  bool _initializing = true;
  int _connectionGeneration = 0;
  Uri? _directory;
  List<LibraryEntry> _entries = [];
  (List<LibraryEntry>, LibraryViewOptions, String)? _visibleKey;
  List<LibraryEntry> _visibleEntries = [];
  CancelToken? _listing, _download;
  String? _error, _activeName;
  String _filter = '';
  LibraryViewOptions _viewOptions = const LibraryViewOptions();
  bool _loading = true, _importing = false;
  int _received = 0, _total = -1;
  final _search = TextEditingController();
  final _imported = <String>{};
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  String t(String cn, String en) => zh ? cn : en;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final options = await LibraryViewOptionsStore.load();
    final source = await LibraryViewOptionsStore.loadSource();
    if (!mounted) return;
    setState(() {
      _viewOptions = options;
      _source = source;
      _initializing = false;
    });
    await _connect();
  }

  Future<void> _changeSource(RemoteLibrarySource source) async {
    if (source == _source || _activeName != null) return;
    _source = source;
    final connecting = _connect();
    try {
      await LibraryViewOptionsStore.saveSource(source);
    } catch (_) {
      _message(t('无法保存书库来源。', 'Could not save the library source.'));
    }
    await connecting;
  }

  Future<void> _changeViewOptions(LibraryViewOptions options) async {
    setState(() => _viewOptions = options);
    try {
      await LibraryViewOptionsStore.save(options);
    } catch (_) {
      if (!mounted) return;
      _message(ModuStrings.text(context, '排序已生效，但无法保存到本机。',
          'Sorting applied, but preferences could not be saved.'));
    }
  }

  Future<void> _connect() async {
    final generation = ++_connectionGeneration;
    _listing?.cancel();
    _client?.close();
    _client = null;
    setState(() {
      _loading = true;
      _entries = [];
      _directory = null;
      _error = null;
    });
    try {
      switch (_source) {
        case RemoteLibrarySource.webdav:
          final connection = await LibraryConnectionStore.load();
          if (!mounted || generation != _connectionGeneration) return;
          if (connection != null) {
            _client = widget.clientFactory?.call(connection) ??
                WebdavLibrary(connection);
          }
        case RemoteLibrarySource.ftp:
          final connection = await FtpConnectionStore.load();
          if (!mounted || generation != _connectionGeneration) return;
          if (connection != null) {
            _client = widget.ftpClientFactory?.call(connection) ??
                FtpLibrary(connection.root,
                    username: connection.username,
                    password: connection.password);
          }
      }
      if (_client == null) {
        setState(() => _loading = false);
      } else {
        await _browse(_client!.root);
      }
    } catch (error) {
      if (mounted && generation == _connectionGeneration) {
        setState(() {
          _loading = false;
          _error = _libraryError(error, listing: true);
        });
      }
    }
  }

  Future<void> _browse(Uri directory) async {
    _listing?.cancel();
    final token = CancelToken();
    _listing = token;
    setState(() {
      _loading = true;
      _error = null;
      _directory = directory;
      _entries = [];
    });
    try {
      final entries = await _client!.list(directory, cancelToken: token);
      if (!mounted || token.isCancelled) return;
      setState(() {
        _entries = entries;
        _directory = directory;
      });
    } catch (error) {
      if (!mounted || token.isCancelled) return;
      AnxLog.warning('Remote library listing failed: ${error.runtimeType}'
          '${error is LibraryListingException ? ' (${error.reason})' : ''}'
          '${error is FtpLibraryException ? ' (${error.failure.name})' : ''}'
          '${error is DioException ? ', HTTP ${error.response?.statusCode}' : ''}');
      setState(() => _error = _libraryError(error, listing: true));
    } finally {
      if (mounted && !token.isCancelled) setState(() => _loading = false);
    }
  }

  Future<void> _settings() async {
    final source = _source;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => Scaffold(
                appBar: AppBar(
                    title: Text(ModuStrings.text(
                        context, '远程书库设置', 'Remote library settings'))),
                body: RemoteLibrarySettings(initialSource: source))));
    if (mounted) await _connect();
  }

  void _message(String value) {
    if (mounted) AnxToast.show(value, context: context);
  }

  String _libraryError(Object error, {bool listing = false}) =>
      _source == RemoteLibrarySource.ftp
          ? ftpLibraryError(error, zh, listing: listing)
          : libraryError(error, zh, listing: listing);

  Future<void> _getBook(LibraryEntry entry) async {
    if (_activeName != null) return;
    final token = CancelToken();
    _download = token;
    setState(() {
      _activeName = entry.name;
      _received = 0;
      _total = -1;
    });
    try {
      final added = await _importEntry(entry, _client!, token);
      if (!mounted) return;
      _message(added
          ? t('已下载并导入本地书架。', 'Downloaded and imported to your bookshelf.')
          : t('书架中已存在这本书，无需重复导入。',
              'This book is already available on your bookshelf.'));
    } catch (error) {
      if (!mounted) return;
      _message(token.isCancelled
          ? t('下载已取消。', 'Download cancelled.')
          : _importing
              ? t('文件已下载，但书籍解析失败。请检查格式、是否加密或文件是否损坏。',
                  'Download completed, but import failed. Check the format, encryption or file integrity.')
              : _libraryError(error));
    } finally {
      if (mounted) {
        setState(() {
          _activeName = null;
          _importing = false;
          _download = null;
        });
      }
    }
  }

  Future<bool> _importEntry(
      LibraryEntry entry, RemoteLibrary client, CancelToken token,
      {FolderImportCollections? collections, String? collectionName}) async {
    final container = ProviderScope.containerOf(context, listen: false);
    Directory? temporary;
    try {
      temporary = await (await getAnxTempDir()).createTemp('modu-remote-');
      // URI-derived immediate-child names are checked by the service, and the
      // unique staging directory prevents clobbering a user's local book.
      final localName =
          entry.name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
      final file = File('${temporary.path}/$localName');
      final progressClock = Stopwatch()..start();
      await client.download(entry, file, token, (received, total) {
        if (mounted &&
            (progressClock.elapsedMilliseconds >= 100 || received == total)) {
          progressClock.reset();
          setState(() {
            _received = received;
            _total = total;
          });
        }
      });
      if (!mounted || token.isCancelled) throw StateError('Cancelled');
      setState(() => _importing = true);
      final hash = await MD5Service.calculateFileMd5(file.path);
      if (!mounted) throw StateError('Cancelled');
      final duplicate =
          hash == null ? null : await MD5Service.checkDuplicateByMd5(hash);
      if (!mounted) throw StateError('Cancelled');
      final alreadyPresent = duplicate != null &&
          !duplicate.isDeleted &&
          File(duplicate.fileFullPath).existsSync();
      if (!alreadyPresent) {
        await importBook(
          file,
          ref,
          collections: collections,
          collectionName: collectionName,
          onImported: () {
            if (collections != null && collectionName != null) {
              container.invalidate(groupDaoProvider);
            }
            container.read(bookListProvider.notifier).refresh();
          },
        );
      }
      if (mounted) setState(() => _imported.add(entry.uri.toString()));
      return !alreadyPresent;
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    }
  }

  Future<void> _getFolder(Uri directory) async {
    if (_activeName != null) return;
    final client = _client!;
    final token = CancelToken();
    _download = token;
    setState(() {
      _activeName = t('扫描文件夹（含子文件夹）', 'Scanning folder (including subfolders)');
      _received = 0;
      _total = -1;
    });
    var added = 0, skipped = 0, failed = 0;
    String? lastFailure;
    try {
      final entries = await client.discoverBooks(directory, cancelToken: token);
      if (!mounted || token.isCancelled) return;
      if (entries.isEmpty) {
        _message(t('没有找到支持的书籍文件', 'No supported books found'));
        return;
      }
      final byId = {for (final e in entries) e.uri.toString(): e};
      final segments = directory.pathSegments;
      final depth = segments.length - (segments.lastOrNull == '' ? 1 : 0);
      final selection = await showDialog<BookImportSelectionResult>(
          context: context,
          animationStyle: AppMotion.style,
          builder: (_) => BookImportSelection(
              allowCollections: true,
              entries: entries.map((entry) {
                final relativePath =
                    entry.uri.pathSegments.skip(depth).toList();
                return BookImportEntry(
                    id: entry.uri.toString(),
                    name: entry.name,
                    label: relativePath.join('/'),
                    collectionName:
                        relativePath.length > 1 ? relativePath.first : null);
              }).toList()));
      if (selection == null || !mounted || token.isCancelled) return;
      final selected = selection.entries;
      final collections =
          selection.createCollections ? FolderImportCollections() : null;
      for (var i = 0; i < selected.length; i++) {
        if (!mounted || token.isCancelled) break;
        final item = selected[i];
        final entry = byId[item.id]!;
        setState(() {
          _activeName = '${i + 1}/${selected.length} · ${entry.name}';
          _received = 0;
          _total = -1;
          _importing = false;
        });
        try {
          if (await _importEntry(entry, client, token,
              collections: collections, collectionName: item.collectionName)) {
            added++;
          } else {
            skipped++;
          }
        } catch (error) {
          if (token.isCancelled || !mounted) break;
          failed++;
          lastFailure = _importing
              ? t('书籍解析失败', 'Book import failed')
              : _libraryError(error);
        }
      }
      if (mounted) {
        _message(t(
            '${token.isCancelled ? '已取消。' : ''}导入 $added 本，重复跳过 $skipped 本，失败 $failed 本。${lastFailure ?? ''}',
            '${token.isCancelled ? 'Cancelled. ' : ''}Imported $added, skipped $skipped duplicates, failed $failed. ${lastFailure ?? ''}'));
      }
    } catch (error) {
      if (mounted) {
        _message(token.isCancelled
            ? t('已取消文件夹扫描。', 'Folder scan cancelled.')
            : _libraryError(error, listing: true));
      }
    } finally {
      if (mounted) {
        setState(() {
          _activeName = null;
          _importing = false;
          _download = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _listing?.cancel();
    _download?.cancel();
    _client?.close();
    _search.dispose();
    super.dispose();
  }

  String _size(int? bytes) => bytes == null
      ? '—'
      : bytes < 1024
          ? '$bytes B'
          : bytes < 1024 * 1024
              ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
              : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

  String _entrySubtitle(LibraryEntry entry) {
    final info = entry.isDirectory
        ? ModuStrings.text(context, '文件夹', 'Folder')
        : '${_size(entry.size)}${entry.isBook ? '' : ModuStrings.text(context, ' · 不支持导入', ' · Import not supported')}';
    final date = switch (_viewOptions.sort) {
      LibrarySortField.createdAt => entry.createdAt,
      LibrarySortField.modifiedAt => entry.modifiedAt,
      _ => null,
    };
    if (_viewOptions.sort != LibrarySortField.createdAt &&
        _viewOptions.sort != LibrarySortField.modifiedAt) {
      return info;
    }
    final label = _viewOptions.sort == LibrarySortField.createdAt
        ? ModuStrings.text(context, '添加', 'Added')
        : ModuStrings.text(context, '修改', 'Modified');
    return '$info · $label: ${date == null ? ModuStrings.text(context, '未提供', 'Not provided') : DateFormat('yyyy-MM-dd HH:mm').format(date.toLocal())}';
  }

  @override
  Widget build(BuildContext context) {
    final directory = _directory;
    final root = _client?.root;
    final visibleKey = (_entries, _viewOptions, _filter);
    // Download progress must not re-sort a large directory on every repaint.
    if (_visibleKey != visibleKey) {
      _visibleKey = visibleKey;
      _visibleEntries = _viewOptions.apply(_entries, query: _filter);
    }
    final visible = _visibleEntries;
    return Scaffold(
        appBar: AppBar(
            title: Text(ModuStrings.text(context, '远程书库', 'Remote library')),
            actions: [
              PopupMenuButton<RemoteLibrarySource>(
                tooltip: t('书库来源', 'Library source'),
                enabled: !_initializing && _activeName == null,
                onSelected: _changeSource,
                itemBuilder: (_) => [
                  for (final source in RemoteLibrarySource.values)
                    CheckedPopupMenuItem(
                        value: source,
                        checked: source == _source,
                        child: Text(source.label)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_source.label),
                    const Icon(Icons.arrow_drop_down, size: 18),
                  ]),
                ),
              ),
              IconButton(
                  tooltip: t('导入当前文件夹', 'Import current folder'),
                  onPressed: _loading ||
                          _error != null ||
                          directory == null ||
                          _activeName != null
                      ? null
                      : () => _getFolder(directory),
                  icon: const Icon(Icons.drive_folder_upload_outlined)),
              IconButton(
                  tooltip: ModuStrings.text(context, '刷新', 'Refresh'),
                  onPressed: _loading
                      ? null
                      : () =>
                          directory == null ? _connect() : _browse(directory),
                  icon: const Icon(Icons.refresh)),
              IconButton(
                  tooltip: ModuStrings.text(
                      context, '远程书库设置', 'Remote library settings'),
                  onPressed:
                      !_initializing && _activeName == null ? _settings : null,
                  icon: const Icon(Icons.settings_outlined)),
            ]),
        body: Column(children: [
          if (root != null)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  IconButton(
                      tooltip:
                          ModuStrings.text(context, '上一级', 'Parent folder'),
                      icon: const Icon(Icons.arrow_upward),
                      onPressed:
                          _loading || directory == null || directory == root
                              ? null
                              : () => _browse(directory.resolve('../'))),
                  TextButton(
                      onPressed: _loading ? null : () => _browse(root),
                      child: Text(ModuStrings.text(context, '根目录', 'Root'))),
                  Expanded(
                      child: SelectableText(
                          directory == null
                              ? '/'
                              : '/${directory.pathSegments.skip(root.pathSegments.where((segment) => segment.isNotEmpty).length).join('/')}',
                          maxLines: 2)),
                ])),
          if (root != null)
            Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                    controller: _search,
                    onChanged: (value) => setState(() => _filter = value),
                    decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: ModuStrings.text(context, '筛选当前目录中的文件',
                            'Filter files in this folder'),
                        border: const OutlineInputBorder()))),
          if (root != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: RemoteLibraryControls(
                  options: _viewOptions, onChanged: _changeViewOptions),
            ),
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
                        child: Text(ModuStrings.text(context, '取消', 'Cancel')))
                  ]),
                  EinkStaticIndicator(
                      child: LinearProgressIndicator(
                          value: _importing || _total <= 0
                              ? null
                              : (_received / _total).clamp(0, 1))),
                ])),
          Expanded(
              child: _loading
                  ? const Center(
                      child: EinkStaticIndicator(
                          child: CircularProgressIndicator()))
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
                                        onPressed: _activeName == null
                                            ? _settings
                                            : null,
                                        child: Text(ModuStrings.text(
                                            context,
                                            '检查连接设置',
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
                                      ModuStrings.text(
                                          context,
                                          '连接 ${_source.label} 后可浏览和下载书籍。',
                                          'Connect ${_source.label} to browse and download books.'),
                                      textAlign: TextAlign.center),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                      onPressed: _settings,
                                      child: Text(ModuStrings.text(
                                          context,
                                          '配置书库 ${_source.label}',
                                          'Configure library ${_source.label}')))
                                ]))
                          : visible.isEmpty
                              ? Center(
                                  child: Text(ModuStrings.text(
                                      context,
                                      '当前目录没有匹配的文件。',
                                      'No matching files in this folder.')))
                              : ListView.builder(
                                  padding: EdgeInsets.only(
                                      bottom: 12 +
                                          MediaQuery.paddingOf(context).bottom +
                                          (_activeName == null
                                              ? HomeNavigationClearance.of(
                                                  context)
                                              : 0)),
                                  itemCount: visible.length,
                                  itemBuilder: (context, index) {
                                    final entry = visible[index];
                                    final imported = _imported
                                        .contains(entry.uri.toString());
                                    return ListTile(
                                        key: ValueKey(
                                            'library-entry:${entry.uri}'),
                                        leading: Icon(entry.isDirectory
                                            ? Icons.folder_outlined
                                            : entry.isBook
                                                ? Icons.menu_book_outlined
                                                : Icons
                                                    .insert_drive_file_outlined),
                                        title: Text(entry.name),
                                        subtitle: Text(_entrySubtitle(entry)),
                                        onTap: entry.isDirectory
                                            ? () => _browse(entry.uri)
                                            : null,
                                        trailing: entry.isDirectory
                                            ? Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                    IconButton(
                                                        tooltip: t('导入文件夹',
                                                            'Import folder'),
                                                        onPressed: _activeName ==
                                                                null
                                                            ? () => _getFolder(
                                                                entry.uri)
                                                            : null,
                                                        icon: const Icon(Icons
                                                            .download_outlined)),
                                                    const Icon(
                                                        Icons.chevron_right),
                                                  ])
                                            : !entry.isBook
                                                ? null
                                                : IconButton(
                                                    tooltip: imported
                                                        ? ModuStrings.text(
                                                            context,
                                                            '本次已导入',
                                                            'Imported this session')
                                                        : ModuStrings.text(
                                                            context,
                                                            '下载并导入书架',
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
                padding: EdgeInsets.fromLTRB(
                    8, 8, 8, 8 + HomeNavigationClearance.of(context)),
                child: SettingHelp(
                    title: Text(ModuStrings.text(context, "下载", "Download")),
                    description: Text(
                        ModuStrings.text(context, "下载完成前请保持此页打开。",
                            "Keep this page open until the download finishes."),
                        style: Theme.of(context).textTheme.bodySmall))),
        ]));
  }
}
