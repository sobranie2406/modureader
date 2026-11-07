import 'package:anx_reader/widgets/settings/setting_help_title.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/local_data/backup_safety.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/service/tts/tts_factory.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/widgets/settings/settings_export_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class GlobalSettingsPage extends ConsumerStatefulWidget {
  const GlobalSettingsPage({super.key});
  @override
  ConsumerState<GlobalSettingsPage> createState() => _GlobalSettingsPageState();
}

class _GlobalSettingsPageState extends ConsumerState<GlobalSettingsPage> {
  bool _busy = false;
  bool _includeSecrets = false;
  String? _status;
  String t(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  String _scopeLabel(String scope) => switch (scope) {
        'appearance' =>
          ModuStrings.text(context, '外观与书架', 'Appearance and bookshelf'),
        'reading' => ModuStrings.text(context, '阅读与排版', 'Reading and layout'),
        'css' => ModuStrings.text(
            context, 'CSS 模板与高亮规则', 'CSS profiles and highlights'),
        'selection-search' =>
          ModuStrings.text(context, '选词搜索', 'Selection search'),
        'ai' => ModuStrings.text(context, 'AI 供应商与对话', 'AI providers and chat'),
        'ai-skills' =>
          ModuStrings.text(context, 'AI 技能与提示词', 'AI skills and prompts'),
        'plugins' =>
          ModuStrings.text(context, '插件状态与设置', 'Plugin state and settings'),
        'vector' =>
          ModuStrings.text(context, '向量模型设置', 'Vector model settings'),
        'tts' => ModuStrings.text(context, '朗读配置', 'Speech settings'),
        'webdav' => ModuStrings.text(
            context, '云端同步（WebDAV / S3）', 'Cloud sync (WebDAV / S3)'),
        'remote-library-webdav' =>
          ModuStrings.text(context, '远程书库 WebDAV', 'Library WebDAV'),
        'translation' =>
          ModuStrings.text(context, '翻译设置', 'Translation settings'),
        'notes' => ModuStrings.text(context, '笔记与书摘设置', 'Notes and excerpts'),
        'statistics' => ModuStrings.text(context, '统计布局', 'Statistics layout'),
        'network' => ModuStrings.text(context, '网络代理', 'Network proxy'),
        'advanced' => ModuStrings.text(context, '高级设置', 'Advanced settings'),
        _ => ModuStrings.text(context, '全部全局设置', 'All global settings'),
      };

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await work();
    } catch (error) {
      // Backup contents and plugin messages can contain credentials.
      AnxLog.warning('Global settings transfer failed: ${error.runtimeType}');
      if (mounted) {
        setState(() => _status = error is FileSystemException
            ? t('文件读写失败，请选择可写目录后重试。原设置未删除。',
                'File access failed. Choose a writable folder and retry. Original settings were not deleted.')
            : error is PlatformException || error is MissingPluginException
                ? t('系统文件或剪贴板服务失败，请重试或重启应用。',
                    'System file or clipboard service failed. Retry or restart the app.')
                : error is FormatException
                    ? t('设置格式无效或内容过大，请检查备份文件；长链接请改用文件迁移。',
                        'Invalid or oversized settings. Check the backup; use a file instead of a long link.')
                    : t("设置处理失败，请重试或导出日志反馈。",
                        "Could not process settings. Try again or export the log for feedback."));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export({bool asLink = false}) => _run(() async {
        final scopeLabel = _scopeLabel('all');
        final text = await GlobalSettingsTransfer.export(Prefs(),
            includeSecrets: _includeSecrets);
        if (asLink) {
          final token = GlobalSettingsTransfer.link(text);
          if (!mounted) return;
          await showDialog<void>(
              animationStyle: AppMotion.style,
              context: context,
              builder: (dialogContext) => AlertDialog(
                    title: Text(ModuStrings.format(
                        context, '{scope}：modu 链接', '{scope}: modu link',
                        values: {'scope': scopeLabel})),
                    content: SizedBox(
                        width: 420,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              SettingHelp(
                                  title: Text(ModuStrings.text(
                                      context, "导入链接", "Import link")),
                                  description: Text(ModuStrings.text(
                                      context,
                                      "在另一台设备的“全局设置备份”中粘贴链接。请勿公开分享。",
                                      "Paste the link in Global settings backup on the other device. Keep it private."))),
                              const SizedBox(height: 12),
                              ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxHeight: 120),
                                  child: SingleChildScrollView(
                                      child: SelectableText(token))),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: token));
                          },
                          child: Text(
                              ModuStrings.text(context, '复制链接', 'Copy link'))),
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child:
                              Text(ModuStrings.text(context, '关闭', 'Close'))),
                    ],
                  ));
          return;
        }
        final date =
            DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
        final fileName = 'Modu-settings-$date.json';
        final path = await saveFileToDownload(
            bytes: utf8.encode(text),
            fileName: fileName,
            mimeType: 'application/json');
        if (mounted && path != null) {
          await _showExportResult(path, fileName: fileName);
        }
      });

  Future<void> _showExportResult(String path,
      {required String fileName}) async {
    final destination =
        SettingsExportDestination(path: path, fileName: fileName);
    setState(() => _status = destination.status(
        zh: Localizations.localeOf(context).languageCode == 'zh'));
    await showDialog<void>(
      animationStyle: AppMotion.style,
      context: context,
      builder: (_) => SettingsExportDialog(destination: destination),
    );
  }

  bool _canImport() {
    if (ref.read(syncProvider).isSyncing ||
        bookKnowledgeIndexQueue.activeItems.isNotEmpty) {
      setState(() => _status = ModuStrings.text(context, '请等待同步、向量化任务结束后再导入。',
          'Wait for sync and indexing to finish before importing.'));
      return false;
    }
    return true;
  }

  Future<void> _import() => _run(() async {
        if (!_canImport()) return;
        final picked = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['json'],
            allowMultiple: false);
        final path = picked?.files.single.path;
        if (path == null || !mounted) return;
        final file = File(path);
        if (await file.length() > GlobalSettingsTransfer.maxBytes) {
          throw const FormatException('too large');
        }
        final text = await file.readAsString();
        await _restore(text);
      });

  Future<void> _importLink() => _run(() async {
        if (!_canImport()) return;
        final text = await showDialog<String>(
            animationStyle: AppMotion.style,
            context: context,
            builder: (_) => const _SettingsLinkDialog());
        if (text == null || !mounted) return;
        await _restore(text);
      });

  Future<void> _restore(String text) async {
    final legacy = GlobalSettingsTransfer.legacy(text);
    final values = GlobalSettingsTransfer.forImport(
        legacy ?? await GlobalSettingsTransfer.decode(text),
        includeSecrets: _includeSecrets);
    if (!mounted) return;
    final scopes = GlobalSettingsTransfer.includedScopes(values);
    if (scopes.isEmpty) {
      setState(() => _status = ModuStrings.text(context, '内容中没有可导入的设置，未作任何更改。',
          'No settings to import. Nothing was changed.'));
      return;
    }
    final scopeLabel = scopes.map(_scopeLabel).join(t('、', ', '));
    final disablesSync = GlobalSettingsTransfer.disablesSync(values);
    final credentialNotice = !_includeSecrets
        ? ModuStrings.text(context, "本次跳过账号和密钥配置。",
            "Account and key settings will be skipped.")
        : values.keys.any(isCredentialPreference)
            ? ModuStrings.text(context, "恢复备份中的账号和密钥配置。",
                "Restore account and key settings from the backup.")
            : ModuStrings.text(context, "此备份没有账号或密钥配置。",
                "This backup contains no account or key settings.");
    final confirmed = await showDialog<bool>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(scopes.length == 1
                  ? t('恢复$scopeLabel？', 'Restore $scopeLabel?')
                  : ModuStrings.text(
                      context, '恢复多项设置？', 'Restore multiple settings?')),
              content: SingleChildScrollView(
                child: Text(t(
                      '导入范围：$scopeLabel。\n\n仅覆盖内容中的 ${values.length - 1} 项设置（包括明确记录的默认值），未包含的设置保持不变。书籍、笔记、进度、存储路径和本机字体/背景文件不受影响。\n\n$credentialNotice\n\n导入后请重启默读。',
                      'Import scope: $scopeLabel.\n\nReplace only the ${values.length - 1} included settings (including recorded defaults); settings not included stay unchanged. Books, notes, progress, storage paths and local font/background files are unaffected.\n\n$credentialNotice\n\nRestart Modu afterwards.',
                    ) +
                    (disablesSync
                        ? ModuStrings.text(context, '\n\n云端同步及自动同步需手动重新开启。',
                            '\n\nRe-enable cloud sync and automatic sync manually.')
                        : '')),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(ModuStrings.text(context, '确认恢复', 'Restore')))
              ],
            ));
    if (!mounted || confirmed != true || !_canImport()) return;
    final hadPlayer = scopes.contains('tts') && TtsFactory().hasCurrent;
    try {
      if (hadPlayer) {
        await TtsHandler().stop();
        await TtsFactory().dispose();
      }
      await GlobalSettingsTransfer.apply(Prefs(), values);
    } finally {
      if (hadPlayer) await TtsHandler().switchTtsType(Prefs().ttsService);
    }
    if (scopes.contains('webdav')) SyncClientFactory.resetCurrentClient();
    if (!mounted) return;
    if (scopes.contains('ai')) ref.read(aiProvidersProvider.notifier).refresh();
    setState(() => _status = t('$scopeLabel已恢复。请完全关闭后重新打开默读。',
            '$scopeLabel restored. Close and reopen Modu.') +
        (disablesSync
            ? ModuStrings.text(
                context, '同步需手动重新开启。', ' Re-enable sync manually.')
            : ''));
  }

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          SettingsSection.content(
            title:
                Text(ModuStrings.text(context, '备份与恢复', 'Backup and restore')),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingHelp(
                      title: Text(ModuStrings.text(
                          context, "迁移设置", "Transfer settings")),
                      description: Text(ModuStrings.text(
                          context,
                          "导出设置文件或链接，在另一台设备导入。",
                          "Export a settings file or link, then import it on the other device."))),
                  const SizedBox(height: 16),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: SettingHelp(
                          title: Text(ModuStrings.text(
                              context,
                              '包含账号、密码和 API Key',
                              'Include accounts, passwords and API keys')),
                          description: Text(ModuStrings.text(
                              context,
                              "包含账号、密码和 API Key，请勿公开分享导出的文件或链接。",
                              "Includes accounts, passwords and API keys. Keep exported files and links private."))),
                      value: _includeSecrets,
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _includeSecrets = v)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                      onPressed: _busy ? null : _export,
                      icon: const Icon(Icons.upload_file),
                      label: Text(ModuStrings.text(
                          context, '导出全局设置文件', 'Export global settings file'))),
                  OutlinedButton.icon(
                      onPressed: _busy ? null : () => _export(asLink: true),
                      icon: const Icon(Icons.link),
                      label: Text(ModuStrings.text(
                          context, '导出 modu 链接', 'Export modu link'))),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                      onPressed: _busy ? null : _import,
                      icon: const Icon(Icons.settings_backup_restore),
                      label: Text(ModuStrings.text(
                          context, '从文件恢复设置', 'Restore settings from file'))),
                  OutlinedButton.icon(
                      onPressed: _busy ? null : _importLink,
                      icon: const Icon(Icons.link),
                      label: Text(ModuStrings.text(
                          context, '粘贴 modu 链接恢复', 'Restore from modu link'))),
                  if (_busy)
                    const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                            child: EinkStaticIndicator(
                                child: CircularProgressIndicator()))),
                  if (_status != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: SelectableText(_status!)),
                ]),
          ),
        ],
      ));
}

class _SettingsLinkDialog extends StatefulWidget {
  const _SettingsLinkDialog();
  @override
  State<_SettingsLinkDialog> createState() => _SettingsLinkDialogState();
}

class _SettingsLinkDialogState extends State<_SettingsLinkDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
        title: Text(ModuStrings.text(context, '粘贴 modu 链接', 'Paste modu link')),
        content: TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 6,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ModuStrings.text(context, '取消', 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, _controller.text),
              child: Text(ModuStrings.text(context, '继续', 'Continue')))
        ]);
  }
}
