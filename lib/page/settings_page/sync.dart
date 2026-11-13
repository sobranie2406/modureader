import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'dart:convert';
import 'dart:io';
import 'package:modu_reader/widgets/settings/reading_sync_settings.dart';
import 'package:modu_reader/widgets/settings/database_backup_section.dart';
import 'package:modu_reader/widgets/settings/settings_export_dialog.dart';
import 'package:modu_reader/page/settings_page/global_settings.dart';
import 'package:modu_reader/page/settings_page/settings_page.dart';

import 'package:modu_reader/dao/database.dart';
import 'package:modu_reader/service/local_data/backup_safety.dart';
import 'package:modu_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:modu_reader/service/ai/ai_history.dart';
import 'package:modu_reader/enums/sync_protocol.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/main.dart';
import 'package:modu_reader/providers/sync.dart';
import 'package:modu_reader/service/sync/ai_settings_sync.dart';
import 'package:modu_reader/service/sync/sync_client_factory.dart';
import 'package:modu_reader/service/sync/webdav_request_policy.dart';
import 'package:modu_reader/utils/save_file_to_download.dart';
import 'package:modu_reader/utils/get_path/get_temp_dir.dart';
import 'package:modu_reader/utils/get_path/databases_path.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:modu_reader/utils/sync_test_helper.dart';
import 'package:modu_reader/utils/toast/common.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/utils/webdav/test_webdav.dart';
import 'package:modu_reader/widgets/settings/settings_title.dart';
import 'package:modu_reader/widgets/settings/webdav_switch.dart';
import 'package:modu_reader/widgets/settings/s3_settings_dialog.dart';
import 'package:modu_reader/widgets/settings/sync_secret_field.dart';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:modu_reader/widgets/settings/settings_section.dart';
import 'package:modu_reader/widgets/settings/settings_tile.dart';

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
        SettingsSection(
          title: Text(
              ModuStrings.text(context, '全局设置备份', 'Global settings backup')),
          tiles: [
            SettingsTile.navigation(
              key: const ValueKey('global-settings-backup'),
              leading: const Icon(Icons.settings_backup_restore),
              title: Text(ModuStrings.text(
                  context, '全局设置导入导出', 'Import and export global settings')),
              description: Text(ModuStrings.text(
                  context,
                  '文件与 modu 链接 · 可选迁移账号密钥',
                  'Files and modu links · Optional credentials')),
              onPressed: (context) => Navigator.of(context).push(
                  MotionCupertinoPageRoute(
                      builder: (context) => SettingsPageBody(
                          title: ModuStrings.text(
                              context, '全局设置备份', 'Global settings backup'),
                          isMobile: true,
                          sections: const GlobalSettingsPage()))),
            ),
          ],
        ),
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
                SettingHelp(
                    title: Text(
                        ModuStrings.text(context, "切换服务", "Switch services")),
                    description: Text(ModuStrings.text(
                        context,
                        "切换同步服务前，请关闭同步并等待传输结束。",
                        "Turn off sync and wait for transfers to finish before switching services."))),
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
                    ? Text(ModuStrings.text(context, "各设备填写相同的桶和同步目录。",
                        "Use the same bucket and sync folder on each device."))
                    : Text(ModuStrings.text(
                        context,
                        "各设备连接同一同步目录，即可同步书籍、笔记和阅读进度。",
                        "Connect each device to the same folder to sync books, notes and reading progress.")),
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
                key: const ValueKey('sync-preview-before-sync'),
                title: Text(ModuStrings.text(
                    context, '同步前预览并确认', 'Preview and confirm before sync')),
                description: Text(ModuStrings.text(
                    context,
                    "同步前预览变化并确认。开启后改为手动同步。",
                    "Review changes before syncing. Enabling this switches to manual sync.")),
                leading: const Icon(Icons.fact_check_outlined),
                initialValue: Prefs().syncPreviewBeforeSync,
                enabled: Prefs().webdavStatus,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().syncPreviewBeforeSync = value;
                    if (value) {
                      // A queued automatic merge must not bypass the new
                      // confirmation step.
                      Sync().pauseAutomaticSync();
                    }
                  });
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
                description: Text(ModuStrings.text(context, "同步成功后显示提示。",
                    "Show a message after a successful sync.")),
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
                    ? Text(ModuStrings.text(context, "坚果云自动同步间隔至少为 10 分钟。",
                        "Automatic sync with Nutstore runs at least 10 minutes apart."))
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
              descriptionAsHelp: true,
              description: Text(
                Prefs().syncAiSettingsToWebdav
                    ? ModuStrings.text(context, "服务配置和 API Key 已开启加密同步。",
                        "Service settings and API keys are synced with encryption.")
                    : ModuStrings.text(context, "设置独立密码后，可加密同步服务配置和 API Key。",
                        "Set a separate password to sync service settings and API keys with encryption."),
              ),
              leading: const Icon(Icons.key_outlined),
              initialValue: Prefs().syncAiSettingsToWebdav,
              onToggle: _toggleAiSettingsSync,
            ),
            if (Prefs().syncAiSettingsToWebdav)
              SettingsTile.navigation(
                title: Text(ModuStrings.text(
                    context, '修改同步加密密码', 'Change sync encryption password')),
                descriptionAsHelp: true,
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

      final zipPath = await compute(createZipFile, {
        'documentPath': await getAnxDocumentsPath(),
        'tempPath': (await getAnxTempDir()).path,
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
                content: Text(ModuStrings.text(context, "恢复备份将替换当前书库、笔记和设置。继续？",
                    "Restoring this backup replaces your library, notes and settings. Continue?")),
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
                    title: SettingHelp(
                        title: Text(ModuStrings.text(
                            context,
                            '包含服务配置、API Key 和密码（加密）',
                            'Include service settings, API keys and passwords (encrypted)')),
                        description: Text(ModuStrings.text(
                            context,
                            "将账号、密码和 API Key 加密保存到备份。",
                            "Include encrypted accounts, passwords and API keys in the backup."))),
                    value: _include,
                    onChanged: (value) =>
                        setState(() => _include = value ?? false)),
              if (!widget.exporting || _include) ...[
                Text(ModuStrings.text(context, "请记住此密码，恢复加密设置时需要使用。",
                    "Keep this password. You will need it to restore encrypted settings.")),
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
                ModuStrings.text(context, "使用独立密码，加密同步服务配置、密码和 API Key。",
                    "Use a separate password to encrypt synced service settings, passwords and API keys."),
              ),
              const SizedBox(height: 10),
              Text(
                ModuStrings.text(context, "请妥善保管密码，其他设备需输入相同密码。",
                    "Keep your password safe. Enter the same password on your other devices."),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 14),
            ] else ...[
              Text(ModuStrings.text(context, "修改后，请在其他设备更新密码。",
                  "Update the password on your other devices after changing it.")),
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
  final String prefsBackupFilePath = params['prefsBackupFilePath'];
  final File prefsBackupFile = File(prefsBackupFilePath);
  final date =
      '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
  final zipPath = '${params['tempPath']}/Modu-Backup-$date.zip';
  final docPath = params['documentPath'] as String;
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
              helperText: ModuStrings.text(context, '坚果云请填写应用密码。',
                  'For Nutstore, enter an app password.'),
            )
          : TextField(
              autocorrect: false,
              // Disabling suggestions adds a password input type on Android.
              enableSuggestions: true,
              enableIMEPersonalizedLearning: false,
              keyboardType: labelText == L10n.of(context).settingsSyncWebdavUrl
                  ? TextInputType.url
                  : TextInputType.text,
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
