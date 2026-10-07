import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/widgets/settings/reading_sync_settings.dart';
import 'package:anx_reader/widgets/settings/database_backup_section.dart';
import 'package:anx_reader/widgets/settings/settings_export_dialog.dart';

import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/service/local_data/backup_safety.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/sync/ai_settings_sync.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/service/sync/webdav_request_policy.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/sync_test_helper.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/webdav/test_webdav.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:anx_reader/widgets/settings/webdav_switch.dart';
import 'package:anx_reader/widgets/settings/s3_settings_dialog.dart';
import 'package:anx_reader/widgets/settings/sync_secret_field.dart';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';

const String _prefsBackupFileName = 'modu_shared_prefs.json';

class SyncSetting extends ConsumerStatefulWidget {
  const SyncSetting({super.key});

  @override
  ConsumerState<SyncSetting> createState() => _SyncSettingState();
}

class _SyncSettingState extends ConsumerState<SyncSetting> {
  bool _backupBusy = false;
  @override
  Widget build(BuildContext context) {
    final protocol = SyncClientFactory.getCurrentSyncProtocol();
    final s3 = protocol == SyncProtocol.s3;
    final canConfigure = !Prefs().webdavStatus;
    return settingsSections(
      sections: [
        CustomSettingsSection(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<SyncProtocol>(
                  key: const ValueKey('sync-backend-tabs'),
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(
                        value: SyncProtocol.webdav, label: Text('WebDAV')),
                    ButtonSegment(
                        value: SyncProtocol.s3,
                        label: Text(ModuStrings.text(
                            context, '对象存储', 'Object storage'))),
                  ],
                  selected: {protocol},
                  onSelectionChanged: canConfigure
                      ? (selected) {
                          if (Prefs().webdavStatus ||
                              Sync().hasActiveTransfers) {
                            AnxToast.show(ModuStrings.text(
                                context,
                                '请关闭同步并等待传输结束后再切换。',
                                'Turn sync off and wait for transfers before switching.'));
                            return;
                          }
                          if (selected.single == protocol) return;
                          Sync().pauseAutomaticSync();
                          SyncClientFactory.switchProtocol(selected.single);
                          setState(() {});
                        }
                      : null,
                ),
                const SizedBox(height: 8),
                Text(ModuStrings.text(
                    context,
                    '两种服务的连接配置分别保留。升级后沿用原 WebDAV 设置；切换前请关闭同步并等待传输结束，不会自动搬运云端文件。下方同步选项为两种服务共用。',
                    'Connection settings are kept separately. Existing WebDAV settings survive upgrades. Turn sync off and wait for transfers before switching; cloud files are not migrated. Sync options below are shared by both backends.')),
              ],
            ),
          ),
        ),
        SettingsSection(
          title: Text(ModuStrings.text(context, '云端同步', 'Cloud sync')),
          tiles: [
            webdavSwitch(context, setState, ref),
            SettingsTile.navigation(
                title: Text(s3
                    ? ModuStrings.text(context, '对象存储（S3 兼容）',
                        'Object storage (S3 compatible)')
                    : L10n.of(context).settingsSyncWebdav),
                leading: const Icon(Icons.cloud),
                description: s3
                    ? Text(ModuStrings.text(
                        context,
                        '同步书籍、封面、阅读记录及已启用的加密设置。使用独立不可变记录，上传后读回校验，不直接覆盖共享数据库。各设备使用相同的桶和同步前缀。',
                        'Sync books, covers, reading records and opted-in encrypted settings through immutable records with read-back verification. All devices must use the same bucket and prefix.'))
                    : Text(ModuStrings.text(
                        context,
                        '同步目录：modu。按稳定标识合并书籍、笔记、书签，阅读位置取最近一次操作，阅读时长按记录去重，删除标记防止旧内容复活。字体不参与同步。可靠 ETag 模式：隔离探测确认条件写入可靠后，以 database8.db 为主，合并已有日志，条件写入并读回验证后清理已覆盖日志。不可靠 ETag 兼容模式：使用 record-log-v1 独立记录文件；累计达到 64 个批次后自动合并，上传并读回验证后清理已覆盖的旧文件，不覆盖共享数据库。两种模式都保留删除标记，不删除书籍、封面或旧 database7.db。请先备份并更新所有设备，再恢复同步。旧版每日累计时长按同书同日较大值迁移。',
                        'Sync folder: modu. Records merge by stable identity, reading positions use the latest operation, and reading sessions are deduplicated. Fonts stay local. Reliable ETag mode: isolated probes verify conditional writes; database8.db is the primary archive, and covered logs are removed only after a conditional update and read-back verification. Compatibility mode: immutable record-log-v1 batches are compacted at 64 batches; covered inputs are removed only after uploading and verifying their replacement, without overwriting the shared database. Both modes retain tombstones and leave books, covers and legacy database7.db untouched. Back up and update all devices before syncing. Legacy daily totals use the larger value per book/day.')),
                value: Text(
                    Prefs().getSyncInfo(protocol)[s3 ? 'bucket' : 'url'] ??
                        ModuStrings.text(context, '未设置', 'Not configured')),
                enabled: canConfigure,
                onPressed: (context) async {
                  if (Sync().hasActiveTransfers) {
                    AnxToast.show(ModuStrings.text(context, '请等待传输结束后再修改。',
                        'Wait for transfers to finish before changing settings.'));
                    return;
                  }
                  if (s3) {
                    final values = await showDialog<Map<String, dynamic>>(
                        context: context,
                        barrierDismissible: false,
                        animationStyle: AppMotion.style,
                        builder: (_) => S3SettingsDialog(
                            initial: Prefs().getSyncInfo(SyncProtocol.s3)));
                    if (values != null &&
                        !Sync().hasActiveTransfers &&
                        !Prefs().webdavStatus) {
                      Prefs().setSyncInfo(SyncProtocol.s3, values);
                      SyncClientFactory.initializeCurrentClient();
                    }
                  } else {
                    await showWebdavDialog(context);
                  }
                  if (mounted) setState(() {});
                }),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncWebdavSyncNow),
                leading: const Icon(Icons.sync_alt),
                // value: Text(Prefs().syncDirection),
                enabled: Prefs().webdavStatus,
                onPressed: (context) {
                  chooseDirection(ref);
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).webdavOnlyWifi),
                leading: const Icon(Icons.wifi),
                initialValue: Prefs().onlySyncWhenWifi,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().onlySyncWhenWifi = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(ModuStrings.text(
                    context, '同步成功提示', 'Sync success notification')),
                description: Text(ModuStrings.text(
                    context,
                    '仅在同步成功时提示；失败始终显示原因。同步过程中不弹出提示。',
                    'Notify on success only; failures always show a reason. No in-progress notifications.')),
                leading: const Icon(Icons.notifications),
                initialValue: Prefs().syncCompletedToast,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().syncCompletedToast = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncAutoSync),
                description: !s3 &&
                        isJianguoyunWebdav(
                            Prefs().getSyncInfo(SyncProtocol.webdav)['url'] ??
                                '')
                    ? Text(ModuStrings.text(
                        context,
                        '已识别坚果云：自动同步至少间隔 10 分钟，期间改动合并同步。本机同账号每滚动 30 分钟最多发出 480 次请求，预算和服务器冷却在重启后保留。“立即同步”只跳过自动同步间隔，不跳过请求预算或冷却。其他设备和应用仍可能占用服务端额度。',
                        'Jianguoyun detected: automatic syncs are at least 10 minutes apart and changes are batched. This device allows up to 480 requests per account in a rolling 30-minute window. The budget and server cooldown survive restarts. Sync now bypasses only the automatic interval, not the budget or cooldown. Other devices and apps may still use the server quota.'))
                    : null,
                leading: const Icon(Icons.sync),
                initialValue: Prefs().autoSync,
                enabled: Prefs().webdavStatus,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().autoSync = value;
                  });
                }),
            const ReadingSyncSettings(),
            SettingsTile.navigation(
                title: Text(L10n.of(context).restoreBackup),
                leading: const Icon(Icons.restore),
                onPressed: (context) {
                  ref.read(syncProvider.notifier).showBackupManagementDialog();
                })
          ],
        ),
        SettingsSection(
          title:
              Text(ModuStrings.text(context, '敏感数据同步', 'Sensitive data sync')),
          tiles: [
            SettingsTile.switchTile(
              title: Text(ModuStrings.text(context, '同步服务配置、API Key 和密码',
                  'Sync service settings, API keys and passwords')),
              description: Text(
                Prefs().syncAiSettingsToWebdav
                    ? ModuStrings.text(
                        context,
                        '已开启：AI、翻译、向量、在线语音及远程书库配置（含密钥和书库密码）加密后随当前云端服务同步。不包含 WebDAV / 对象存储的连接凭据。',
                        'Enabled: AI, translation, vector, online speech and remote library settings (including keys and library passwords) are encrypted and synced through the selected cloud service. WebDAV / object-storage connection credentials are excluded.')
                    : ModuStrings.text(
                        context,
                        '默认关闭。开启需设置独立同步加密密码并确认风险；此密码不是 WebDAV 密码或对象存储密钥。两种同步方式共用此开关。',
                        'Off by default. Requires a separate sync encryption password and risk confirmation, not your WebDAV password or object-storage key. This switch is shared by both backends.'),
              ),
              leading: const Icon(Icons.key_outlined),
              initialValue: Prefs().syncAiSettingsToWebdav,
              onToggle: _toggleAiSettingsSync,
            ),
            if (Prefs().syncAiSettingsToWebdav)
              SettingsTile.navigation(
                title: Text(ModuStrings.text(
                    context, '修改同步加密密码', 'Change sync encryption password')),
                description: Text(ModuStrings.text(
                    context,
                    '其他设备必须输入相同密码。密码无法找回。',
                    'Other devices must use the same password. It cannot be recovered.')),
                leading: const Icon(Icons.password_outlined),
                onPressed: (_) => _changeAiSettingsSyncPassword(),
              ),
          ],
        ),
        DatabaseBackupSection(
          busy: _backupBusy,
          onExport: () => exportData(context),
          onImport: importData,
        ),
      ],
    );
  }

  Future<void> _toggleAiSettingsSync(bool enabled) async {
    if (!enabled) {
      Prefs().syncAiSettingsToWebdav = false;
      try {
        await AiSettingsSyncService().prepareLocalDatabase(
          enabled: false,
          password: null,
        );
      } catch (error) {
        AnxLog.warning('Failed to disable encrypted AI sync: $error');
      }
      await Prefs().clearSyncAiSettingsEncryptionPassword();
      if (mounted) setState(() {});
      return;
    }

    final password = await _showEncryptionPasswordDialog(confirmRisk: true);
    if (password == null || !mounted) return;
    try {
      await AiSettingsSyncService().prepareLocalDatabase(
        enabled: true,
        password: password,
      );
      await RemoteLibrarySettingsSyncService().prepareLocalDatabase(
        enabled: true,
        password: password,
      );
      await Prefs().saveSyncAiSettingsEncryptionPassword(password);
      Prefs().syncAiSettingsToWebdav = true;
      if (mounted) setState(() {});
    } catch (error) {
      AnxLog.severe('Failed to enable encrypted AI settings sync: $error');
      if (!mounted) return;
      AnxToast.show(ModuStrings.text(context, '无法启用敏感服务配置同步，请稍后重试',
          'Could not enable sensitive service-settings sync. Please try again.'));
    }
  }

  Future<void> _changeAiSettingsSyncPassword() async {
    final password = await _showEncryptionPasswordDialog(confirmRisk: false);
    if (password == null || !mounted) return;
    try {
      await AiSettingsSyncService().prepareLocalDatabase(
        enabled: true,
        password: password,
        force: true,
      );
      await RemoteLibrarySettingsSyncService().prepareLocalDatabase(
        enabled: true,
        password: password,
        force: true,
      );
      await Prefs().saveSyncAiSettingsEncryptionPassword(password);
      if (!mounted) return;
      setState(() {});
      AnxToast.show(ModuStrings.text(context, '同步加密密码已更新，下次成功同步后生效',
          'The encryption password was updated and will take effect after the next successful sync.'));
    } catch (error) {
      AnxLog.severe('Failed to change AI settings sync password: $error');
      if (!mounted) return;
      AnxToast.show(ModuStrings.text(context, '无法修改同步加密密码',
          'Could not change the sync encryption password.'));
    }
  }

  Future<String?> _showEncryptionPasswordDialog({
    required bool confirmRisk,
  }) {
    return showDialog<String>(
      animationStyle: AppMotion.style,
      context: context,
      barrierDismissible: false,
      builder: (_) => _AiSyncPasswordDialog(confirmRisk: confirmRisk),
    );
  }

  void _showDataDialog(String title) {
    Future.microtask(() {
      SmartDialog.show(
        builder: (BuildContext context) => SimpleDialog(
          title: Center(child: Text(title)),
          children: const [
            Center(
              child: EinkStaticIndicator(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    });
  }

  Future<void> exportData(BuildContext context) async {
    AnxLog.info('exportData: start');
    if (!mounted || _backupBusy) return;
    setState(() => _backupBusy = true);
    File? snapshot;
    File? prefsFile;
    try {
      final password = await showDialog<String>(
          animationStyle: AppMotion.style,
          context: context,
          builder: (_) => const _BackupPasswordDialog(exporting: true));
      if (password == null || !context.mounted) return;

      _showDataDialog(L10n.of(context).exporting);

      await AiHistoryStore.migrateLegacyHistory();
      final File prefsBackupFile =
          await _createPrefsBackupFile(password: password);
      prefsFile = prefsBackupFile;
      snapshot = File(await DBHelper.prepareUploadSnapshot());

      RootIsolateToken token = RootIsolateToken.instance!;
      final zipPath = await compute(createZipFile, {
        'token': token,
        'prefsBackupFilePath': prefsBackupFile.path,
        'snapshotPath': snapshot.path,
      });

      final file = File(zipPath);
      SmartDialog.dismiss();
      if (await file.exists()) {
        String fileName =
            'Modu-Backup-${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}-v3.zip';

        String? filePath = await saveFileToDownload(
            sourceFilePath: file.path,
            fileName: fileName,
            mimeType: 'application/zip');

        await file.delete();

        if (filePath != null) {
          AnxLog.info('exportData: Saved to: $filePath');
          if (context.mounted) {
            await showDialog<void>(
              animationStyle: AppMotion.style,
              context: context,
              builder: (_) => SettingsExportDialog(
                destination: SettingsExportDestination(
                    path: filePath, fileName: fileName),
              ),
            );
          }
        } else {
          AnxLog.info('exportData: Cancelled');
          AnxToast.show(L10n.of(navigatorKey.currentContext!).commonCanceled);
        }
      }
    } catch (error) {
      AnxToast.show('导出失败：$error');
    } finally {
      if (await snapshot?.exists() ?? false) await snapshot!.delete();
      if (await prefsFile?.exists() ?? false) await prefsFile!.delete();
      SmartDialog.dismiss();
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> importData() async {
    AnxLog.info('importData: start');
    if (!mounted || _backupBusy) return;
    if (ref.read(syncProvider).isSyncing ||
        bookKnowledgeIndexQueue.activeItems.isNotEmpty) {
      AnxToast.show('请等待同步和向量队列结束后再恢复备份。');
      return;
    }
    setState(() => _backupBusy = true);
    Directory? staging;
    BackupDirectoryTransaction? transaction;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (result == null) {
        return;
      }

      String? filePath = result.files.single.path;
      if (filePath == null) {
        AnxLog.info('importData: cannot get file path');
        AnxToast.show(
            L10n.of(navigatorKey.currentContext!).importCannotGetFilePath);
        return;
      }

      File zipFile = File(filePath);
      if (!await zipFile.exists()) {
        AnxLog.info('importData: zip file not found');
        AnxToast.show(
            L10n.of(navigatorKey.currentContext!).importCannotGetFilePath);
        return;
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
          animationStyle: AppMotion.style,
          context: context,
          builder: (context) => AlertDialog(
                title: Text(ModuStrings.text(
                    context, '数据库备份导入', 'Import database backup')),
                content: Text(ModuStrings.text(
                    context,
                    '恢复会替换现有书库、笔记和备份中的设置。程序会先校验备份并保留旧目录的恢复副本。是否继续？',
                    'Restoring replaces your library, notes and backed-up settings. The backup is validated first, and a recovery copy of the old directory is kept. Continue?')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(ModuStrings.text(
                          context, '校验并恢复', 'Validate and restore')))
                ],
              ));
      if (confirmed != true) return;
      _showDataDialog(L10n.of(navigatorKey.currentContext!).importing);
      staging = await (await getAnxTempDir()).createTemp('modu-restore-');
      final extractPath = staging.path;

      try {
        await compute(extractZipFile, {
          'zipFilePath': zipFile.path,
          'destinationPath': extractPath,
        });

        await DBHelper().database;
        await validateBackupDatabase(staging,
            maxSchemaVersion: currentDbVersion);
        var importedPrefs = await readBackupPreferences(staging);
        if (importedPrefs?['encryptedPreferences'] is String) {
          await SmartDialog.dismiss();
          if (!mounted) return;
          final password = await showDialog<String>(
              animationStyle: AppMotion.style,
              context: context,
              builder: (_) => const _BackupPasswordDialog(exporting: false));
          if (password == null) return;
          importedPrefs = Map<String, dynamic>.from(await AiSettingsSyncCipher()
              .decrypt(
                  importedPrefs!['encryptedPreferences'] as String, password));
          _showDataDialog('正在恢复');
        }
        validatePreferencesBackup(importedPrefs);
        final previousPrefs = await Prefs().buildPrefsBackupMap();
        final oldKeys = Prefs().prefs.getKeys();
        final docPath = await getAnxDocumentsPath();
        transaction = BackupDirectoryTransaction();
        await transaction.stage(staging, {
          for (final name
              in backupDirectories.where((name) => name != 'databases'))
            name: Directory(path.join(docPath, name)),
          'databases': await getAnxDataBasesDir(),
        });
        // Recheck immediately before replacing data, after potentially slow validation.
        if (ref.read(syncProvider).isSyncing ||
            bookKnowledgeIndexQueue.activeItems.isNotEmpty) {
          throw StateError('同步或向量任务已启动，请稍后重试恢复');
        }
        await DBHelper.close();
        try {
          await transaction.commit(applySettings: () async {
            if (importedPrefs != null) {
              await Prefs().applyPrefsBackupMap(importedPrefs);
            }
            // Opening/migrating the replacement is part of the transaction.
            try {
              await DBHelper().database;
            } catch (_) {
              await DBHelper.close();
              rethrow;
            }
          });
        } catch (_) {
          for (final key in Prefs().prefs.getKeys().difference(oldKeys)) {
            await Prefs().prefs.remove(key);
          }
          await Prefs().applyPrefsBackupMap(previousPrefs);
          await DBHelper().database;
          rethrow;
        }
        AnxLog.info(
            'Backup recovery directories retained: ${transaction.recoveryPaths}');

        AnxLog.info('importData: import success');
        AnxToast.show(
            L10n.of(navigatorKey.currentContext!).importSuccessRestartApp);
      } catch (e) {
        AnxLog.info('importData: error while unzipping or copying files: $e');
        AnxToast.show(
            L10n.of(navigatorKey.currentContext!).importFailed(e.toString()));
      } finally {
        SmartDialog.dismiss();
      }
    } finally {
      await transaction?.cleanStaging();
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      if (mounted) setState(() => _backupBusy = false);
    }
  }
}

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog({required this.exporting});
  final bool exporting;
  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _include = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.exporting
            ? ModuStrings.text(context, '数据库备份导出', 'Export database backup')
            : ModuStrings.text(context, '解密备份设置', 'Decrypt backup settings')),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.exporting)
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(ModuStrings.text(
                        context,
                        '包含服务配置、API Key 和密码（加密）',
                        'Include service settings, API keys and passwords (encrypted)')),
                    subtitle: Text(ModuStrings.text(
                        context,
                        '默认不导出 AI、翻译、语音、向量、WebDAV、对象存储和远程书库的配置与凭据。勾选后包含密码、API Key 和对象存储密钥并加密设置。书籍、笔记和一般设置仍会导出。',
                        'AI, translation, speech, vector, WebDAV, object storage and remote library settings and credentials are excluded by default. Enable this to include passwords, API keys and object-storage keys in encrypted settings. Books, notes and general settings are always exported.')),
                    value: _include,
                    onChanged: (value) =>
                        setState(() => _include = value ?? false)),
              if (!widget.exporting || _include) ...[
                Text(ModuStrings.text(
                    context,
                    '设置使用 AES-256-GCM 加密；书籍、笔记和 AI 对话历史不加密。请使用独立强密码，遗失密码无法恢复密钥。密码不会写入备份。',
                    'Settings use AES-256-GCM encryption; books, notes and AI chat history are not encrypted. Use a unique strong password. Keys cannot be recovered if the password is lost. The password is not stored in the backup.')),
                SyncSecretField(
                    controller: _password,
                    label: ModuStrings.text(context, '备份密码', 'Backup password'),
                    errorText: _error),
                if (widget.exporting)
                  SyncSecretField(
                      controller: _confirm,
                      label: ModuStrings.text(context, '再次输入密码（至少 12 个字符）',
                          'Repeat password (at least 12 characters)')),
              ],
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
          TextButton(
              onPressed: () {
                if (widget.exporting && !_include) {
                  Navigator.pop(context, '');
                  return;
                }
                if (_password.text.isEmpty ||
                    (widget.exporting &&
                        (_password.text.length < 12 ||
                            _password.text != _confirm.text))) {
                  setState(() => _error = ModuStrings.text(
                      context,
                      '请检查密码长度和两次输入',
                      'Check the password length and that both entries match'));
                  return;
                }
                Navigator.pop(context, _password.text);
              },
              child: Text(widget.exporting
                  ? ModuStrings.text(context, '导出', 'Export')
                  : ModuStrings.text(context, '解密', 'Decrypt')))
        ],
      );
}

class _AiSyncPasswordDialog extends StatefulWidget {
  const _AiSyncPasswordDialog({required this.confirmRisk});

  final bool confirmRisk;

  @override
  State<_AiSyncPasswordDialog> createState() => _AiSyncPasswordDialogState();
}

class _AiSyncPasswordDialogState extends State<_AiSyncPasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  String? _errorText;

  String _label(String zh, String en) {
    return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;
    if (password.length < 12) {
      setState(() {
        _errorText = ModuStrings.text(context, '密码至少需要 12 个字符',
            'Password must contain at least 12 characters');
      });
      return;
    }
    if (password != _confirmationController.text) {
      setState(() {
        _errorText = ModuStrings.text(
            context, '两次输入的密码不一致', 'The passwords do not match');
      });
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_label(
        widget.confirmRisk ? '同步服务配置、API Key 和密码：风险提示' : '修改同步加密密码',
        widget.confirmRisk
            ? 'Service settings, API keys and passwords: sync risks'
            : 'Change sync encryption password',
      )),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.confirmRisk) ...[
              Text(
                ModuStrings.text(
                    context,
                    '开启后，AI、翻译、向量、在线语音服务的配置及 API Key，以及远程书库配置和密码，会使用 AES-256-GCM 加密并随当前云端服务同步。不包含 WebDAV / 对象存储连接凭据。此开关及加密密码为两种同步方式共用。',
                    'AI, translation, vector, online speech and remote library settings, API keys and library passwords are encrypted with AES-256-GCM and synced through the selected cloud service. WebDAV / object-storage credentials are excluded. Both backends share this switch and encryption password.'),
              ),
              const SizedBox(height: 10),
              Text(
                ModuStrings.text(
                    context,
                    '风险：加密不能代替可信的云端服务。弱密码可能被猜出；任何得到同步数据和正确密码的人都能读取密钥。请使用独立强密码，不要复用服务商登录密码或访问密钥，并妥善保管。',
                    'Risk: encryption does not replace a trusted cloud service. Anyone with the synced data and correct password can read the keys. Use and protect a strong, unique password, not your provider login password or access key.'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 14),
            ] else ...[
              Text(ModuStrings.text(context, '修改后，其他设备也必须改用新密码。旧密码无法恢复新上传的数据。',
                  'After changing it, other devices must use the new password. The old password cannot decrypt newly uploaded data.')),
              const SizedBox(height: 14),
            ],
            SyncSecretField(
              controller: _passwordController,
              autofocus: true,
              label: ModuStrings.text(
                  context, '同步加密密码', 'Sync encryption password'),
              helperText: ModuStrings.text(context, '至少 12 个字符，仅保存在本机',
                  'At least 12 characters; stored only on this device'),
            ),
            const SizedBox(height: 8),
            SyncSecretField(
              controller: _confirmationController,
              label:
                  ModuStrings.text(context, '再次输入密码', 'Enter password again'),
              errorText: _errorText,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_label(
            widget.confirmRisk ? '我了解风险并开启' : '保存',
            widget.confirmRisk ? 'I understand and enable' : 'Save',
          )),
        ),
      ],
    );
  }
}

Future<String> createZipFile(Map<String, dynamic> params) async {
  RootIsolateToken token = params['token'];
  final String prefsBackupFilePath = params['prefsBackupFilePath'];
  final File prefsBackupFile = File(prefsBackupFilePath);
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final date =
      '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
  final zipPath = '${(await getAnxTempDir()).path}/Modu-Backup-$date.zip';
  final docPath = await getAnxDocumentsPath();
  final directoryList = [
    getFileDir(path: docPath),
    getCoverDir(path: docPath),
    getFontDir(path: docPath),
    getBgimgDir(path: docPath),
    Directory(path.join(docPath, 'ai')),
    // await getAnxSharedPrefsDir(),
    // await getAnxShredPrefsFile(),
    prefsBackupFile,
  ];

  AnxLog.info('exportData: directoryList: $directoryList');

  final encoder = ZipFileEncoder();
  encoder.create(zipPath);

  await encoder.addFile(
      File(params['snapshotPath'] as String), 'databases/app_database.db');

  for (final dir in directoryList) {
    if (dir is Directory) {
      if (await dir.exists()) await encoder.addDirectory(dir);
    } else if (dir is File) {
      await encoder.addFile(dir);
    }
  }
  encoder.close();
  if (await prefsBackupFile.exists()) {
    await prefsBackupFile.delete();
  }
  return zipPath;
}

Future<void> extractZipFile(Map<String, String> params) async {
  final zipFilePath = params['zipFilePath']!;
  final destinationPath = params['destinationPath']!;

  final input = InputFileStream(zipFilePath);
  try {
    final archive = ZipDecoder().decodeBuffer(input);
    validateBackupArchive(archive);
    extractArchiveToDiskSync(archive, destinationPath);
    archive.clearSync();
  } finally {
    await input.close();
  }
}

Future<File> _createPrefsBackupFile({required String password}) async {
  final Directory tempDir = await getAnxTempDir();
  final File backupFile = File('${tempDir.path}/$_prefsBackupFileName');
  final backup = await Prefs().buildPrefsBackupMap();
  final Map<String, dynamic> prefsMap = password.isEmpty
      ? withoutBackupCredentials(backup)
      : {
          'encryptedPreferences':
              await AiSettingsSyncCipher().encrypt(backup, password)
        };
  await backupFile.writeAsString(jsonEncode(prefsMap));
  return backupFile;
}

Future<void> showWebdavDialog(BuildContext context) async {
  final title = L10n.of(context).settingsSyncWebdav;
  // final prefs = Prefs().saveWebdavInfo;
  final webdavInfo = Prefs().getSyncInfo(SyncProtocol.webdav);
  final webdavUrlController = TextEditingController(text: webdavInfo['url']);
  final webdavUsernameController =
      TextEditingController(text: webdavInfo['username']);
  final webdavPasswordController =
      TextEditingController(text: webdavInfo['password']);
  Widget buildTextField(String labelText, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: labelText == L10n.of(context).settingsSyncWebdavPassword
          ? SyncSecretField(
              controller: controller,
              label: labelText,
              helperText: ModuStrings.text(
                  context,
                  '坚果云请填写应用密码，不是登录密码。连接凭据仅保存在本机。',
                  'For Jianguoyun use an app password, not your login password. Connection credentials stay on this device.'),
            )
          : TextField(
              autocorrect: false,
              enableSuggestions: false,
              controller: controller,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: labelText,
              ),
            ),
    );
  }

  await showDialog<void>(
    animationStyle: AppMotion.style,
    context: context,
    builder: (context) {
      return SimpleDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.all(20),
        children: [
          buildTextField(
              L10n.of(context).settingsSyncWebdavUrl, webdavUrlController),
          buildTextField(L10n.of(context).settingsSyncWebdavUsername,
              webdavUsernameController),
          buildTextField(L10n.of(context).settingsSyncWebdavPassword,
              webdavPasswordController),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(L10n.of(context).commonCancel),
              ),
              TextButton.icon(
                onPressed: () => SyncTestHelper.handleFullTestConnection(
                  context,
                  protocol: SyncProtocol.webdav,
                  config: {
                    'url': webdavUrlController.text.trim(),
                    'username': webdavUsernameController.text,
                    'password': webdavPasswordController.text,
                  },
                ),
                icon: const Icon(Icons.wifi_find),
                label: Text(L10n.of(context).settingsSyncWebdavTestConnection),
              ),
              TextButton(
                onPressed: () {
                  webdavInfo['url'] = webdavUrlController.text.trim();
                  if (Sync().hasActiveTransfers || Prefs().webdavStatus) return;
                  webdavInfo['username'] = webdavUsernameController.text;
                  webdavInfo['password'] = webdavPasswordController.text;
                  Prefs().setSyncInfo(SyncProtocol.webdav, webdavInfo);
                  SyncClientFactory.initializeCurrentClient();
                  Navigator.pop(context);
                },
                child: Text(L10n.of(context).commonSave),
              ),
            ],
          ),
        ],
      );
    },
  );
}
