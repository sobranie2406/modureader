import 'package:anx_reader/utils/app_motion.dart';
import 'dart:async';
import 'package:anx_reader/service/feedback/runtime_diagnostics.dart';
import 'package:anx_reader/service/ios_linked_books.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'dart:io' as io;
import 'package:anx_reader/service/book.dart' show getBookMetadata;
import 'package:anx_reader/models/document_reading_mode.dart';
import 'package:anx_reader/service/sync/sync_feedback.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/sync_state_model.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/providers/book_notes.dart';
import 'package:anx_reader/providers/bookmark.dart';
import 'package:anx_reader/providers/sync_database_revision.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';
import 'package:anx_reader/service/sync/sync_preflight.dart';
import 'package:anx_reader/service/sync/sync_preview.dart';
import 'package:anx_reader/widgets/sync/sync_preview_dialog.dart';
import 'package:anx_reader/service/sync/reading_sync_retry.dart';
import 'package:anx_reader/service/sync/pending_auto_sync.dart';
import 'package:anx_reader/service/sync/webdav_client.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/replaced_book_files.dart';
import 'package:anx_reader/service/sync/local_book_download.dart';
import 'package:anx_reader/service/sync/converted_book_checksum.dart';
import 'package:anx_reader/service/sync/book_file_sync.dart';
import 'package:anx_reader/service/sync/document_reflow_sync.dart';
import 'package:anx_reader/service/sync/weread_metadata_sync.dart';
import 'package:anx_reader/service/sync/reading_round_sync.dart';
import 'package:anx_reader/service/sync/sync_asset_listing.dart';
import 'package:anx_reader/service/sync/sync_maintenance_schedule.dart';
import 'package:anx_reader/utils/get_path/get_cache_dir.dart';
import 'package:anx_reader/service/sync/ai_settings_sync.dart';
import 'package:anx_reader/service/sync/translation_usage_sync.dart';
import 'package:anx_reader/service/database_sync_manager.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
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
  final _localDownloads = LocalBookDownload();
  int _activeDownloads = 0;
  bool get hasActiveTransfers => _syncRunning || _activeDownloads > 0;
  bool _pendingAutomatic = false;
  SyncDirection? _pendingManualDirection;
  final _autoStart = AutoSyncStartGate();
  final _readingRetry = ReadingSyncRetry();
  final _readingFeedback = ReadingSyncFeedback();
  final _pendingSync = PendingAutoSync(() => Prefs().prefs);
  Timer? _retryAutomatic;
  SyncClientBase? _automaticClient;
  Object? _automaticPolicy;
  SyncClientBase? _remoteListClient;
  Future<List<String>>? _remoteBookListing;
  SyncPreview? _lastPreview;

  /// Shows the read-only preview before the first write of a manual sync.
  ///
  /// The engine calls this after both libraries are loaded and before the local
  /// database or the cloud is touched, so declining leaves both sides intact.
  Future<SyncPreviewDecision> _confirmPreview(
      SyncPreviewContext context) async {
    final preview = buildSyncPreview(context: context);
    _lastPreview = preview;
    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) {
      return const SyncPreviewDecision(SyncConflictResolution.newest);
    }
    final resolution = await showSyncPreviewDialog(dialogContext, preview);
    if (resolution == null) {
      if (dialogContext.mounted) {
        AnxToast.show(ModuStrings.text(
            dialogContext,
            '已取消同步，本机与云端都没有修改。',
            'Sync cancelled. Nothing was changed locally or in the cloud.'));
      }
      return const SyncPreviewDecision.cancel();
    }
    return SyncPreviewDecision(resolution);
  }

  String _previewSummary(SyncPreview preview) {
    final context = navigatorKey.currentContext!;
    final parts = <String>[];
    if (preview.addedBooks.isNotEmpty) {
      parts.add(ModuStrings.text(
          context,
          '新增 ${preview.addedBooks.length} 本',
          '${preview.addedBooks.length} added'));
    }
    if (preview.removedBooks.isNotEmpty) {
      parts.add(ModuStrings.text(
          context,
          '移除 ${preview.removedBooks.length} 本',
          '${preview.removedBooks.length} removed'));
    }
    if (preview.noteDelta != 0) {
      final sign = preview.noteDelta > 0 ? '+' : '';
      parts.add(ModuStrings.text(context, '笔记 $sign${preview.noteDelta}',
          'notes $sign${preview.noteDelta}'));
    }
    final minutes = (preview.readingTimeDelta / 60).round();
    if (minutes != 0) {
      final sign = minutes > 0 ? '+' : '';
      parts.add(ModuStrings.text(
          context, '时长 $sign$minutes 分钟', 'time $sign$minutes min'));
    }
    if (parts.isEmpty) {
      return ModuStrings.text(
          context, '同步完成，两端已一致', 'Sync complete; both sides agree');
    }
    return ModuStrings.text(context, '同步完成：${parts.join(' · ')}',
        'Synced: ${parts.join(' · ')}');
  }

  bool get _chineseFeedback {
    final context = navigatorKey.currentContext;
    return context == null ||
        Localizations.maybeLocaleOf(context)?.languageCode == 'zh';
  }

  bool get _autoSyncAllowed {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return Prefs().webdavStatus &&
        Prefs().autoSync &&
        // A confirmation cannot be shown for a background start. While the
        // preview is enabled every merge has to be started and confirmed by the
        // user, so automatic starts stay paused instead of merging silently.
        !Prefs().syncPreviewBeforeSync &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
  }

  void pauseAutomaticSync() {
    _autoStart.invalidate();
    _readingRetry.cancel();
    _pendingAutomatic = false;
    _retryAutomatic?.cancel();
    _retryAutomatic = null;
  }

  void _retryPendingSyncLater() {
    if (!_pendingSync.pending ||
        !_autoSyncAllowed ||
        _syncClient?.isConfigured != true ||
        _retryAutomatic != null) {
      return;
    }
    // No busy loop while offline. The normal gate still enforces DAV cooldowns.
    _retryAutomatic = Timer(const Duration(minutes: 1), () {
      _retryAutomatic = null;
      if (_pendingSync.pending && _autoSyncAllowed) {
        unawaited(syncData(SyncDirection.both, null));
      }
    });
  }

  @override
  SyncStateModel build() {
    ref.onDispose(pauseAutomaticSync);
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

  void _finishTransfer() {
    if (_activeDownloads > 0) return;
    changeState(state.copyWith(
      isSyncing: _syncRunning,
      direction: SyncDirection.both,
      fileName: '',
      count: 0,
      total: 0,
    ));
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

  Future<bool> shouldSync({bool automatic = false}) async {
    if (!Prefs().webdavStatus) {
      if (!automatic) throw const SyncFeedbackFailure(SyncFailureCode.disabled);
      return false;
    }

    if (_isReading) return _networkReady();
    if (!automatic &&
        Prefs().onlySyncWhenWifi &&
        !(await Connectivity().checkConnectivity())
            .contains(ConnectivityResult.wifi)) {
      throw const SyncFeedbackFailure(SyncFailureCode.wifiRequired);
    }
    return true;
  }

  bool get _isReading => ref.read(currentReadingProvider).isReading;

  Future<bool> _networkReady() async {
    try {
      return syncNetworkAllowed(await Connectivity().checkConnectivity(),
          onlyWifi: Prefs().onlySyncWhenWifi);
    } catch (error) {
      if (!_isReading) rethrow;
      AnxLog.warning('Sync network check unavailable: ${error.runtimeType}');
      return false;
    }
  }

  Future<void> syncData(
    SyncDirection direction,
    WidgetRef? ref, {
    SyncTrigger trigger = SyncTrigger.auto,
    bool Function()? shouldStart,
    bool immediate = false,
    Future<void>? savedReading,
  }) async {
    if (shouldStart != null && (!shouldStart() || _syncRunning)) return;
    final automatic = trigger == SyncTrigger.auto;
    try {
      if (automatic && immediate) {
        await _pendingSync.request(savedReading: savedReading);
      }
      await _pendingSync.ready;
    } catch (error) {
      AnxLog.warning('Sync progress save failed: ${error.runtimeType}');
      return;
    }
    final scheduledClient = _syncClient;
    final policy =
        scheduledClient is WebdavClient ? scheduledClient.requestPolicy : null;
    if (automatic && !_autoSyncAllowed) return;
    if (_isReading && !await _networkReady()) {
      _retryPendingSyncLater();
      return;
    }
    (Object, StackTrace)? preparationFailure;
    try {
      await policy?.prepare();
    } catch (error, stack) {
      if (!_isReading) {
        AnxToast.show(syncFailureMessage(error, chinese: _chineseFeedback));
        _retryPendingSyncLater();
        return;
      }
      // Report preparation failures through the same bounded reader retry cycle.
      preparationFailure = (error, stack);
    }
    if (!identical(_automaticClient, scheduledClient) ||
        !identical(_automaticPolicy, policy)) {
      // A pending long delay for the old account must not swallow the first
      // automatic trigger after changing server/account.
      _autoStart.invalidate();
      _automaticClient = scheduledClient;
      _automaticPolicy = policy;
      _readingFeedback.reset();
    }
    if (automatic) {
      if (!_autoSyncAllowed) return;
      if (_syncRunning) {
        _pendingAutomatic = true;
        return;
      }
      // Foreground/exit requests supersede a reader-only or ordinary delayed start.
      if (immediate) _autoStart.invalidate();
      if (!await _autoStart.wait(
          () =>
              _autoSyncAllowed &&
              identical(scheduledClient, _syncClient) &&
              (scheduledClient is! WebdavClient ||
                  identical(policy, scheduledClient.requestPolicy)) &&
              (shouldStart?.call() ?? true),
          duration:
              policy?.automaticStartDelay(immediate: _pendingSync.pending) ??
                  (_pendingSync.pending
                      ? Duration.zero
                      : const Duration(seconds: 2)))) {
        _retryPendingSyncLater();
        return;
      }
    } else {
      _autoStart.invalidate();
    }
    // Covers preflight and direction selection as well as byte transfer.
    if (_syncRunning) {
      if (!automatic) _pendingManualDirection = direction;
      return;
    }
    _syncRunning = true;
    final diagnosticTimer = Stopwatch()..start();
    RuntimeDiagnostics.record(RuntimeEvent.syncStart);
    _retryAutomatic?.cancel();
    _retryAutomatic = null;
    try {
      if (!(shouldStart?.call() ?? true)) return;
      await _pendingSync.ready;
      final pendingRevision = _pendingSync.revision;
      final generation = _autoStart.generation;
      final identity = List<Object?>.of(scheduledClient?.syncIdentity ?? []);
      bool stillAllowed() =>
          (shouldStart?.call() ?? true) &&
          identical(scheduledClient, _syncClient) &&
          listEquals(identity, scheduledClient?.syncIdentity ?? []) &&
          (!automatic ||
              (_autoSyncAllowed && generation == _autoStart.generation));
      final completed = await _readingRetry.run(
        enabled: stillAllowed,
        reading: () => _isReading,
        networkReady: _networkReady,
        policyDelay: () =>
            policy?.automaticStartDelay(immediate: true) ?? Duration.zero,
        synchronize: () async {
          final failedPreparation = preparationFailure;
          preparationFailure = null;
          if (failedPreparation != null) {
            Error.throwWithStackTrace(
                failedPreparation.$1, failedPreparation.$2);
          }
          await policy?.prepare();
          if (!stillAllowed()) return false;
          return _syncData(direction, ref,
              trigger: trigger, shouldStart: stillAllowed);
        },
      );
      if (completed) await _pendingSync.acknowledge(pendingRevision);
      RuntimeDiagnostics.record(
          completed ? RuntimeEvent.syncComplete : RuntimeEvent.syncPending,
          durationMs: diagnosticTimer.elapsedMilliseconds);
    } catch (e, stack) {
      // Declining the preview is not a failure: nothing was written, and the
      // user already received the "cancelled" confirmation.
      if (e is SyncPreviewCancelled) {
        RuntimeDiagnostics.record(RuntimeEvent.syncPending,
            durationMs: diagnosticTimer.elapsedMilliseconds);
        AnxLog.info('Sync cancelled before merge at the user\'s request');
        return;
      }
      RuntimeDiagnostics.record(RuntimeEvent.syncFailed,
          durationMs: diagnosticTimer.elapsedMilliseconds);
      // Avoid logging DioException.toString(): it can contain private URLs.
      AnxLog.warning(
          'Sync incomplete: ${syncFailureDiagnostic(e)}, automatic=$automatic',
          null,
          stack);
      // Intentional pause/cancellation is not a failed synchronization.
      // Reader failures reach here only after the bounded reconciliation retries.
      if (automatic && (!_autoSyncAllowed || !(shouldStart?.call() ?? true))) {
        return;
      }
      if ((!_isReading || await _networkReady()) &&
          _readingFeedback.failure(reading: _isReading)) {
        AnxToast.show(syncFailureMessage(e, chinese: _chineseFeedback));
      }
    } finally {
      _syncRunning = false;
      changeState(state.copyWith(isSyncing: false));
      final pending = _pendingManualDirection;
      final pendingAutomatic = _pendingAutomatic;
      _pendingManualDirection = null;
      _pendingAutomatic = false;
      if (pending != null) {
        unawaited(syncData(pending, null, trigger: SyncTrigger.manual));
      } else if (pendingAutomatic && _autoSyncAllowed) {
        unawaited(
            syncData(SyncDirection.both, null, trigger: SyncTrigger.auto));
      } else {
        _retryPendingSyncLater();
      }
    }
  }

  Future<bool> _syncData(
    SyncDirection direction,
    WidgetRef? ref, {
    SyncTrigger trigger = SyncTrigger.auto,
    bool Function()? shouldStart,
  }) async {
    if (trigger == SyncTrigger.auto && !Prefs().autoSync) {
      return false;
    }

    if (!(await shouldSync(automatic: trigger == SyncTrigger.auto))) {
      return false;
    }

    final client = _syncClient;
    if (client == null) {
      throw const SyncFeedbackFailure(SyncFailureCode.notConfigured);
    }

    // Do not overlap a library sync with an active file transfer.
    if (state.isSyncing) {
      AnxLog.info('Sync already in progress, skipping');
      return false;
    }

    // Fail visibly without treating authentication/network errors as absence.
    final generation = _autoStart.generation;
    if (!await SyncPreflight().run(
      automatic: trigger == SyncTrigger.auto && !_isReading,
      enabled: () =>
          (shouldStart?.call() ?? true) &&
          Prefs().webdavStatus &&
          (trigger != SyncTrigger.auto ||
              (_autoSyncAllowed && generation == _autoStart.generation)),
      networkReady: _networkReady,
      probe: client.ping,
    )) {
      return false;
    }
    if (!(shouldStart?.call() ?? true)) return false;
    // An offline attempt must not consume Jianguoyun's ten-minute sync interval.
    if (client is WebdavClient) {
      client.requestPolicy.syncStarted();
      await client.requestPolicy.persist();
    }
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
      await RemoteLibrarySettingsSyncService().prepareLocalDatabase(
        enabled: Prefs().syncAiSettingsToWebdav,
        password: Prefs().syncAiSettingsEncryptionPassword,
      );
      await TranslationUsageSyncService().prepareLocalDatabase(
        enabled: Prefs().syncAiSettingsToWebdav,
        password: Prefs().syncAiSettingsEncryptionPassword,
      );
    } on AiSyncPasswordMissingException {
      AnxLog.warning('AI settings sync skipped: encryption password missing');
      rethrow;
    } catch (e) {
      AnxLog.severe(
          'Failed to prepare encrypted AI settings for sync: ${e.runtimeType}');
      throw const SyncFeedbackFailure(SyncFailureCode.encryptionFailed);
    }

    // Reject future formats. Never guess which whole database should win.
    final remoteFiles = await client.safeReadDir(SyncPaths.root);
    for (final file in remoteFiles) {
      final match = RegExp(r'^database(\d+)\.db$').firstMatch(file.name ?? '');
      if (match != null && int.parse(match.group(1)!) > currentDbVersion) {
        throw const SyncFeedbackFailure(SyncFailureCode.newerDatabase);
      }
    }
    if (!(shouldStart?.call() ?? true)) return false;
    changeState(state.copyWith(isSyncing: true));

    final preview = trigger == SyncTrigger.manual &&
            Prefs().webdavStatus &&
            Prefs().syncPreviewBeforeSync
        ? _confirmPreview
        : null;
    _lastPreview = null;

    try {
      final assetListing = SyncAssetListing(client);
      final outcome = await syncDatabase(direction,
          assetListing: assetListing, preview: preview);
      final hasPendingChanges =
          outcome == RowSyncOutcome.publishedWithPendingChanges;
      if (hasPendingChanges) await _pendingSync.request();

      await syncFiles(assetListing: assetListing);
      await DocumentReflowSync(
        client: client,
        cache: await getAnxCacheDir(),
        durableDirectory: await getAnxDataBasesDir(),
      ).sync(await bookDao.selectNotDeleteBooks());
      await WereadMetadataSync(
        client: client,
        cache: await getAnxCacheDir(),
        durableDirectory: await getAnxDataBasesDir(),
      ).sync(await bookDao.selectNotDeleteBooks());
      await this
          .ref
          .read(syncStatusProvider.notifier)
          .refresh(remoteFileNames: assetListing.bookNames);

      // Reclaim only after database publication and book transfer.
      // This is recoverable maintenance; failure does not undo a good sync.
      try {
        final durableDirectory = await getAnxDataBasesDir();
        final reclaimed = await SyncMaintenanceSchedule(durableDirectory).run(
            client,
            () async => ReplacedBookFiles(
                  store: RowSyncStore(await DBHelper().database),
                  client: client,
                  cache: await getAnxCacheDir(),
                  durableDirectory: durableDirectory,
                ).reclaim());
        if (reclaimed != null) {
          AnxLog.info('Replaced-book cleanup: reclaimed=$reclaimed');
        }
      } catch (error) {
        AnxLog.warning('Replaced-book cleanup deferred: ${error.runtimeType}');
      }
      await _cleanupReplacedLocalBooks();

      imageCache.clear();
      imageCache.clearLiveImages();

      try {
        this.ref.read(bookListProvider.notifier).refresh();
        this.ref.read(groupDaoProvider.notifier).refresh();
      } catch (e) {
        AnxLog.info('Failed to refresh book list: $e');
      }

      // Backup cleanup is now handled by DatabaseSyncManager

      if (!hasPendingChanges &&
          preview != null &&
          (_lastPreview?.hasChanges ?? false) &&
          navigatorKey.currentContext != null) {
        AnxToast.show(_previewSummary(_lastPreview!));
      } else if (!hasPendingChanges &&
          _readingFeedback.success(
              reading: _isReading, enabled: Prefs().syncCompletedToast)) {
        AnxToast.show(syncSuccessMessage(chinese: _chineseFeedback));
      }
      return !hasPendingChanges;
    } finally {
      changeState(state.copyWith(isSyncing: false));
      // _deleteBackUpDb();
    }
  }

  Future<void> syncFiles({SyncAssetListing? assetListing}) async {
    final client = _syncClient;
    if (client == null) return;

    AnxLog.info('Sync: syncFiles');
    List<String> currentBooks = await bookDao.getCurrentBooks();
    List<String> currentCover =
        (await bookDao.getCurrentCover()).where((p) => p.isNotEmpty).toList();

    final listing = assetListing ?? SyncAssetListing(client);
    if (!identical(listing.client, client)) {
      throw StateError('Sync client changed during asset synchronization');
    }
    final remoteBooksName = await listing.read(SyncPaths.books, currentBooks);
    final remoteCoversName = await listing.read(SyncPaths.covers, currentCover);

    // Sync cover files
    for (var file in currentCover) {
      if (!remoteCoversName.contains(file) &&
          io.File(getBasePath(file)).existsSync()) {
        await uploadFile(getBasePath(file), SyncPaths.data(file));
        listing.uploaded(file);
      }
      if (!io.File(getBasePath(file)).existsSync() &&
          remoteCoversName.contains(file)) {
        await downloadFile(SyncPaths.data(file), getBasePath(file));
      }
    }

    // Sync book files
    await syncBookFiles(
      client: client,
      currentPaths: currentBooks,
      listedPaths: remoteBooksName,
      onRemotePresent: listing.uploaded,
      localFile: (path) => io.File(getBasePath(path)),
      upload: (local, remote) async {
        await uploadFile(local, remote);
        listing.uploaded(remote.substring('${SyncPaths.root}/data/'.length));
      },
    );

    // Do not garbage-collect by absence: an offline/concurrent device can
    // still reference these files. Deletions are synchronized as tombstones;
    // Explicit replacements are reclaimed separately, AFTER successful sync,
    // with verified recovery copies. Unknown historical files remain untouched.
    if (assetListing == null) {
      await ref
          .read(syncStatusProvider.notifier)
          .refresh(remoteFileNames: listing.bookNames);
    }
  }

  Future<RowSyncOutcome> syncDatabase(SyncDirection direction,
      {SyncAssetListing? assetListing, SyncPreviewHook? preview}) async {
    final client = _syncClient;
    if (client == null) {
      throw const SyncFeedbackFailure(SyncFailureCode.notConfigured);
    }
    // Existing upload/download callers now converge records safely in both
    // directions; no entry point may overwrite a whole live library.
    try {
      final outcome = await RowSyncEngine(
        store: RowSyncStore(await DBHelper().database),
        client: client,
        cache: await getAnxCacheDir(),
        durableDirectory: await getAnxDataBasesDir(),
        onPreview: preview,
        beforePublish: () => syncFiles(assetListing: assetListing),
        beforeMerge: _createMergeBackup,
        afterMerge: () async {
          // Round records arrive before/with the time rows; reconcile derived
          // caches (current_round, cancelled-round time) before publishing.
          await ReadingRoundSync.reconcile(await DBHelper().database);
          await ConvertedBookChecksum(await DBHelper().database)
              .repairLocalBooks(
                  localFile: (path) => io.File(getBasePath(path)));
        },
      ).synchronize();
      AnxLog.info('Row sync database outcome: ${outcome.name}');
      await _restoreAiSettingsAfterDatabaseDownload();
      // Compatibility mode may not have a database8.db at all. Completion is
      // determined by the verified transport, not the old shared file's mtime.
      Prefs().lastUploadBookDate = DateTime.now();
      return outcome;
    } finally {
      // A local merge may succeed even if a later upload fails. Refresh live
      // readers/editors in that case too; never leave stale snapshots active.
      ref.invalidate(bookNotesControllerProvider);
      ref.invalidate(bookmarkProvider);
      ref.read(syncDatabaseRevisionProvider.notifier).state++;
    }
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
    await RemoteLibrarySettingsSyncService().restoreFromDownloadedDatabase(
      enabled: Prefs().syncAiSettingsToWebdav,
      password: Prefs().syncAiSettingsEncryptionPassword,
    );
    await TranslationUsageSyncService().restoreFromDownloadedDatabase(
      enabled: Prefs().syncAiSettingsToWebdav,
      password: Prefs().syncAiSettingsEncryptionPassword,
    );
  }

  Future<void> uploadFile(
    String localPath,
    String remotePath, [
    bool replace = true,
  ]) async {
    changeState(state.copyWith(
      direction: SyncDirection.upload,
      fileName: localPath.split('/').last,
      count: 0,
      total: 0,
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
        _finishTransfer();
        await status.removeUploading(remotePath, completed: completed);
      }
    }

    _finishTransfer();
  }

  Future<void> downloadFile(String remotePath, String localPath,
      {String? expectedMd5}) async {
    final client = _syncClient;
    if (client == null) {
      throw const SyncFeedbackFailure(SyncFailureCode.notConfigured);
    }
    _activeDownloads++;
    changeState(state.copyWith(isSyncing: true));
    var completed = false;
    try {
      await _localDownloads.ensure(io.File(localPath), expectedMd5: expectedMd5,
          download: (temporary) async {
        changeState(state.copyWith(
          isSyncing: true,
          direction: SyncDirection.download,
          fileName: remotePath.split('/').last,
          count: 0,
          total: 0,
        ));
        final status = ref.read(syncStatusProvider.notifier);
        await status.addDownloading(remotePath);
        await client.downloadFile(
          remotePath,
          temporary.path,
          onProgress: (received, total) {
            changeState(state.copyWith(
              isSyncing: true,
              count: received,
              total: total,
            ));
          },
        );
      });
      completed = true;
    } finally {
      // Publish completion only after checksum verification and atomic rename.
      _activeDownloads--;
      _finishTransfer();
      await ref
          .read(syncStatusProvider.notifier)
          .removeDownloading(remotePath, completed: completed);
    }
  }

  Future<List<String>> listRemoteBookFiles() async {
    final client = _syncClient;
    if (client == null) return [];
    // Share only an in-flight request, never a cached snapshot: a later sync
    // must still see changes made by other devices.
    if (identical(client, _remoteListClient) && _remoteBookListing != null) {
      return _remoteBookListing!;
    }
    final pending = client
        .safeReadDir(SyncPaths.books)
        .then((files) => files.map((e) => e.name!).toList());
    _remoteListClient = client;
    _remoteBookListing = pending;
    try {
      return await pending;
    } finally {
      if (identical(_remoteBookListing, pending)) _remoteBookListing = null;
    }
  }

  Future<void> downloadBook(Book book) async {
    try {
      await _downloadBook(book);
    } catch (e) {
      // Error handling is done in _downloadBook
    }
  }

  Future<void> releaseBook(Book book) async {
    if (IosLinkedBooks.isLinked(book.filePath)) {
      AnxToast.show(ModuStrings.text(
          navigatorKey.currentContext!,
          '原位书籍未复制到默读，无需释放原书空间。',
          'This book is read in place; no copied book storage to release.'));
      return;
    }
    final syncStatus = await ref.read(syncStatusProvider.future);

    Future<void> deleteLocalBook() async {
      final client = _syncClient;
      if (client != null) {
        await WereadMetadataSync(
          client: client,
          cache: await getAnxCacheDir(),
          durableDirectory: await getAnxDataBasesDir(),
        ).sync([book]);
        await DocumentReflowSync(
          client: client,
          cache: await getAnxCacheDir(),
          durableDirectory: await getAnxDataBasesDir(),
        ).sync([book]);
      }
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

    final summary = bookDownloadSummary(L10n.of(navigatorKey.currentContext!),
        success: successCount, failed: failCount);
    AnxLog.info(summary);
    AnxToast.show(summary);
  }

  Future<void> _cleanupReplacedLocalBooks() async {
    try {
      final count = await ReplacedBookFiles.reclaimLocal(
        db: await DBHelper().database,
        files: getFileDir(),
        isInUse: (path) {
          final reading = ref.read(currentReadingProvider);
          return reading.isReading && reading.book?.filePath == path;
        },
      );
      if (count > 0) {
        AnxLog.info('Local replaced-book cleanup: reclaimed=$count');
      }
    } catch (error) {
      // Maintenance must not turn a successful download into an error.
      AnxLog.warning(
          'Local replaced-book cleanup deferred: ${error.runtimeType}');
    }
  }

  Future<void> _downloadBook(Book book) async {
    try {
      // A shelf widget can still hold the pre-replacement filename.
      book = await bookDao.selectBookById(book.id);
      if (book.isDeleted) return;
      if (IosLinkedBooks.isLinked(book.filePath)) {
        throw StateError(
            '原位书籍未上传原书，请在当前设备重新授权或普通导入。 / Add the original in place or import it on this device.');
      }
      final remotePath = SyncPaths.data(book.filePath);
      final localPath = getBasePath(book.filePath);
      await downloadFile(remotePath, localPath, expectedMd5: book.md5);
      await _cleanupReplacedLocalBooks();
      try {
        final client = _syncClient;
        if (client != null) {
          await WereadMetadataSync(
            client: client,
            cache: await getAnxCacheDir(),
            durableDirectory: await getAnxDataBasesDir(),
          ).sync([book]);
        }
      } catch (_) {
        await _pendingSync.request();
        _retryPendingSyncLater();
        AnxLog.warning('WeRead metadata transfer deferred');
      }
      try {
        final client = _syncClient;
        if (client != null) {
          await DocumentReflowSync(
            client: client,
            cache: await getAnxCacheDir(),
            durableDirectory: await getAnxDataBasesDir(),
          ).sync([book]);
        }
      } catch (error) {
        // Keep a successful original download; retry only its optional OCR data.
        await _pendingSync.request();
        _retryPendingSyncLater();
        AnxLog.warning(
            'Downloaded book OCR cache deferred: ${error.runtimeType}');
        AnxToast.show(ModuStrings.text(
            navigatorKey.currentContext!,
            '书籍已下载，OCR 缓存同步失败，将在下次同步重试。',
            'Book downloaded. OCR cache transfer will retry on the next sync.'));
      }
      if (DocumentReadingMode.supportsImageBook(book.filePath)) {
        try {
          await getBookMetadata(io.File(localPath),
              book: book, classificationOnly: true);
        } catch (_) {
          // Advisory detection cannot turn a successful download into a failure.
          AnxLog.warning(
              'Downloaded book classification unavailable; manual mode remains available');
        }
      }
      await ref.read(bookListProvider.notifier).refresh();
    } catch (e) {
      AnxToast.show(e is BookFileIntegrityException
          ? bookIntegrityFailureMessage(chinese: _chineseFeedback)
          : L10n.of(navigatorKey.currentContext!).bookSyncStatusDownloadFailed);
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
      final dialogContext = navigatorKey.currentContext;
      if (dialogContext == null || !dialogContext.mounted) return;
      // Use the same navigator route that the Cancel button dismisses.
      await showDialog<void>(
        animationStyle: AppMotion.style,
        context: dialogContext,
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
