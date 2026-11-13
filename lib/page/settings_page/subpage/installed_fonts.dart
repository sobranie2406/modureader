import 'package:modu_reader/widgets/settings/font_name_preview.dart';
import 'dart:io';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/page/reading_page.dart';
import 'package:modu_reader/providers/font_list.dart';
import 'package:modu_reader/providers/fonts.dart';
import 'package:modu_reader/service/installed_fonts.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:modu_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class InstalledFontsPage extends ConsumerStatefulWidget {
  const InstalledFontsPage({super.key});

  @override
  ConsumerState<InstalledFontsPage> createState() => _InstalledFontsPageState();
}

class _InstalledFontsPageState extends ConsumerState<InstalledFontsPage> {
  bool _busy = false;
  String t(String zh, String en) => ModuStrings.text(context, zh, en);

  bool get _downloading => ref.read(fontDownloadsProvider).values.any((value) =>
      value.status == DownloadStatus.downloading ||
      value.status == DownloadStatus.paused);

  Future<void> _remove(String filename) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('移除字体？', 'Remove font?')),
        content: Text(
            '$filename\n\n${t("删除此字体？正在使用它的内容将改用默认字体。", "Delete this font? Text using it will switch to the default font.")}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('移除', 'Remove'))),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy || _downloading) return;
    setState(() => _busy = true);
    try {
      final changed =
          await removeInstalledFont(filename, directory: getFontDir());
      ref.invalidate(fontListProvider);
      ref.invalidate(fontPreviewProvider);
      final reader = epubPlayerKey.currentState;
      if (reader != null && reader.mounted) {
        if (changed.contains('font')) reader.changeFont(Prefs().font);
        if (changed.contains('englishFont')) {
          reader.changeEnglishFont(Prefs().englishFont);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t(
              '无法移除字体，请稍后重试。', 'Could not remove the font. Please try again.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(fontDownloadsProvider);
    List<File> files;
    try {
      files = installedFontFiles(getFontDir());
    } on FileSystemException {
      return Scaffold(
          appBar: AppBar(title: Text(t('管理已安装字体', 'Manage installed fonts'))),
          body: Center(
              child: Text(t('无法读取字体目录，请稍后重试。',
                  'Could not read the font directory. Please try again.'))));
    }
    final downloading = _downloading;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(t('管理已安装字体', 'Manage installed fonts'))),
        body: SafeArea(
            child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(t("管理下载和导入的字体。",
                          "Manage downloaded and imported fonts."))),
                  if (downloading)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(t('请先完成或取消字体下载，再移除字体。',
                            'Finish or cancel font downloads before removing fonts.'))),
                  if (files.isEmpty)
                    Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(t('暂无已安装字体', 'No installed fonts'))),
                  for (final file in files)
                    FilledContainer(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.font_download_outlined),
                        title: FontNamePreview(file.uri.pathSegments.last,
                            filename: file.uri.pathSegments.last),
                        subtitle:
                            file.uri.pathSegments.last == bundledFontFilename
                                ? Text(t('应用内置', 'Bundled with the app'))
                                : null,
                        trailing: file.uri.pathSegments.last ==
                                bundledFontFilename
                            ? const Icon(Icons.lock_outline)
                            : IconButton(
                                tooltip: t('移除字体', 'Remove font'),
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _busy || downloading
                                    ? null
                                    : () =>
                                        _remove(file.uri.pathSegments.last)),
                      ),
                    ),
                ]),
          ),
        )),
      ),
    );
  }
}
