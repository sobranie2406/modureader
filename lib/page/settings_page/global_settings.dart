import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/service/config_transfer/config_qr_bridge.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/service/tts/tts_factory.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
        'appearance' => t('外观与书架', 'Appearance and bookshelf'),
        'reading' => t('阅读与排版', 'Reading and layout'),
        'css' => t('CSS 模板与高亮规则', 'CSS profiles and highlights'),
        'selection-search' => t('选词搜索', 'Selection search'),
        'ai' => t('AI 供应商与对话', 'AI providers and chat'),
        'ai-skills' => t('AI 技能与提示词', 'AI skills and prompts'),
        'vector' => t('向量模型设置', 'Vector model settings'),
        'tts' => t('朗读配置', 'Speech settings'),
        'webdav' => t('同步 WebDAV', 'Sync WebDAV'),
        'remote-library-webdav' => t('远程书库 WebDAV', 'Library WebDAV'),
        'translation' => t('翻译设置', 'Translation settings'),
        'notes' => t('笔记与书摘设置', 'Notes and excerpts'),
        'statistics' => t('统计布局', 'Statistics layout'),
        'network' => t('网络代理', 'Network proxy'),
        'advanced' => t('高级设置', 'Advanced settings'),
        _ => t('全部全局设置', 'All global settings'),
      };

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await work();
    } catch (_) {
      if (mounted) {
        setState(() => _status = t('操作未完成：请检查文件格式或存储权限；配置过大时请使用文件迁移。',
            'Operation failed. Check the file or storage permissions; use a file for large configurations.'));
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
          Uint8List? image;
          try {
            image = await ConfigQrBridge.generate(token);
          } catch (_) {/* Keep the complete link. */}
          if (!mounted) return;
          await showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                    title: Text(t('$scopeLabel：二维码 / modu 链接',
                        '$scopeLabel: QR / modu link')),
                    content: SizedBox(
                        width: 420,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              if (image != null)
                                Image.memory(image, width: 260, height: 260)
                              else
                                Text(t('内容超过二维码容量或二维码不可用，请复制完整链接或导出文件。',
                                    'QR unavailable or too large. Copy the complete link or export a file.')),
                              const SizedBox(height: 12),
                              Text(t('请勿公开分享。导入时请到“全局设置备份”粘贴链接或读取二维码图片。',
                                  'Keep private. Paste this link or import its QR image in Global settings backup.')),
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
                          child: Text(t('复制链接', 'Copy link'))),
                      if (image != null)
                        TextButton(
                            onPressed: () async {
                              await saveFileToDownload(
                                  bytes: image,
                                  fileName: 'Modu-settings-qr.png',
                                  mimeType: 'image/png');
                            },
                            child: Text(t('保存二维码', 'Save QR'))),
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(t('关闭', 'Close'))),
                    ],
                  ));
          return;
        }
        final date =
            DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
        final path = await saveFileToDownload(
            bytes: utf8.encode(text),
            fileName: 'Modu-settings-$date.json',
            mimeType: 'application/json');
        if (mounted && path != null) {
          setState(() => _status = t('$scopeLabel已导出。请妥善保存，不要公开分享。',
              '$scopeLabel exported. Keep the file private.'));
        }
      });

  bool _canImport() {
    if (ref.read(syncProvider).isSyncing ||
        bookKnowledgeIndexQueue.activeItems.isNotEmpty) {
      setState(() => _status = t('请等待同步、向量化任务结束后再导入。',
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

  Future<void> _importLink({bool image = false}) => _run(() async {
        if (!_canImport()) return;
        String? text;
        if (image) {
          final picked = await FilePicker.platform
              .pickFiles(type: FileType.image, allowMultiple: false);
          final path = picked?.files.single.path;
          if (path == null) return;
          text = await ConfigQrBridge.decodeImage(path);
          if (text == null) throw const FormatException('No QR code');
        } else {
          text = await showDialog<String>(
              context: context, builder: (_) => const _SettingsLinkDialog());
        }
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
      setState(() => _status = t('内容中没有可导入的设置，未作任何更改。',
          'No settings to import. Nothing was changed.'));
      return;
    }
    final scopeLabel = scopes.map(_scopeLabel).join(t('、', ', '));
    final disablesSync = GlobalSettingsTransfer.disablesSync(values);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(scopes.length == 1
                  ? t('恢复$scopeLabel？', 'Restore $scopeLabel?')
                  : t('恢复多项设置？', 'Restore multiple settings?')),
              content: SingleChildScrollView(
                child: Text(t(
                      '导入范围：$scopeLabel。\n\n仅覆盖内容中的 ${values.length - 1} 项设置（包括明确记录的默认值），未包含的设置保持不变。书籍、笔记、进度、存储路径和本机字体/背景文件不受影响。文件中包含的账号及密钥也会一并恢复。导入后请重启默读。',
                      'Import scope: $scopeLabel.\n\nReplace only the ${values.length - 1} included settings (including recorded defaults); settings not included stay unchanged. Books, notes, progress, storage paths and local font/background files are unaffected. Any accounts and keys included in the file will also be restored. Restart Modu afterwards.',
                    ) +
                    (disablesSync
                        ? t('\n\nWebDAV 及自动同步需手动重新开启。',
                            '\n\nRe-enable WebDAV and automatic sync manually.')
                        : '')),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(t('取消', 'Cancel'))),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(t('确认恢复', 'Restore')))
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
        (disablesSync ? t('同步需手动重新开启。', ' Re-enable sync manually.') : ''));
  }

  @override
  Widget build(BuildContext context) => Material(
      color: Colors.transparent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
        children: [
          Text(t('全局设置导入导出', 'Global settings transfer'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text(t(
              '一次迁移全部全局设置，文件、二维码和 modu 链接统一在这里导入导出。兼容旧版 AI、朗读、同步及书库链接，导入前会显示实际包含的设置。',
              'Transfer all global settings together via files, QR codes or modu links. Older AI, speech, sync and library links remain supported; the actual contents are shown before import.')),
          const SizedBox(height: 12),
          Text(t(
              '包含外观、阅读排版、CSS 方案、AI 技能、朗读、翻译及其他通用设置。不包含书籍、笔记、聊天记录、阅读进度、字体/背景图片文件、字典或向量模型。',
              'Export appearance, reading layout, CSS profiles, AI skills, speech, translation and general preferences. Books, notes, chats, reading progress, fonts/background files, dictionaries and vector models are not included.')),
          const SizedBox(height: 16),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('包含账号、密码和 API Key',
                  'Include accounts, passwords and API keys')),
              subtitle: Text(t(
                  '默认关闭：导出时排除、导入时跳过含凭据的 API 供应商和服务器配置，保留本机已有账号与密钥。开启后会一并迁移，文件、二维码和 modu 链接包含可还原的明文凭据，请勿公开分享。此开关不改变同步加密设置，同步加密密码不导出。自定义 CSS、提示词及网址请勿填写私密凭据。',
                  'Off by default: omit credential-bearing API/server configurations on export and skip them on import, preserving local accounts and keys. When enabled, transfers contain plaintext credentials. Keep them private. Sync encryption is unchanged and its password is never exported. Do not place private credentials in custom CSS, prompts or URLs.')),
              value: _includeSecrets,
              onChanged:
                  _busy ? null : (v) => setState(() => _includeSecrets = v)),
          const SizedBox(height: 20),
          FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.upload_file),
              label: Text(t('导出全局设置文件', 'Export global settings file'))),
          OutlinedButton.icon(
              onPressed: _busy ? null : () => _export(asLink: true),
              icon: const Icon(Icons.qr_code_2),
              label: Text(t('导出二维码 / modu 链接', 'Export QR / modu link'))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: _busy ? null : _import,
              icon: const Icon(Icons.settings_backup_restore),
              label: Text(t('从文件恢复设置', 'Restore settings from file'))),
          OutlinedButton.icon(
              onPressed: _busy ? null : () => _importLink(),
              icon: const Icon(Icons.link),
              label: Text(t('粘贴 modu 链接恢复', 'Restore from modu link'))),
          OutlinedButton.icon(
              onPressed: _busy ? null : () => _importLink(image: true),
              icon: const Icon(Icons.image_search),
              label: Text(t('从二维码图片恢复', 'Restore from QR image'))),
          if (_busy)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator())),
          if (_status != null)
            Padding(
                padding: const EdgeInsets.only(top: 16), child: Text(_status!)),
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
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return AlertDialog(
        title: Text(zh ? '粘贴 modu 链接' : 'Paste modu link'),
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
              child: Text(zh ? '取消' : 'Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _controller.text),
              child: Text(zh ? '继续' : 'Continue'))
        ]);
  }
}
