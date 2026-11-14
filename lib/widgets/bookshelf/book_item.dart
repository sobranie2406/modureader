import 'package:modu_reader/providers/private_library.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/enums/book_sync_status.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/providers/sync_status.dart';
import 'package:modu_reader/providers/bookshelf_pins.dart';
import 'package:modu_reader/service/book.dart';
import 'package:modu_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:modu_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:modu_reader/widgets/bookshelf/book_bottom_sheet.dart';
import 'package:modu_reader/widgets/bookshelf/book_cover.dart';
import 'package:modu_reader/widgets/page_router/reader_cover_hero.dart';
import 'package:modu_reader/widgets/bookshelf/book_type_badges.dart';
import 'package:modu_reader/widgets/bookshelf/book_sync_status_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef BookSelectionChanged = void Function(Book book, bool selected);

class BookItem extends ConsumerStatefulWidget {
  const BookItem({
    super.key,
    required this.book,
    this.listMode = false,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
    this.dragBooks = const [],
  });

  final Book book;
  final bool listMode;
  final bool selectionMode;
  final bool selected;
  final BookSelectionChanged? onSelectionChanged;
  final List<Book> dragBooks;

  @override
  ConsumerState<BookItem> createState() => _BookItemState();
}

class _BookItemState extends ConsumerState<BookItem> {
  // Sync status/progress refreshes must not dispose the button that is awaiting
  // an open popup's result, otherwise Flutter silently drops onSelected.
  var menuKey = GlobalKey<PopupMenuButtonState<BookAction>>();
  Book get book => widget.book;
  bool get selectionMode => widget.selectionMode;
  bool get selected => widget.selected;
  BookSelectionChanged? get onSelectionChanged => widget.onSelectionChanged;

  @override
  void didUpdateWidget(covariant BookItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.id != widget.book.id) {
      // A genuinely different book must never inherit another book's popup.
      menuKey = GlobalKey<PopupMenuButtonState<BookAction>>();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(privateLibraryRevisionProvider);
    if (!PrivateLibrary.instance.isVisible(book)) {
      return const SizedBox.shrink();
    }
    final pinned = ref.watch(bookshelfPinsProvider).contains(bookPinKey(book));
    void toggleSelection() {
      onSelectionChanged?.call(book, !selected);
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
        final item = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: selectionMode
              ? toggleSelection
              : () => pushToReadingPage(ref, context, book),
          onSecondaryTap: toggleSelection,
          child: widget.listMode
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    children: [
                      if (selectionMode)
                        Checkbox(
                          value: selected,
                          onChanged: (_) => toggleSelection(),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(book.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                              ),
                              if (pinned) const Icon(Icons.push_pin, size: 16),
                              if (Prefs().webdavStatus)
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: BookSyncStatusIcon(
                                      syncStatus: bookSyncStatus),
                                ),
                            ]),
                            const SizedBox(height: 4),
                            Text(
                              [
                                if (book.author.trim().isNotEmpty) book.author,
                                '${(book.readingPercentage * 100).toStringAsFixed(0)}%',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Flexible(child: BookTypeBadges(book: book)),
                                FutureBuilder<bool>(
                                  future: BookKnowledgeIndexService()
                                      .hasIndex(book),
                                  builder: (context, snapshot) {
                                    final indexed = snapshot.data == true ||
                                        queueItem?.status ==
                                            BookKnowledgeQueueStatus.completed;
                                    return indexed || queueItem != null
                                        ? Padding(
                                            padding:
                                                const EdgeInsets.only(left: 8),
                                            child: KnowledgeStatusBadge(
                                                indexed: indexed,
                                                item: queueItem),
                                          )
                                        : const SizedBox.shrink();
                                  },
                                ),
                              ],
                            ),
                            if (queueItem?.status.isActive == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: EinkStaticIndicator(
                                  child: LinearProgressIndicator(
                                      value: queueItem?.progress, minHeight: 2),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (selectionMode)
                        BookBottomSheet(
                          book: book,
                          menuOnly: true,
                          menuKey: menuKey,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Icon(Icons.more_vert),
                          ),
                        ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Hero(
                        tag: book.coverFullPath,
                        transitionOnUserGestures: true,
                        createRectTween: readerCoverRectTween,
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
                              Positioned(
                                left: 8,
                                right: 40,
                                bottom: 8,
                                child: BookTypeBadges(book: book),
                              ),
                              FutureBuilder<bool>(
                                future:
                                    BookKnowledgeIndexService().hasIndex(book),
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
                                          child: KnowledgeStatusBadge(
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
                                        ),
                                      if (selectionMode)
                                        Positioned(
                                          right: 6,
                                          bottom: 6,
                                          child: BookBottomSheet(
                                            book: book,
                                            menuOnly: true,
                                            menuKey: menuKey,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color:
                                                    Colors.black.withAlpha(150),
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
                                          child: EinkStaticIndicator(
                                              child: LinearProgressIndicator(
                                            value: queueItem?.progress,
                                            minHeight: 4,
                                          )),
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
                              if (pinned) const Icon(Icons.push_pin, size: 16),
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
        if (onSelectionChanged == null) return item;
        final dragged = selected && widget.dragBooks.isNotEmpty
            ? List<Book>.unmodifiable(widget.dragBooks)
            : <Book>[book];
        return LongPressDraggable<List<Book>>(
          data: dragged,
          maxSimultaneousDrags: 1,
          rootOverlay: true,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () {
            if (!selected) onSelectionChanged?.call(book, true);
          },
          feedback: Material(
            color: Colors.transparent,
            elevation: Prefs().eInkMode ? 0 : 8,
            borderRadius: BorderRadius.circular(8),
            child: Badge(
              isLabelVisible: dragged.length > 1,
              label: Text('${dragged.length}'),
              child: BookCover(book: book, width: 100, height: 150),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: item),
          child: item,
        );
      },
    );
  }
}

class KnowledgeStatusBadge extends StatelessWidget {
  const KnowledgeStatusBadge(
      {super.key, required this.indexed, required this.item});

  final bool indexed;
  final BookKnowledgeQueueItem? item;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Prefs(),
      builder: (context, _) {
        final status = item?.status;
        if (!Prefs().showBookIndexBadge &&
            indexed &&
            (status == null ||
                status == BookKnowledgeQueueStatus.completed ||
                status == BookKnowledgeQueueStatus.cancelled)) {
          return const SizedBox.shrink();
        }
        String text(String zh, String en) => ModuStrings.text(context, zh, en);
        final indexedLabel =
            indexed ? text('已索引', 'Indexed') : text('未索引', 'Not indexed');
        final (label, color) = switch (status) {
          BookKnowledgeQueueStatus.queued => (
              text('排队中', 'Queued'),
              Colors.orange.shade700
            ),
          BookKnowledgeQueueStatus.extracting => (
              text('读取章节', 'Reading chapters'),
              Colors.blue.shade700
            ),
          BookKnowledgeQueueStatus.preparing => (
              text('整理章节', 'Preparing chapters'),
              Colors.blue.shade700
            ),
          BookKnowledgeQueueStatus.vectorizing => (
              '${text('向量化', 'Indexing')} ${((item?.progress ?? 0) * 100).round()}%',
              Colors.blue.shade700
            ),
          BookKnowledgeQueueStatus.cancelling => (
              text('正在取消', 'Cancelling'),
              Colors.orange.shade700
            ),
          BookKnowledgeQueueStatus.failed => (
              text('向量失败', 'Indexing failed'),
              Colors.red.shade700
            ),
          BookKnowledgeQueueStatus.cancelled => (
              indexedLabel,
              Colors.grey.shade700
            ),
          BookKnowledgeQueueStatus.completed || null => (
              indexedLabel,
              Colors.green.shade600
            ),
        };
        if (!indexed && status == null) return const SizedBox.shrink();

        return DecoratedBox(
          decoration: BoxDecoration(
            color: Prefs().eInkMode ? Colors.black : color,
            borderRadius: BorderRadius.circular(6),
            border: Prefs().eInkMode ? Border.all(color: Colors.black) : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                height: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      });
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
