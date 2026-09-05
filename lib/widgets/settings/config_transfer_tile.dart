import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/service/config_transfer/config_qr_bridge.dart';
import 'package:anx_reader/service/config_transfer/config_transfer_codec.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef ConfigTransferDataBuilder = Map<String, dynamic> Function();
typedef ConfigTransferImporter = FutureOr<void> Function(
  Map<String, dynamic> data,
);

class ConfigTransferTile extends AbstractSettingsTile {
  const ConfigTransferTile({
    super.key,
    required this.kind,
    required this.label,
    required this.getData,
    required this.applyData,
  });

  final String kind;
  final String label;
  final ConfigTransferDataBuilder getData;
  final ConfigTransferImporter applyData;

  String _text(BuildContext context, String zh, String en) {
    return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _text(context, '配置迁移', 'Configuration transfer'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            _text(
              context,
              '通过配置代码或二维码迁移 $label。配置包含密码或 API Key，请勿公开分享。',
              'Transfer $label with a code or QR image. It may contain passwords or API keys; keep it private.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => _showExport(context),
                icon: const Icon(Icons.qr_code_2),
                label: Text(_text(context, '导出 $label', 'Export $label')),
              ),
              OutlinedButton.icon(
                onPressed: () => _showImport(context),
                icon: const Icon(Icons.download),
                label: Text(_text(context, '导入 $label', 'Import $label')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showExport(BuildContext context) async {
    late final String token;
    try {
      token = ConfigTransferCodec.encode(kind: kind, data: getData());
    } catch (error) {
      if (context.mounted) {
        _message(
            context, _text(context, '导出失败：$error', 'Export failed: $error'));
      }
      return;
    }

    Uint8List? qrBytes;
    String? qrError;
    if (ConfigQrBridge.isSupported) {
      try {
        qrBytes = await ConfigQrBridge.generate(token);
      } on PlatformException catch (error) {
        qrError = error.message;
      } catch (_) {
        qrError = _text(context, '二维码生成失败', 'Could not generate QR code');
      }
    }
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_text(context, '导出 $label', 'Export $label')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (qrBytes != null) ...[
                  Center(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: Colors.white),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Image.memory(
                          qrBytes,
                          width: 240,
                          height: 240,
                          filterQuality: FilterQuality.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _text(
                      context,
                      '在另一台设备扫描二维码，或复制下方配置代码导入。',
                      'Scan this QR code on another device, or copy the configuration code below.',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  Text(
                    qrError ??
                        _text(
                          context,
                          '当前平台暂不支持二维码，请复制配置代码。',
                          'QR export is unavailable on this platform. Copy the code instead.',
                        ),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 12),
                ],
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: _text(context, '配置代码', 'Configuration code'),
                    border: const OutlineInputBorder(),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 110),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        token,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _text(
                          context,
                          '配置代码和二维码不是加密数据，可能包含密码或 API Key。',
                          'The code and QR image are not encrypted and may contain passwords or API keys.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: token));
              if (dialogContext.mounted) {
                _message(
                  dialogContext,
                  _text(context, '配置代码已复制', 'Configuration code copied'),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: Text(_text(context, '复制代码', 'Copy code')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_text(context, '关闭', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showImport(BuildContext context) async {
    final imported = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfigImportDialog(
        kind: kind,
        label: label,
        applyData: applyData,
      ),
    );
    if (imported == true && context.mounted) {
      _message(context, _text(context, '$label 已导入', '$label imported'));
    }
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ConfigImportDialog extends StatefulWidget {
  const _ConfigImportDialog({
    required this.kind,
    required this.label,
    required this.applyData,
  });

  final String kind;
  final String label;
  final ConfigTransferImporter applyData;

  @override
  State<_ConfigImportDialog> createState() => _ConfigImportDialogState();
}

class _ConfigImportDialogState extends State<_ConfigImportDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;
  bool _readingQr = false;

  String _text(String zh, String en) {
    return Localizations.localeOf(context).languageCode == 'zh' ? zh : en;
  }

  String _friendlyError(Object error) {
    if (error is FormatException) return error.message.toString();
    if (error is PlatformException) {
      return error.message ?? _text('二维码读取失败', 'Could not read QR code');
    }
    return _text('配置格式无效', 'Invalid configuration');
  }

  Future<void> _readQrImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final filePath = picked?.files.single.path;
    if (filePath == null || !mounted) return;
    setState(() {
      _readingQr = true;
      _errorText = null;
    });
    try {
      final value = await ConfigQrBridge.decodeImage(filePath);
      if (value == null || value.trim().isEmpty) {
        throw const FormatException('图片中没有识别到二维码');
      }
      _controller.text = value.trim();
    } catch (error) {
      if (mounted) setState(() => _errorText = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _readingQr = false);
    }
  }

  Future<void> _importConfig() async {
    setState(() => _errorText = null);
    try {
      final decoded = ConfigTransferCodec.decode(_controller.text);
      if (decoded.source == ConfigTransferSource.modu &&
          decoded.kind != widget.kind) {
        throw FormatException(
          _text(
            '该代码不是 ${widget.label}',
            'This code is not ${widget.label}',
          ),
        );
      }
      await Future<void>.sync(() => widget.applyData(decoded.data));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _errorText = _friendlyError(error));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_text('导入 ${widget.label}', 'Import ${widget.label}')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                minLines: 4,
                maxLines: 8,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  labelText: _text('配置代码', 'Configuration code'),
                  hintText: _text(
                    '粘贴 modu: 或 readany: 开头的代码',
                    'Paste a code beginning with modu: or readany:',
                  ),
                  errorText: _errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (ConfigQrBridge.isSupported) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _readingQr ? null : _readQrImage,
                  icon: _readingQr
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.image_search),
                  label: Text(
                    _text('从二维码图片读取', 'Read from QR image'),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                _text(
                  '导入将替换当前 ${widget.label}。ReadAny 口令也可直接粘贴，兼容字段会自动转换。',
                  'Importing replaces the current ${widget.label}. ReadAny tokens are accepted and compatible fields are converted.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(_text('取消', 'Cancel')),
        ),
        FilledButton.icon(
          onPressed: _importConfig,
          icon: const Icon(Icons.download),
          label: Text(_text('导入配置', 'Import configuration')),
        ),
      ],
    );
  }
}
