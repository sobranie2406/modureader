import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SettingsExportDestination {
  const SettingsExportDestination({required this.path, required this.fileName});

  final String path;
  final String fileName;

  // Android SAF providers may return a content URI or just its document path.
  // Neither is a filesystem path that the user can paste into a file manager.
  bool get isSystemDocument =>
      Uri.tryParse(path)?.scheme == 'content' ||
      path.startsWith('/document/') ||
      path.startsWith('/tree/');

  String get copyValue => isSystemDocument ? fileName : path;

  String status({required bool zh}) => isSystemDocument
      ? (zh
          ? '已保存到系统保存窗口中选择的位置。\n建议文件名：$fileName\n若在保存窗口修改了名称，请按实际文件名查找。'
          : 'Saved to the location selected in the system save dialog.\nSuggested file name: $fileName\nIf you renamed it there, look for the chosen name.')
      : (zh ? '已保存至：\n$path' : 'Saved to:\n$path');
}

class SettingsExportDialog extends StatelessWidget {
  const SettingsExportDialog({super.key, required this.destination});

  final SettingsExportDestination destination;

  @override
  Widget build(BuildContext context) {
    final document = destination.isSystemDocument;
    return AlertDialog(
      title: Text(ModuStrings.text(context, '导出成功', 'Export complete')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(document
                ? (ModuStrings.text(context, '建议文件名：', 'Suggested file name:'))
                : (ModuStrings.text(context, '文件已保存至：', 'File saved to:'))),
            const SizedBox(height: 8),
            SelectableText(destination.copyValue),
            if (document) ...[
              const SizedBox(height: 12),
              Text(ModuStrings.text(context, '已保存到你在系统保存窗口选择的位置，可用系统文件管理器查找。若修改了文件名，请以保存窗口中的名称为准。', 'Saved to the location you selected in the system save dialog. Find it in your file manager using the name you chose there.')),
            ],
            const SizedBox(height: 16),
            Text(ModuStrings.text(context, '请妥善保管，不要公开分享。', 'Keep this file private.')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: destination.copyValue)),
          child: Text(document
              ? (ModuStrings.text(context, '复制文件名', 'Copy file name'))
              : (ModuStrings.text(context, '复制保存位置', 'Copy location'))),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ModuStrings.text(context, '完成', 'Done')),
        ),
      ],
    );
  }
}
