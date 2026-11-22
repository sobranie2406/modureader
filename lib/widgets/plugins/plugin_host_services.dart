import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/providers/chapter_content_bridge.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_host_api.dart';
import 'package:modu_reader/widgets/plugins/plugin_permission_sheet.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Builds the native surfaces [PluginHostApi] needs from a live widget context.
///
/// Kept out of the runtime on purpose: the runtime must stay testable without
/// a widget tree, so the page supplies these and a test supplies none.
PluginHostServices buildPluginHostServices(
  BuildContext context, {
  required PluginHost host,
  required String pluginId,
  Book? book,
  String chapter = '',
  CurrentChapterContentFetcher? currentChapter,
  ChapterContentByHrefFetcher? chapterByHref,
  required bool Function() isCurrent,
}) {
  String t(String zh, String en) => ModuStrings.text(context, zh, en);
  return PluginHostServices(
    reader: book == null
        ? null
        : PluginReaderSnapshot(
            book: book,
            chapter: chapter,
            currentChapter: currentChapter,
            chapterByHref: chapterByHref,
          ),
    copyToClipboard: (text) => Clipboard.setData(ClipboardData(text: text)),
    readClipboard: () async {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      return data?.text;
    },
    shareText: (text, subject) async {
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(ShareParams(
        text: text,
        subject: subject,
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
    },
    openUrl: (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    // Consent always goes through the same sheet, whether the plugin asked on
    // its own initiative or the user opened the permission page.
    requestPermissions: (id, capabilities, reason) =>
        showPluginPermissionRequest(context,
            host: host,
            pluginId: id,
            capabilities: capabilities,
            reason: reason,
            isCurrent: isCurrent),
    grantedPermissions: (id) async => host.grantedPermissions(id),
    askConfirm: (title, message) async {
      if (!context.mounted) return false;
      final answer = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                title: Text(title),
                content: SingleChildScrollView(child: Text(message)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: Text(t('取消', 'Cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: Text(t('继续', 'Continue'))),
                ],
              ));
      return answer == true;
    },
    askPrompt: (title, message, initial) async {
      if (!context.mounted) return null;
      final controller = TextEditingController(text: initial ?? '');
      final answer = await showDialog<String>(
          context: context,
          builder: (dialog) => AlertDialog(
                title: Text(title),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (message.isNotEmpty) Text(message),
                  TextField(
                      controller: controller, maxLength: 500, autofocus: true),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: Text(t('取消', 'Cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, controller.text),
                      child: Text(t('确定', 'OK'))),
                ],
              ));
      controller.dispose();
      return answer;
    },
    askSelect: (title, options) async {
      if (!context.mounted) return null;
      return showDialog<String>(
          context: context,
          builder: (dialog) => SimpleDialog(
                title: Text(title),
                children: [
                  for (final option in options)
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(dialog, option),
                        child: Text(option)),
                ],
              ));
    },
    showProgress: (label, fraction) async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (label.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child:
                    Align(alignment: Alignment.centerLeft, child: Text(label))),
          LinearProgressIndicator(value: fraction),
        ]),
      ));
    },
  );
}
