import 'package:anx_reader/utils/app_motion.dart';
import 'dart:io';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/notes/reading_link.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Called only after the home page and database are ready. External links are
/// data references, never paths, scripts, or permission to import settings.
Future<void> openReadingLink(
    String raw, BuildContext context, WidgetRef ref) async {
  final chinese = Localizations.localeOf(context).languageCode == 'zh';
  String tr(String zh, String en) => chinese ? zh : en;
  Future<void> explain(String message) async {
    if (!context.mounted) return;
    await showDialog<void>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text(tr('返回原文', 'Open in Modu')),
              content: Text(message),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(tr('知道了', 'OK')))
              ],
            ));
  }

  try {
    if (AnxPlatform.isWindows || AnxPlatform.isMacOS || AnxPlatform.isLinux) {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    }
    final link = ReadingLink.parse(raw);
    final books = await bookDao.selectBooks(includeDeleted: false);
    final matches = link.matches(books);
    if (!context.mounted) return;
    if (matches.isEmpty) {
      final differentEdition =
          books.any((b) => b.title == link.title && b.author == link.author);
      await explain(differentEdition
          ? tr('书架中的书籍版本与笔记不一致，请导入原版本，或从当前版本重新导出笔记。',
              'The book edition differs from this note. Import the original edition or export new notes from the current edition.')
          : tr('书架中未找到这本书，请先导入或同步书籍，再点击链接。',
              'Book not found. Import or sync the book, then open this link again.'));
      return;
    }
    Book? book = matches.first;
    if (matches.length > 1) {
      book = await showDialog<Book>(
          animationStyle: AppMotion.style,
          context: context,
          builder: (dialogContext) => SimpleDialog(
                title: Text(tr('选择要打开的书籍', 'Choose a book')),
                children: [
                  for (final item in matches)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialogContext, item),
                      child: Text(
                          '${item.title}\n${item.author} · ${item.createTime.toLocal()}'),
                    )
                ],
              ));
    }
    if (book == null || !context.mounted) return;
    if (!await File(book.fileFullPath).exists()) {
      if (!context.mounted) return;
      final download = await showDialog<bool>(
          animationStyle: AppMotion.style,
          context: context,
          builder: (dialogContext) => AlertDialog(
                title: Text(tr('书籍尚未下载', 'Book not downloaded')),
                content: Text(tr('是否下载《${book!.title}》并返回原文？',
                    'Download “${book.title}” and open the original passage?')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(tr('取消', 'Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(tr('下载', 'Download'))),
                ],
              ));
      if (download != true || !context.mounted) return;
      await ref.read(syncProvider.notifier).downloadBook(book);
      book = await bookDao.selectBookById(book.id);
      if (link.matches([book]).isEmpty ||
          !await File(book.fileFullPath).exists()) {
        await explain(tr('书籍未能下载，或同步后的版本已变化。请在书架检查后重试。',
            'Download failed or the edition changed during sync. Check the bookshelf and retry.'));
        return;
      }
    }
    if (!context.mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final readerContext = epubPlayerKey.currentContext;
    final oldRoute =
        readerContext == null ? null : ModalRoute.of(readerContext);
    final reading = ref.read(currentReadingProvider);
    await audioHandler.stop();
    if (!context.mounted) return;
    if (reading.isReading && reading.book?.id == book.id && oldRoute != null) {
      navigator.popUntil((route) => route == oldRoute || route.isFirst);
      epubPlayerKey.currentState?.goToLinkedCfi(link.cfi);
      return;
    }
    navigator.popUntil((route) => route.isFirst);
    // Wait for the previous reader's global keys and provider cleanup before
    // creating another reader. Route.popped alone precedes its disposal.
    if (oldRoute != null) await oldRoute.completed;
    if (!context.mounted) return;
    await pushToReadingPage(ref, context, book,
        cfi: link.cfi, waitForClose: false);
    // A following link must see the newly mounted reader and its route.
    await WidgetsBinding.instance.endOfFrame;
  } on FormatException {
    await explain(tr('原文链接无效或版本不受支持，请重新导出笔记。',
        'Invalid or unsupported reading link. Export the notes again.'));
  } catch (_) {
    await explain(tr('暂时无法返回原文，请检查书籍文件后重试。',
        'Unable to open the passage. Check the book file and retry.'));
  }
}
