import 'dart:async';
import 'dart:io' as io;
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/models/sync_state_model.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/utils/get_path/get_cache_dir.dart';
import 'package:anx_reader/service/sync/ai_settings_sync.dart';
import 'package:anx_reader/service/database_sync_manager.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'sync.g.dart';

@Riverpod(keepAlive: true)
class Sync extends _$Sync {
  static final Sync _instance = Sync._internal();

  factory Sync() {
    return _instance;
  }

  Sync._internal();

  bool _syncRunning = false;

  @override
  SyncStateModel build() {
    return const SyncStateModel(
      direction: SyncDirection.both,
      isSyncing: false,
      total: 0,
      count: 0,
      fileName: '',
    );
  }

  void changeState(SyncStateModel s) {
    state = s;
  }

  SyncClientBase? get _syncClient {
    if (SyncClientFactory.currentClient == null) {
      SyncClientFactory.initializeCurrentClient();
    }
    return SyncClientFactory.currentClient;
  }

  Future<void> init() async {
    final client = _syncClient;
    if (client == null) {
      AnxLog.severe('No sync client configured');
      return;
    }

    AnxLog.info('${client.protocolName}: init');
  }

  Future<void> _createSyncDir() async {
    final client = _syncClient;
    if (client == null) return;

    for (final directory in [SyncPaths.books, SyncPaths.covers]) {
      if (!await client.isExist('$directory/')) {
        await client.mkdirAll(directory);
      }
    }
  }

  Future<bool> shouldSync() async {
    if (!Prefs().webdavStatus) {
      return false;
    }

    if (Prefs().onlySyncWhenWifi &&
        !(await Connectivity().checkConnectivity())
            .contains(ConnectivityResult.wifi)) {
      if (Prefs().syncCompletedToast) {
        AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavOnlyWifi);
      }
      return false;
    }

    return true;
  }

  Future<void> _showDatabaseVersionMismatchDialog(int remoteVersion) async {
    await SmartDialog.show(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: Text(L10n.of(context).webdavSyncAborted),
        content: Text(
            L10n.of(context).syncMismatchTip(currentDbVersion, remoteVersion)),
        actions: [
          TextButton(
            onPressed: () {
              SmartDialog.dismiss();
            },
            child: Text(L10n.of(context).commonOk),
          ),
        ],
      ),
    );
  }

  Future<void> syncData(
    SyncDirection direction,
    WidgetRef? ref, {
    SyncTrigger trigger = SyncTrigger.auto,
  }) async {
    // Covers preflight and direction selection as well as byte transfer.
    if (_syncRunning) return;
    _syncRunning = true;
    try {
      await _syncData(direction, ref, trigger: trigger);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      AnxToast.show(status == 401 || status == 403
          ? 'WebDAV 账号或目录权限校验失败，请检查手机端配置。'
          : 'WebDAV 请求失败，请检查网络和服务器；未将失败当作空书库处理。');
      AnxLog.warning('Sync preflight failed: ${e.type.name}, HTTP $status');
    } catch (e) {
      AnxToast.show('同步未完成：$e');
    } finally {
      _syncRunning = false;
      changeState(state.copyWith(isSyncing: false));
    }
  }

  Future<void> _syncData(
    SyncDirection direction,
    WidgetRef? ref, {
    SyncTrigger trigger = SyncTrigger.auto,
  }) async {
    final client = _syncClient;
    if (client == null) {
      AnxLog.info('No sync client configured');
      return;
    }

    if (trigger == SyncTrigger.auto && !Prefs().autoSync) {
      return;
    }

    if (!(await shouldSync())) {
      return;
    }

    // Do not overlap a library sync with an active file transfer.
    if (state.isSyncing) {
      AnxLog.info('Sync already in progress, skipping');
      return;
    }

    // Fail visibly without treating authentication/network errors as absence.
    await client.ping();
    await _createSyncDir();

    AnxLog.info('Sync ping success');

    // Materialize the selected AI service settings into the database before
    // comparing timestamps. This makes API-key changes participate in the
    // existing WebDAV database conflict flow without storing plaintext keys.
    try {
      await AiSettingsSyncService().prepareLocalDatabase(
        enabled: Prefs().syncAiSettingsToWebdav,
        password: Prefs().syncAiSettingsEncryptionPassword,
      );
    } on AiSyncPasswordMissingException catch (e) {
      AnxToast.show(e.toString());
      AnxLog.warning('AI settings sync skipped: encryption password missing');
      return;
    } catch (e) {
      AnxToast.show('AI 设置加密失败，本次同步已取消');
      AnxLog.severe('Failed to prepare encrypted AI settings for sync: $e');
      return;
    }

    // Reject future formats. Never guess which whole database should win.
    final remoteFiles = await client.safeReadDir(SyncPaths.root);
    for (final file in remoteFiles) {
      final match = RegExp(r'^database(\d+)\.db$').firstMatch(file.name ?? '');
      if (match != null && int.parse(match.group(1)!) > currentDbVersion) {
        await _showDatabaseVersionMismatchDialog(int.parse(match.group(1)!));
        return;
      }
    }
    changeState(state.copyWith(isSyncing: true));

    if (Prefs().syncCompletedToast) {
      AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavSyncing);
    }

    try {
      await syncDatabase(direction);

      if (Prefs().syncCompletedToast) {
        AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavSyncingFiles);
      }

      await syncFiles();

      imageCache.clear();
      imageCache.clearLiveImages();

      try {
        this.ref.read(bookListProvider.notifier).refresh();
        this.ref.read(groupDaoProvider.notifier).refresh();
      } catch (e) {
        AnxLog.info('Failed to refresh book list: $e');
      }

      // Backup cleanup is now handled by DatabaseSyncManager

      if (Prefs().syncCompletedToast) {
        AnxToast.show(L10n.of(navigatorKey.currentContext!).webdavSyncComplete);
      }
    } catch (e, s) {
      if (e is DioException && e.type == DioExceptionType.connectionError) {
        AnxToast.show('Sync connection failed, check your network');
        AnxLog.severe('Sync connection failed, connection error\n$e, $s');
      } else {
        AnxToast.show('Sync failed\n$e');
        AnxLog.severe('Sync failed\n$e, $s');
      }
    } finally {
      changeState(state.copyWith(isSyncing: false));
      // _deleteBackUpDb();
    }
  }

  Future<void> syncFiles() async {
    final client = _syncClient;
    if (client == null) return;

    AnxLog.info('Sync: syncFiles');
    List<String> currentBooks = await bookDao.getCurrentBooks();
    List<String> currentCover =
        (await bookDao.getCurrentCover()).where((p) => p.isNotEmpty).toList();

    List<String> remoteBooksName = [];
    List<String> remoteCoversName = [];

    List<RemoteFile> remoteBooks = await client.safeReadDir(SyncPaths.books);
    remoteBooksName = List.generate(
        remoteBooks.length, (index) => 'file/${remoteBooks[index].name!}');

    List<RemoteFile> remoteCovers = await client.safeReadDir(SyncPaths.covers);
    remoteCoversName = List.generate(
        remoteCovers.length, (index) => 'cover/${remoteCovers[index].name!}');

    final localBooks = io.Directory(getBasePath('file'))
        .listSync()
        .whereType<io.File>()
        .map((e) => 'file/${basename(e.path)}')
        .toList();

    // Sync cover files
    for (var file in currentCover) {
      if (!remoteCoversName.contains(file) &&
          io.File(getBasePath(file)).existsSync()) {
        await uploadFile(getBasePath(file), SyncPaths.data(file));
      }
      if (!io.File(getBasePath(file)).existsSync() &&
          remoteCoversName.contains(file)) {
        await downloadFile(SyncPaths.data(file), getBasePath(file));
      }
    }

    // Sync book files
    for (var file in currentBooks) {
      if (!remoteBooksName.contains(file) && localBooks.contains(file)) {
        await uploadFile(getBasePath(file), SyncPaths.data(file));
      }
    }

    // Do not garbage-collect by absence: an offline/concurrent device can
    // still reference these files. Deletions are synchronized as tombstones;
    // physical file reclamation needs a separately acknowledged GC protocol.
    ref.read(syncStatusProvider.notifier).refresh();
  }

  Future<void> syncDatabase(SyncDirection direction) async {
    final client = _syncClient;
    if (client == null) return;
    // Existing upload/download callers now converge records safely in both
    // directions; no entry point may overwrite a whole live library.
    await RowSyncEngine(
      store: RowSyncStore(await DBHelper().database),
      client: client,
      cache: await getAnxCacheDir(),
      beforePublish: syncFiles,
      beforeMerge: _createMergeBackup,
    ).synchronize();
    await _restoreAiSettingsAfterDatabaseDownload();
    final metadata = await client.readProps(RowSyncEngine.remotePath);
    if (metadata?.mTime != null) Prefs().lastUploadBookDate = metadata!.mTime;
  }

  Future<void> _createMergeBackup() async {
    final snapshot = await DBHelper.prepareUploadSnapshot();
    final cache = await getAnxCacheDir();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    await io.File(snapshot)
        .rename(join(cache.path, 'backup_database_$timestamp.db'));
    await DatabaseSyncManager.pruneBackups();
  }

  Future<void> _restoreAiSettingsAfterDatabaseDownload() async {
    final restored =
        await AiSettingsSyncService().restoreFromDownloadedDatabase(
      enabled: Prefs().syncAiSettingsToWebdav,
      password: Prefs().syncAiSettingsEncryptionPassword,
    );
    if (restored) {
      ref.read(aiProvidersProvider.notifier).refresh();
    }
  }

  Future<void> uploadFile(
    String localPath,
    String remotePath, [
    bool replace = true,
  ]) async {
    changeState(state.copyWith(
      direction: SyncDirection.upload,
      fileName: localPath.split('/').last,
    ));

    final client = _syncClient;
    if (client != null) {
      final status = ref.read(syncStatusProvider.notifier);
      var completed = false;
      await status.addUploading(remotePath);
      try {
        await client.uploadFile(
          localPath,
          remotePath,
          replace: replace,
          onProgress: (sent, total) {
            changeState(state.copyWith(
              isSyncing: true,
              count: sent,
              total: total,
            ));
          },
        );
        completed = true;
      } finally {
        changeState(state.copyWith(isSyncing: false));
        await status.removeUploading(remotePath, completed: completed);
      }
    }

    changeState(state.copyWith(isSyncing: false));
  }

  Future<void> downloadFile(String remotePath, String localPath) async {
    changeState(state.copyWith(
      direction: SyncDirection.download,
      fileName: remotePath.split('/').last,
    ));

    final client = _syncClient;
    if (client != null) {
      final status = ref.read(syncStatusProvider.notifier);
      var completed = false;
      await status.addDownloading(remotePath);
      try {
        await client.downloadFile(
          remotePath,
          localPath,
          onProgress: (received, total) {
            changeState(state.copyWith(
              isSyncing: true,
              count: received,
              total: total,
            ));
          },
        );
        completed = true;
      } finally {
        changeState(state.copyWith(isSyncing: false));
        await status.removeDownloading(remotePath, completed: completed);
      }
    }

    changeState(state.copyWith(isSyncing: false));
  }

  Future<List<String>> listRemoteBookFiles() async {
    final client = _syncClient;
    if (client == null) return [];

    final remoteFiles = await client.safeReadDir(SyncPaths.books);
    return remoteFiles.map((e) => e.name!).toList();
  }

  Future<void> downloadBook(Book book) async {
    final syncStatus = await ref.read(syncStatusProvider.future);

    if (!syncStatus.remoteOnly.contains(book.id)) {
      AnxToast.show(L10n.of(navigatorKey.currentContext!)
          .bookSyncStatusBookNotFoundRemote);
      return;
    }

    try {
      await _downloadBook(book);
    } catch (e) {
      // Error handling is done in _downloadBook
    }
  }

  Future<void> releaseBook(Book book) async {
    final syncStatus = await ref.read(syncStatusProvider.future);

    Future<void> deleteLocalBook() async {
      await io.File(getBasePath(book.filePath)).delete();
    }

    Future<void> uploadBook() async {
      try {
        final remotePath = SyncPaths.data(book.filePath);
        final localPath = getBasePath(book.filePath);
        await uploadFile(localPath, remotePath);
      } catch (e) {
        AnxToast.show(
            L10n.of(navigatorKey.currentContext!).bookSyncStatusUploadFailed);
        AnxLog.severe('Failed to upload book\n$e');
        rethrow;
      }
    }

    if (syncStatus.remoteOnly.contains(book.id)) {
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).bookSyncStatusSpaceReleased);
      return;
    } else if (syncStatus.both.contains(book.id)) {
      await deleteLocalBook();
      ref.read(syncStatusProvider.notifier).refresh();
    } else {
      try {
        await uploadBook();
        await deleteLocalBook();
      } catch (e) {
        AnxToast.show(
            L10n.of(navigatorKey.currentContext!).bookSyncStatusUploadFailed);
      }
    }
  }

  Future<void> downloadMultipleBooks(List<int> bookIds) async {
    AnxLog.info(
        'WebDAV: Starting download for ${bookIds.length} remote books.');
    int successCount = 0;
    int failCount = 0;

    try {
      final client = _syncClient;
      if (client != null) {
        await client.ping();
      } else {
        throw Exception('No sync client configured');
      }
    } catch (e) {
      AnxLog.severe(
          'WebDAV connection failed before batch download, ping failed\n${e.toString()}');
      return;
    }

    for (final bookId in bookIds) {
      try {
        final book = await bookDao.selectBookById(bookId);
        AnxLog.info('WebDAV: Downloading book ID $bookId: ${book.title}');
        await _downloadBook(book);
        successCount++;
      } catch (e) {
        AnxLog.severe('WebDAV: Failed to download book ID $bookId: $e');
        failCount++;
      }
    }

    AnxLog.info(L10n.of(navigatorKey.currentContext!)
        .webdavBatchDownloadFinishedReport(successCount, failCount));
    AnxToast.show(L10n.of(navigatorKey.currentContext!)
        .webdavBatchDownloadFinishedReport(successCount, failCount));
  }

  Future<void> _downloadBook(Book book) async {
    try {
      AnxToast.show(L10n.of(navigatorKey.currentContext!)
          .bookSyncStatusDownloadingBook(book.filePath));
      final remotePath = SyncPaths.data(book.filePath);
      final localPath = getBasePath(book.filePath);
      await downloadFile(remotePath, localPath);
    } catch (e) {
      AnxToast.show(
          L10n.of(navigatorKey.currentContext!).bookSyncStatusDownloadFailed);
      AnxLog.severe('Failed to download book\n$e');
      rethrow;
    }
  }

  Future<bool> isCurrentEmpty() async {
    List<String> currentBooks = await bookDao.getCurrentBooks();
    List<String> currentCover = await bookDao.getCurrentCover();
    List<String> totalCurrentFiles = [...currentCover, ...currentBooks];
    return totalCurrentFiles.isEmpty;
  }

  /// Get available database backup list
  Future<List<String>> getAvailableBackups() async {
    return await DatabaseSyncManager.getAvailableBackups();
  }

  /// Show database backup management dialog
  Future<void> showBackupManagementDialog() async {
    try {
      final backups = await getAvailableBackups();

      await SmartDialog.show(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).databaseBackupManagement),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L10n.of(context).availableBackups),
                const SizedBox(height: 12),
                if (backups.isEmpty)
                  Text(
                    L10n.of(context).noBackupsAvailable,
                    style: const TextStyle(color: Colors.grey),
                  )
                else
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      itemCount: backups.length,
                      itemBuilder: (context, index) {
                        final backup = backups[index];
                        final fileName = backup.split('/').last;
                        final timestamp = fileName
                            .replaceAll('backup_database_', '')
                            .replaceAll('.db', '');

                        return ListTile(
                          title: Text('Backup ${index + 1}'),
                          subtitle: Text(timestamp),
                          trailing: ElevatedButton(
                            onPressed: () async {
                              // Navigator.of(context).pop();
                              await _restoreFromBackup(backup);
                            },
                            child: Text(L10n.of(context).restore),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(L10n.of(context).commonCancel),
            ),
          ],
        ),
      );
    } catch (e) {
      AnxLog.severe('Failed to show backup management dialog: $e');
      AnxToast.show('Failed to get backup list: $e');
    }
  }

  /// Restore database from specified backup
  Future<void> _restoreFromBackup(String backupPath) async {
    try {
      final databasePath = await getAnxDataBasesPath();
      final localDbPath = join(databasePath, 'app_database.db');

      // Confirmation dialog
      final confirmed = await SmartDialog.show<bool>(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).confirmRestore),
          content: Text(L10n.of(context).restoreWarning),
          actions: [
            TextButton(
              onPressed: () => SmartDialog.dismiss(result: false),
              child: Text(L10n.of(context).commonCancel),
            ),
            FilledButton(
              onPressed: () => SmartDialog.dismiss(result: true),
              child: Text(L10n.of(context).commonConfirm),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Execute restore
      await DBHelper.close();
      await DBHelper.cleanupWalFiles(localDbPath);
      await io.File(backupPath).copy(localDbPath);
      await DBHelper().initDB();

      // Refresh related providers
      try {
        ref.read(bookListProvider.notifier).refresh();
        ref.read(groupDaoProvider.notifier).refresh();
      } catch (e) {
        AnxLog.info('Failed to refresh providers after restore: $e');
      }

      AnxToast.show(L10n.of(navigatorKey.currentContext!).restoreSuccess);
      AnxLog.info('Database restored from backup: $backupPath');
    } catch (e) {
      AnxLog.severe('Failed to restore from backup: $e');
      AnxToast.show('Restore failed: $e');
    }
  }
}
