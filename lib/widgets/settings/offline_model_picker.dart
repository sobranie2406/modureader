import 'dart:io';

import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

Future<List<File>?> pickOfflineModelFiles(
    BuildContext context, String model, String instructions) async {
  String t(String zh, String en) => ModuStrings.text(context, zh, en);
  final proceed = await showDialog<bool>(
    context: context,
    animationStyle: AppMotion.style,
    builder: (context) => AlertDialog(
      title: Text(t('离线导入 · $model', 'Offline import · $model')),
      content: Text(
          '$instructions\n\n${t("同时选择所选型号的全部模型文件。", "Select all files for the chosen model.")}'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel'))),
        TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('选择文件', 'Choose files'))),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return null;
  final result = await FilePicker.platform
      .pickFiles(allowMultiple: true, type: FileType.any, withData: false);
  if (result == null) return null;
  if (result.files.any((file) => file.path == null)) {
    throw const FileSystemException('Selected files are not accessible');
  }
  return result.files.map((file) => File(file.path!)).toList();
}
