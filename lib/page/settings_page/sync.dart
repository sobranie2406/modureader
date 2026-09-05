import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/service/local_data/backup_safety.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/config_transfer/settings_config_transfer.dart';
import 'package:anx_reader/service/sync/ai_settings_sync.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
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
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/config_transfer_tile.dart';
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
    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).settingsSyncWebdav),
          tiles: [
            webdavSwitch(context, setState, ref),
            SettingsTile.navigation(
                title: Text(L10n.of(context).settingsSyncWebdav),
                leading: const Icon(Icons.cloud),
                value: Text(Prefs().getSyncInfo(SyncProtocol.webdav)['url'] ??
                    'Not set'),
                // enabled: Prefs().webdavStatus,
                onPressed: (context) async {
                  showWebdavDialog(context);
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
                title: Text(L10n.of(context).settingsSyncCompletedToast),
                leading: const Icon(Icons.notifications),
                initialValue: Prefs().syncCompletedToast,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().syncCompletedToast = value;
                  });
                }),
            SettingsTile.switchTile(
                title: Text(L10n.of(context).settingsSyncAutoSync),
                leading: const Icon(Icons.sync),
                initialValue: Prefs().autoSync,
                enabled: Prefs().webdavStatus,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().autoSync = value;
                  });
                }),
            SettingsTile.navigation(
                title: Text(L10n.of(context).restoreBackup),
                leading: const Icon(Icons.restore),
                onPressed: (context) {
                  ref.read(syncProvider.notifier).showBackupManagementDialog();
                })
          ],
        ),
        SettingsSection(
          title: Text(_label('敏感数据同步', 'Sensitive data sync')),
          tiles: [
            SettingsTile.switchTile(
              title: Text(_label('同步 API Key', 'Sync API keys')),
              description: Text(
                Prefs().syncAiSettingsToWebdav
                    ? _label(
                        '已单独开启。AI、翻译、向量和在线语音服务配置将加密后写入 WebDAV 同步数据库。',
                        'Enabled separately. AI, translation, vector, and online speech settings are encrypted before being written to the WebDAV database.',
                      )
                    : _label(
                        '默认不随 WebDAV 同步。开启时需要设置独立加密密码并确认风险。',
                        'Excluded from WebDAV sync by default. Enabling it requires a separate encryption password and risk confirmation.',
                      ),
              ),
              leading: const Icon(Icons.key_outlined),
              initialValue: Prefs().syncAiSettingsToWebdav,
              onToggle: _toggleAiSettingsSync,
            ),
            if (Prefs().syncAiSettingsToWebdav)
              SettingsTile.navigation(
                title: Text(_label(
                  '修改同步加密密码',
                  'Change sync encryption password',
                )),
                description: Text(_label(
                  '其他设备必须输入相同密码。密码无法找回。',
                  'Other devices must use the same password. It cannot be recovered.',
                )),
                leading: const Icon(Icons.password_outlined),
                onPressed: (_) => _changeAiSettingsSyncPassword(),
              ),
          ],
        ),
        SettingsSection(
          tiles: [
            ConfigTransferTile(
              kind: 'webdav',
              label: _label('WebDAV 配置', 'WebDAV configuration'),
              getData: _buildWebdavTransferData,
              applyData: _applyWebdavTransferData,
            ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).exportAndImport),
          tiles: [
            SettingsTile.navigation(
                title: Text(L10n.of(context).exportAndImportExport),
                leading: const Icon(Icons.cloud_upload),
                onPressed: (context) {
                  exportData(context);
                }),
            SettingsTile.navigation(
                title: Text(L10n.of(context).exportAndImportImport),
                leading: const Icon(Icons.cloud_download),
                onPressed: (context) {
                  importData();
                }),
          ],
        ),
      ],
    );
  }

  String _label(String zh, String en) {
    return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
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
      await Prefs().saveSyncAiSettingsEncryptionPassword(password);
      Prefs().syncAiSettingsToWebdav = true;
      if (mounted) setState(() {});
    } catch (error) {
      AnxLog.severe('Failed to enable encrypted AI settings sync: $error');
      AnxToast.show(_label(
        '无法启用 API Key 同步，请稍后重试',
        'Could not enable API key sync. Please try again.',
      ));
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
      await Prefs().saveSyncAiSettingsEncryptionPassword(password);
      if (mounted) setState(() {});
      AnxToast.show(_label(
        '同步加密密码已更新，下次上传数据库后生效',
        'The encryption password was updated and will take effect after the next database upload.',
      ));
    } catch (error) {
      AnxLog.severe('Failed to change AI settings sync password: $error');
      AnxToast.show(_label(
        '无法修改同步加密密码',
        'Could not change the sync encryption password.',
      ));
    }
  }

  Future<String?> _showEncryptionPasswordDialog({
    required bool confirmRisk,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AiSyncPasswordDialog(confirmRisk: confirmRisk),
    );
  }

  Map<String, dynamic> _buildWebdavTransferData() {
    return WebdavConfigTransfer.createPayload(
      syncInfo: Prefs().getSyncInfo(SyncProtocol.webdav),
      enabled: Prefs().webdavStatus,
      autoSync: Prefs().autoSync,
      wifiOnly: Prefs().onlySyncWhenWifi,
      notifyOnComplete: Prefs().syncCompletedToast,
    );
  }

  Future<void> _applyWebdavTransferData(Map<String, dynamic> data) async {
    final imported = WebdavConfigTransfer.parse(data);
    Prefs().setSyncInfo(SyncProtocol.webdav, imported.syncInfo);
    if (imported.enabled != null) {
      Prefs().saveWebdavStatus(imported.enabled!);
    }
    if (imported.autoSync != null) Prefs().autoSync = imported.autoSync!;
    if (imported.wifiOnly != null) {
      Prefs().onlySyncWhenWifi = imported.wifiOnly!;
    }
    if (imported.notifyOnComplete != null) {
      Prefs().syncCompletedToast = imported.notifyOnComplete!;
    }
    SyncClientFactory.initializeCurrentClient();
    if (mounted) setState(() {});
  }

  void _showDataDialog(String title) {
    Future.microtask(() {
      SmartDialog.show(
        builder: (BuildContext context) => SimpleDialog(
          title: Center(child: Text(title)),
          children: const [
            Center(
              child: CircularProgressIndicator(),
            ),
          ],
        ),
      );
    });
  }

  Future<void> exportData(BuildContext context) async {
    AnxLog.info('exportData: start');
    if (!mounted || _backupBusy) return;
    _backupBusy = true;
    File? snapshot;
    File? prefsFile;
    try {
      final password = await showDialog<String>(
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
        // SaveFileDialogParams params = SaveFileDialogParams(
        //   sourceFilePath: file.path,
        //   mimeTypesFilter: ['application/zip'],
        // );
        // final filePath = await FlutterFileDialog.saveFile(params: params);
        String fileName =
            'Modu-Backup-${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}-v3.zip';

        String? filePath = await saveFileToDownload(
            sourceFilePath: file.path,
            fileName: fileName,
            mimeType: 'application/zip');

        await file.delete();

        if (filePath != null) {
          AnxLog.info('exportData: Saved to: $filePath');
          AnxToast.show(
              L10n.of(navigatorKey.currentContext!).exportTo(filePath));
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
      _backupBusy = false;
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
    _backupBusy = true;
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
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('恢复备份'),
                content:
                    const Text('恢复会替换现有书库、笔记和备份中的设置。程序会先校验备份并保留旧目录的恢复副本。是否继续？'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('校验并恢复'))
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
      _backupBusy = false;
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
        title: Text(widget.exporting ? '导出本地备份' : '解密备份设置'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.exporting)
                CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('包含服务配置与 API Key（加密）'),
                    subtitle: const Text(
                        '默认不导出 AI、翻译、语音、向量和 WebDAV 的接口配置与凭据。书籍、笔记和一般设置仍会导出。'),
                    value: _include,
                    onChanged: (value) =>
                        setState(() => _include = value ?? false)),
              if (!widget.exporting || _include) ...[
                const Text(
                    '设置使用 AES-256-GCM 加密；书籍、笔记和 AI 对话历史不加密。请使用独立强密码，遗失密码无法恢复密钥。密码不会写入备份。'),
                TextField(
                    controller: _password,
                    obscureText: true,
                    decoration:
                        InputDecoration(labelText: '备份密码', errorText: _error)),
                if (widget.exporting)
                  TextField(
                      controller: _confirm,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: '再次输入密码（至少 12 个字符）')),
              ],
            ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
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
                  setState(() => _error = '请检查密码长度和两次输入');
                  return;
                }
                Navigator.pop(context, _password.text);
              },
              child: Text(widget.exporting ? '导出' : '解密'))
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
        _errorText = _label(
          '密码至少需要 12 个字符',
          'Password must contain at least 12 characters',
        );
      });
      return;
    }
    if (password != _confirmationController.text) {
      setState(() {
        _errorText = _label('两次输入的密码不一致', 'The passwords do not match');
      });
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_label(
        widget.confirmRisk ? '同步 API Key 风险提示' : '修改同步加密密码',
        widget.confirmRisk
            ? 'API key sync risk warning'
            : 'Change sync encryption password',
      )),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.confirmRisk) ...[
              Text(
                _label(
                  '开启后，AI、翻译、向量和在线语音服务的配置及 API Key 会使用 AES-256-GCM 加密，并写入 WebDAV 同步数据库。',
                  'When enabled, AI, translation, vector, and online speech settings and API keys are encrypted with AES-256-GCM and written to the WebDAV sync database.',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _label(
                  '风险：加密不能代替可信的 WebDAV 服务。弱密码可能被猜出；任何得到数据库和正确密码的人都能读取密钥。请使用独立强密码，并妥善保管。',
                  'Risk: encryption does not replace a trusted WebDAV service. Weak passwords may be guessed, and anyone with the database and correct password can read the keys. Use and protect a strong, unique password.',
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 14),
            ] else ...[
              Text(_label(
                '修改后，其他设备也必须改用新密码。旧密码无法恢复新上传的数据。',
                'After changing it, other devices must use the new password. The old password cannot decrypt newly uploaded data.',
              )),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _passwordController,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _label('同步加密密码', 'Sync encryption password'),
                helperText: _label(
                  '至少 12 个字符，仅保存在本机',
                  'At least 12 characters; stored only on this device',
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _confirmationController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _label('再次输入密码', 'Enter password again'),
                errorText: _errorText,
              ),
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

void showWebdavDialog(BuildContext context) {
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
      child: TextField(
        obscureText: labelText == L10n.of(context).settingsSyncWebdavPassword
            ? true
            : false,
        controller: controller,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: labelText,
        ),
      ),
    );
  }

  showDialog(
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
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
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
