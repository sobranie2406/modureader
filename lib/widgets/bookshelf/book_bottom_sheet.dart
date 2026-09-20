import 'dart:io';
import 'dart:math';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/service/convert_to_epub/txt/convert_from_txt.dart';
import 'package:anx_reader/service/md5_service.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/share_file.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/bookshelf/book_knowledge_actions.dart';
import 'package:anx_reader/widgets/bookshelf/book_embedding_model_dialog.dart';
import 'package:anx_reader/service/knowledge/book_embedding_preferences.dart';
import 'package:anx_reader/widgets/icon_and_text.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:path/path.dart' as p;

enum BookAction {
  details,
  vectorize,
  vectorModel,
  share,
  replace,
  release,
  delete
}

class BookBottomSheet extends ConsumerWidget {
  const BookBottomSheet({
    super.key,
    required this.book,
    this.menuOnly = false,
    this.menuKey,
    this.child,
  });

  final Book book;

  /// Both the cover button and the drag bottom bar use this same menu.
  final bool menuOnly;
  final GlobalKey<PopupMenuButtonState<BookAction>>? menuKey;
  final Widget? child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> handleDelete(BuildContext context) async {
      final deleted =
          await confirmAndDeleteBooksFromBookshelf(context, ref, [book]);
      if (deleted && !menuOnly && context.mounted) Navigator.pop(context);
    }

    void handleDetail(BuildContext context) {
      final navigator = Navigator.of(context);
      if (!menuOnly) navigator.pop();
      navigator.push(
        MaterialPageRoute(
          builder: (context) => BookDetail(book: book),
        ),
      );
    }

    void handleUpload(BuildContext context) {
      Future<void> core() async {
        await ref.read(syncProvider.notifier).releaseBook(book);
        ref.read(syncStatusProvider.notifier).refresh();
      }

      if (Prefs().shouldShowHint(HintKey.releaseLocalSpace)) {
        SmartDialog.show(
          builder: (context) => AlertDialog(
            title: Text(L10n.of(context).bookSyncStatusReleaseSpaceDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(L10n.of(context).bookSyncStatusReleaseSpaceDialogContent),
                Row(
                  children: [
                    StatefulBuilder(builder: (context, setState) {
                      return Checkbox(
                          value: !Prefs()
                              .shouldShowHint(HintKey.releaseLocalSpace),
                          onChanged: (value) {
                            value = !(value ?? false);
                            Prefs()
                                .setShowHint(HintKey.releaseLocalSpace, value);
                            setState(() {});
                          });
                    }),
                    Text(L10n.of(context).bookSyncStatusDoNotShowAgain),
                  ],
                )
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  SmartDialog.dismiss();
                },
                child: Text(L10n.of(context).commonCancel),
              ),
              TextButton(
                onPressed: () {
                  SmartDialog.dismiss();
                  core();
                },
                child: Text(L10n.of(context).commonConfirm),
              ),
            ],
          ),
        );
      } else {
        ref.read(syncProvider.notifier).releaseBook(book);
      }
    }

    Future<void> handleShare() async {
      await shareFile(
        title: '${book.title}.${book.filePath.split('.').last}',
        filePath: book.fileFullPath,
      );
    }

    String formatSize(int bytes) {
      if (bytes <= 0) return '0 B';
      const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
      var i = (log(bytes) / log(1024)).floor();
      return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
    }

    Future<void> handleReplace(BuildContext context) async {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null) return;
      PlatformFile newFile = result.files.first;
      String extension =
          p.extension(newFile.name).replaceAll('.', '').toLowerCase();
      if (!allowBookExtensions.contains(extension)) {
        AnxToast.show(
            L10n.of(context).bookBottomSheetUnsupportedFileFormat(extension));
        return;
      }

      File newFileObj = File(newFile.path!);

      if (!context.mounted) return;

      int newSize = await newFileObj.length();
      int oldSize = 0;
      if (await File(book.fileFullPath).exists()) {
        oldSize = await File(book.fileFullPath).length();
      }

      bool? confirm = await SmartDialog.show(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).commonAttention),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(L10n.of(context)
                  .bookBottomSheetOriginalFileSize(formatSize(oldSize))),
              Text(L10n.of(context)
                  .bookBottomSheetNewFileSize(formatSize(newSize))),
              const SizedBox(height: 10),
              Text(
                L10n.of(context).bookBottomSheetReplaceWarning,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                SmartDialog.dismiss(result: false);
              },
              child: Text(L10n.of(context).commonCancel),
            ),
            TextButton(
              onPressed: () {
                SmartDialog.dismiss(result: true);
              },
              child: Text(L10n.of(context).commonConfirm),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      try {
        String extension = p.extension(newFile.name);
        File fileToProcess = newFileObj;

        // Convert TXT to EPUB if needed
        if (extension.toLowerCase() == '.txt') {
          fileToProcess = await convertFromTxt(newFileObj);
          extension = '.epub';
        }

        String title = book.title;
        String nameWithoutExtension =
            '${title.length > 20 ? title.substring(0, 20) : title}-${DateTime.now().millisecondsSinceEpoch}'
                .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
                .replaceAll('\n', '')
                .replaceAll('\r', '')
                .trim();
        String newFileName = '$nameWithoutExtension$extension';
        String newRelativePath = 'file/$newFileName';
        String newDestPath = getBasePath(newRelativePath);

        // Copy new file
        await fileToProcess.copy(newDestPath);

        // Calculate MD5
        String? newMd5 = await MD5Service.calculateFileMd5(newDestPath);

        // Drain the old file's worker before changing its identity.
        await bookKnowledgeIndexQueue.cancelAndRemove(book.id);
        final replacement = book.copyWith(
          filePath: newRelativePath,
          md5: newMd5,
          updateTime: DateTime.now(),
        );
        await bookDao.updateBook(replacement);
        await BookKnowledgeIndexService().deleteIndex(book);
        enqueueImportedBookForAutomaticIndexing(
          book: replacement,
          vectorModelEnabled: Prefs().vectorModelEnabled,
          autoVectorizeOnImport: Prefs().autoVectorizeOnImport,
        );

        // Delete old file if path is different
        if (book.fileFullPath != newDestPath) {
          final oldFile = File(book.fileFullPath);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        }

        // Clean up temporary file if TXT conversion happened
        if (fileToProcess != newFileObj) {
          if (await fileToProcess.exists()) {
            await fileToProcess.delete();
          }
        }

        ref.read(bookListProvider.notifier).refresh();
        if (!menuOnly && context.mounted) Navigator.pop(context);

        if (Prefs().webdavStatus) {
          ref.read(syncProvider.notifier).syncData(SyncDirection.upload, ref);
        }
      } catch (e) {
        AnxToast.show(
            L10n.of(context).bookBottomSheetReplaceFailed(e.toString()));
      }
    }

    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final menu = AnimatedBuilder(
      animation: bookKnowledgeIndexQueue,
      builder: (context, _) => FutureBuilder<bool>(
        future: BookKnowledgeIndexService().hasIndex(book),
        builder: (context, snapshot) {
          final item = bookKnowledgeIndexQueue.itemFor(book.id);
          final active = item?.status.isActive ?? false;
          final indexed = snapshot.data == true ||
              item?.status == BookKnowledgeQueueStatus.completed;
          final local = File(book.fileFullPath).existsSync();
          PopupMenuItem<BookAction> entry(
                  BookAction action, IconData icon, String label,
                  {bool enabled = true, String? subtitle}) =>
              PopupMenuItem<BookAction>(
                key: ValueKey('book-action-${action.name}'),
                value: action,
                enabled: enabled,
                child: ListTile(
                  dense: true,
                  enabled: enabled,
                  textColor: action == BookAction.delete ? Colors.red : null,
                  iconColor: action == BookAction.delete ? Colors.red : null,
                  leading: Icon(icon),
                  title: Text(label),
                  subtitle: subtitle == null ? null : Text(subtitle),
                ),
              );
          return PopupMenuButton<BookAction>(
            key: menuKey,
            tooltip: zh ? '书籍操作' : 'Book actions',
            color: Theme.of(context).colorScheme.surfaceContainer,
            onSelected: (action) async {
              switch (action) {
                case BookAction.details:
                  handleDetail(context);
                  break;
                case BookAction.vectorize:
                  await queueBookForVectorization(book);
                  break;
                case BookAction.vectorModel:
                  await showBookEmbeddingModelDialog(context, book);
                  break;
                case BookAction.share:
                  await handleShare();
                  break;
                case BookAction.replace:
                  await handleReplace(context);
                  break;
                case BookAction.release:
                  handleUpload(context);
                  break;
                case BookAction.delete:
                  await handleDelete(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              entry(BookAction.details, Icons.info_outline,
                  zh ? '书籍详情' : 'Book details'),
              entry(
                  BookAction.vectorize,
                  active
                      ? Icons.hourglass_top_rounded
                      : indexed
                          ? Icons.refresh
                          : Icons.hub_outlined,
                  _vectorActionLabel(indexed, item, zh),
                  enabled: !active),
              entry(BookAction.vectorModel, Icons.tune,
                  zh ? '向量化模型' : 'Embedding model',
                  enabled: !active,
                  subtitle: BookEmbeddingPreferences.labelFor(book)),
              const PopupMenuDivider(),
              entry(
                  BookAction.share, EvaIcons.share, L10n.of(context).shareFile,
                  enabled: local),
              entry(BookAction.replace, EvaIcons.refresh,
                  L10n.of(context).bookBottomSheetReplaceFile),
              entry(BookAction.release, EvaIcons.cloud_upload,
                  L10n.of(context).bookSyncStatusReleaseSpace,
                  enabled: local && Prefs().webdavStatus && !active),
              const PopupMenuDivider(),
              entry(BookAction.delete, Icons.delete_outline,
                  L10n.of(context).commonDelete),
            ],
            child: child ??
                IconAndText(
                  icon: const Icon(EvaIcons.more_vertical),
                  text: L10n.of(context).more,
                ),
          );
        },
      ),
    );
    if (menuOnly) return menu;
    return Container(
      padding: const EdgeInsets.all(20),
      constraints: const BoxConstraints(minHeight: 112),
      child: Row(
        children: [
          SizedBox(height: 60, child: BookCover(book: book, width: 40)),
          const SizedBox(width: 10),
          Expanded(
              child: SingleChildScrollView(
            child: Text(book.title,
                style: Theme.of(context).textTheme.titleMedium),
          )),
          menu,
        ],
      ),
    );
  }
}

String _vectorActionLabel(bool indexed, BookKnowledgeQueueItem? item, bool zh) {
  final status = item?.status;
  if (status == BookKnowledgeQueueStatus.queued) return zh ? '排队中' : 'Queued';
  if (status == BookKnowledgeQueueStatus.cancelling)
    return zh ? '正在取消' : 'Cancelling';
  if (status?.isActive == true) return zh ? '正在向量化' : 'Indexing';
  if (status == BookKnowledgeQueueStatus.failed)
    return zh ? '重新排队' : 'Retry indexing';
  return indexed ? (zh ? '重新向量化' : 'Reindex') : (zh ? '向量化' : 'Vectorize');
}
