import 'dart:io';

import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/main.dart';
import 'package:modu_reader/utils/harmony_file_share.dart';
import 'package:modu_reader/utils/platform_utils.dart';
import 'package:modu_reader/utils/toast/common.dart';
import 'package:modu_reader/widgets/show_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareFile({
  File? file,
  String? filePath,
  String? title,
}) async {
  if (filePath == null && file == null) {
    return;
  }
  filePath ??= file?.path;

  if (AnxPlatform.isOhos) {
    showLoading();
    try {
      await shareHarmonyFile(sourceFilePath: filePath!, title: title);
    } catch (_) {
      final context = navigatorKey.currentContext;
      const message =
          'Sharing failed. Check that the file is downloaded and retry.';
      AnxToast.show(context == null || !context.mounted
          ? message
          : ModuStrings.text(context, '分享失败，请确认文件已下载到本机后重试', message));
    } finally {
      await SmartDialog.dismiss();
    }
    return;
  }

  showLoading();
  final box = navigatorKey.currentContext!.findRenderObject() as RenderBox?;
  await SharePlus.instance.share(ShareParams(
    title: title ?? filePath?.split('/').last ?? 'file',
    files: [XFile(filePath ?? '')],
    sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size,
  ));
  SmartDialog.dismiss();
}
