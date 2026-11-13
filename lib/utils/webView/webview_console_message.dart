import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/utils/platform_utils.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

const minWebviewVersion = 70;
void showUnsupportedWebviewDialog(int version,
    {int minimum = minWebviewVersion}) {
  SmartDialog.show(
    animationType: SmartAnimationType.fade,
    builder: (context) {
      return AlertDialog(
        title: const Center(
          child: Icon(Icons.warning_rounded),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L10n.of(context).webviewUnsupportedVersion,
                style: Theme.of(context).textTheme.titleMedium),
            Text(L10n.of(context).webviewUnsupportedMessage(minimum, version)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () {
                SmartDialog.dismiss();
              },
              child: Text(L10n.of(context).webviewCancel)),
        ],
      );
    },
  );
}

int? unsupportedWebviewVersion(String message, {required bool isApple}) {
  if (!RegExp(r'^(?:ModuUA|AnxUA)\s+').hasMatch(message)) return null;
  final match = RegExp(isApple ? r'AppleWebKit/(\d+)' : r'Chrome/(\d+)')
      .firstMatch(message);
  final version = int.tryParse(match?.group(1) ?? '');
  return version != null && version < (isApple ? 605 : minWebviewVersion)
      ? version
      : null;
}

void handleWebviewVersion(String message) {
  final isApple = AnxPlatform.isIOS || AnxPlatform.isMacOS;
  final version = unsupportedWebviewVersion(message, isApple: isApple);
  if (version != null) {
    showUnsupportedWebviewDialog(version,
        minimum: isApple ? 605 : minWebviewVersion);
  }
}

void webviewConsoleMessage(
  InAppWebViewController controller,
  ConsoleMessage consoleMessage,
) {
  const ignoreMsg = [
    'JavaScript execution returned a result of an unsupported type'
  ];
  if (ignoreMsg.contains(consoleMessage.message)) {
    return;
  }

  if (consoleMessage.messageLevel == ConsoleMessageLevel.LOG) {
    AnxLog.info('Webview: ${consoleMessage.message}');
    if (RegExp(r'^(?:ModuUA|AnxUA)\s+').hasMatch(consoleMessage.message)) {
      handleWebviewVersion(consoleMessage.message);
    }
  } else if (consoleMessage.messageLevel == ConsoleMessageLevel.WARNING) {
    AnxLog.warning('Webview: ${consoleMessage.message}');
  } else if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR) {
    AnxLog.severe('Webview: ${consoleMessage.message}');
  }
}
