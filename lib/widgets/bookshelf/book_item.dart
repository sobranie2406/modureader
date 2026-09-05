import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/book_sync_status.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:anx_reader/widgets/bookshelf/book_bottom_sheet.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/bookshelf/book_knowledge_actions.dart';
import 'package:anx_reader/widgets/bookshelf/book_sync_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _BookCardAction { details, vectorize, more, delete }

typedef BookSelectionChanged = void Function(Book book, bool selected);

class BookItem extends ConsumerWidget {
  const BookItem({
    super.key,
    required this.book,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
  });

  final Book book;
  final bool selectionMode;
  final bool selected;
  final BookSelectionChanged? onSelectionChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuKey = GlobalKey<PopupMenuButtonState<_BookCardAction>>();
    void toggleSelection() {
      onSelectionChanged?.call(book, !selected);
    }

    Future<void> handleLongPress(BuildContext context) async {
      if (selectionMode) {
        toggleSelection();
        return;
      }
      menuKey.currentState?.showButtonMenu();
    }

    final bookSyncStatus =
        ref.watch(syncStatusProvider).whenOrNull(data: (data) {
              if (data.downloading.contains(book.id)) {
                return BookSyncStatusEnum.downloading;
              } else if (data.uploading.contains(book.id)) {
                return BookSyncStatusEnum.uploading;
              } else if (data.localOnly.contains(book.id)) {
                return BookSyncStatusEnum.localOnly;
              } else if (data.remoteOnly.contains(book.id)) {
                return BookSyncStatusEnum.remoteOnly;
              } else if (data.both.contains(book.id)) {
                return BookSyncStatusEnum.both;
              } else if (data.nonExistent.contains(book.id)) {
                return BookSyncStatusEnum.nonExistent;
              }
              return BookSyncStatusEnum.checking;
            }) ??
            BookSyncStatusEnum.checking;

    return AnimatedBuilder(
      animation: bookKnowledgeIndexQueue,
      builder: (context, _) {
        final queueItem = bookKnowledgeIndexQueue.itemFor(book.id);
        return GestureDetector(
          onTap: selectionMode
              ? toggleSelection
              : () => pushToReadingPage(ref, context, book),
          onLongPress: () => handleLongPress(context),
          onSecondaryTap: () => handleLongPress(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Hero(
                  tag: book.coverFullPath,
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        if (!Prefs().eInkMode)
                          BoxShadow(
                            color: Colors.grey.withAlpha(100),
                            spreadRadius: 5,
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BookCover(book: book),
                        FutureBuilder<bool>(
                          future: BookKnowledgeIndexService().hasIndex(book),
                          builder: (context, snapshot) {
                            final indexed = snapshot.data == true ||
                                queueItem?.status ==
                                    BookKnowledgeQueueStatus.completed;
                            return Stack(
                              children: [
                                if (indexed || queueItem != null)
                                  Positioned(
                                    left: 8,
                                    top: 8,
                                    child: _KnowledgeStatusBadge(
                                      indexed: indexed,
                                      item: queueItem,
                                    ),
                                  ),
                                if (selectionMode)
                                  Positioned(
                                    right: 7,
                                    top: 7,
                                    child: _SelectionIndicator(
                                      selected: selected,
                                    ),
                                  )
                                else
                                  Positioned(
                                    right: 6,
                                    bottom: 6,
                                    child: PopupMenuButton<_BookCardAction>(
                                      key: menuKey,
                                      tooltip: '书籍操作',
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainer,
                                      onSelected: (action) async {
                                        switch (action) {
                                          case _BookCardAction.details:
                                            await Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    BookDetail(book: book),
                                              ),
                                            );
                                            break;
                                          case _BookCardAction.vectorize:
                                            queueBookForVectorization(book);
                                            break;
                                          case _BookCardAction.delete:
                                            await confirmAndDeleteBooksFromBookshelf(
                                              context,
                                              ref,
                                              [book],
                                            );
                                            break;
                                          case _BookCardAction.more:
                                            await showModalBottomSheet<void>(
                                              context: context,
                                              builder: (_) =>
                                                  BookBottomSheet(book: book),
                                            );
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: _BookCardAction.details,
                                          child: ListTile(
                                            dense: true,
                                            leading: Icon(Icons.info_outline),
                                            title: Text('书籍详情'),
                                          ),
                                        ),
                                        PopupMenuItem(
                                          value: _BookCardAction.vectorize,
                                          enabled:
                                              !(queueItem?.status.isActive ??
                                                  false),
                                          child: ListTile(
                                            dense: true,
                                            leading: Icon(
                                              queueItem?.status.isActive == true
                                                  ? Icons.hourglass_top_rounded
                                                  : indexed
                                                      ? Icons.refresh
                                                      : Icons.hub_outlined,
                                            ),
                                            title: Text(
                                              _vectorActionLabel(
                                                indexed,
                                                queueItem,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(
                                          value: _BookCardAction.more,
                                          child: ListTile(
                                              dense: true,
                                              leading: Icon(Icons.more_horiz),
                                              title: Text('更多操作（分享、替换文件）')),
                                        ),
                                        PopupMenuItem(
                                          value: _BookCardAction.delete,
                                          child: ListTile(
                                            dense: true,
                                            textColor: Colors.red,
                                            iconColor: Colors.red,
                                            leading: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            title: const Text('删除'),
                                          ),
                                        ),
                                      ],
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withAlpha(150),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Padding(
                                          padding: EdgeInsets.all(5),
                                          child: Icon(
                                            Icons.more_vert,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (queueItem?.status.isActive == true)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: LinearProgressIndicator(
                                      value: queueItem?.progress,
                                      minHeight: 4,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 55,
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (Prefs().webdavStatus)
                          SizedBox(
                            height: 20,
                            width: 20,
                            child: BookSyncStatusIcon(
                              syncStatus: bookSyncStatus,
                            ),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            book.author,
                            style: const TextStyle(
                              fontWeight: FontWeight.w300,
                              fontSize: 9,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Text(
                          '${(book.readingPercentage * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w300,
                            fontSize: 9,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String _vectorActionLabel(
  bool indexed,
  BookKnowledgeQueueItem? item,
) {
  if (item != null) {
    switch (item.status) {
      case BookKnowledgeQueueStatus.queued:
        return '排队中';
      case BookKnowledgeQueueStatus.extracting:
      case BookKnowledgeQueueStatus.preparing:
      case BookKnowledgeQueueStatus.vectorizing:
        return '正在向量化';
      case BookKnowledgeQueueStatus.cancelling:
        return '正在取消';
      case BookKnowledgeQueueStatus.failed:
        return '重新排队';
      case BookKnowledgeQueueStatus.completed:
      case BookKnowledgeQueueStatus.cancelled:
        break;
    }
  }
  return indexed ? '重新向量化' : '向量化';
}

class _KnowledgeStatusBadge extends StatelessWidget {
  const _KnowledgeStatusBadge({required this.indexed, required this.item});

  final bool indexed;
  final BookKnowledgeQueueItem? item;

  @override
  Widget build(BuildContext context) {
    final status = item?.status;
    final (label, color) = switch (status) {
      BookKnowledgeQueueStatus.queued => ('排队中', Colors.orange.shade700),
      BookKnowledgeQueueStatus.extracting => ('读取章节', Colors.blue.shade700),
      BookKnowledgeQueueStatus.preparing => ('整理章节', Colors.blue.shade700),
      BookKnowledgeQueueStatus.vectorizing => (
          '向量化 ${((item?.progress ?? 0) * 100).round()}%',
          Colors.blue.shade700
        ),
      BookKnowledgeQueueStatus.cancelling => ('正在取消', Colors.orange.shade700),
      BookKnowledgeQueueStatus.failed => ('向量失败', Colors.red.shade700),
      BookKnowledgeQueueStatus.cancelled => (
          indexed ? '已索引' : '未索引',
          Colors.grey.shade700
        ),
      BookKnowledgeQueueStatus.completed || null => (
          indexed ? '已索引' : '未索引',
          Colors.green.shade600
        ),
    };
    if (!indexed && status == null) return const SizedBox.shrink();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SelectionIndicator extends StatelessWidget {
  const _SelectionIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.primary
            : Colors.black.withAlpha(110),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: SizedBox(
        width: 24,
        height: 24,
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 17)
            : null,
      ),
    );
  }
}
