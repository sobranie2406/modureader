import 'package:modu_reader/utils/app_motion.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/enums/bookshelf_folder_style.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/tb_group.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/providers/book_list.dart';
import 'package:modu_reader/providers/tb_groups.dart';
import 'package:modu_reader/widgets/bookshelf/book_cover.dart';
import 'package:modu_reader/widgets/bookshelf/book_item.dart';
import 'package:modu_reader/widgets/bookshelf/book_folder_dialog.dart';
import 'package:modu_reader/widgets/bookshelf/book_opened_folder.dart';
import 'package:modu_reader/widgets/bookshelf/folder_pin_menu.dart';
import 'package:modu_reader/utils/toast/common.dart';
import 'package:modu_reader/widgets/common/container/outlined_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';

class BookFolder extends ConsumerStatefulWidget {
  const BookFolder({
    super.key,
    required this.books,
    this.listMode = false,
    this.selectionMode = false,
    this.selectedBookIds = const <int>{},
    this.onSelectionChanged,
    this.selectedBooks = const [],
  });

  final List<Book> books;
  final bool listMode;
  final bool selectionMode;
  final Set<int> selectedBookIds;
  final BookSelectionChanged? onSelectionChanged;
  final List<Book> selectedBooks;

  @override
  ConsumerState<BookFolder> createState() => _BookFolderState();
}

class _BookFolderState extends ConsumerState<BookFolder> {
  bool _moving = false;
  final _menuKey = GlobalKey<PopupMenuButtonState<bool>>();

  @override
  Widget build(BuildContext context) {
    final folderStyle = context.watch<Prefs>().bookshelfFolderStyle;

    Future<void> onAcceptBook(DragTargetDetails<List<Book>> details) async {
      if (_moving) return;
      _moving = true;
      try {
        final target = widget.books.first;
        if (target.groupId == 0) {
          await showDialog<bool>(
            animationStyle: AppMotion.style,
            context: context,
            barrierDismissible: false,
            builder: (_) => BookFolderDialog(
                bookIds: [...details.data.map((book) => book.id), target.id],
                createNew: true),
          );
        } else {
          await ref.read(bookListProvider.notifier).moveBooksToFolder(
              details.data.map((book) => book.id),
              groupId: target.groupId);
        }
      } catch (_) {
        if (context.mounted) {
          AnxToast.show(ModuStrings.text(context, '移入文件夹失败，请刷新书架后重试',
              'Could not move the book. Refresh the shelf and try again.'));
        }
      } finally {
        _moving = false;
      }
    }

    Widget scaleTransition(Widget child, bool accepting) {
      return accepting
          ? ScaleTransition(
              scale: Tween<double>(begin: 1.0, end: 1.1).animate(
                CurvedAnimation(
                    parent: const AlwaysStoppedAnimation(0.5),
                    curve: Curves.easeInOut),
              ),
              child: child,
            )
          : child;
    }

    bool onWillAcceptBook(DragTargetDetails<List<Book>> details) {
      final target = widget.books.first;
      return !_moving &&
          details.data.isNotEmpty &&
          (target.groupId == 0
              ? details.data.every((book) => book.id != target.id)
              : details.data.any((book) => book.groupId != target.groupId));
    }

    void openFolder(String groupName) {
      final navigator = Navigator.of(context, rootNavigator: true);
      final themes =
          InheritedTheme.capture(from: context, to: navigator.context);
      // Hero flights require a PageRoute at both ends, including this dialog.
      navigator.push(PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierLabel:
            MaterialLocalizations.of(context).modalBarrierDismissLabel,
        barrierColor: DialogTheme.of(context).barrierColor ?? Colors.black54,
        transitionDuration:
            AppMotion.duration(const Duration(milliseconds: 150)),
        reverseTransitionDuration:
            AppMotion.duration(const Duration(milliseconds: 150)),
        pageBuilder: (context, animation, secondaryAnimation) => themes.wrap(
          FocusScope(
            child: SafeArea(
              child: BookOpenedFolder(
                books: widget.books,
                groupName: groupName,
              ),
            ),
          ),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ));
    }

    String groupName = ref.watch(groupDaoProvider).whenOrNull(
              data: (groups) => groups
                  .firstWhere((group) => group.id == widget.books.first.groupId,
                      orElse: () => TbGroup(id: -1, name: "..."))
                  .name,
            ) ??
        '???';

    final singleBookTarget = DragTarget<List<Book>>(
      onAcceptWithDetails: (book) => onAcceptBook(book),
      onWillAcceptWithDetails: (data) => onWillAcceptBook(data),
      builder: (context, candidateData, rejectedData) {
        return scaleTransition(
          BookItem(
            book: widget.books[0],
            listMode: widget.listMode,
            selectionMode: widget.selectionMode,
            selected: widget.selectedBookIds.contains(widget.books[0].id),
            onSelectionChanged: widget.onSelectionChanged,
            dragBooks: widget.selectedBooks,
          ),
          candidateData.isNotEmpty,
        );
      },
    );

    final groupTarget = DragTarget<List<Book>>(
      onAcceptWithDetails: (book) => onAcceptBook(book),
      onWillAcceptWithDetails: (data) => onWillAcceptBook(data),
      builder: (context, candidateData, rejectedData) {
        int count = -1;

        Widget buildStackedPreview() {
          return Stack(
            children: [
              ...(widget.books.take(4).toList()).map((book) {
                count++;
                return Positioned.fill(
                  right: 0,
                  top: 30 - count * Prefs().bookCoverWidth * 0.12,
                  child: Transform.scale(
                    scale: 1 - (count * 0.08),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: BookCover(book: book),
                    ),
                  ),
                );
              }),
            ].reversed.toList(),
          );
        }

        Widget buildGridPreview() {
          final previewBooks = widget.books.take(4).toList();
          return OutlinedContainer(
            color: Colors.transparent,
            outlineColor: Theme.of(context).colorScheme.outlineVariant,
            padding: const EdgeInsets.all(6),
            radius: 10,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1 / 1.6,
                mainAxisSpacing: 16,
                crossAxisSpacing: 6,
              ),
              itemCount: 4,
              itemBuilder: (context, index) {
                if (index >= previewBooks.length) {
                  return SizedBox.shrink();
                }
                final book = previewBooks[index];
                return BookCover(book: book);
              },
            ),
          );
        }

        Widget folderPreview;
        switch (folderStyle) {
          case BookshelfFolderStyle.grid2x2:
            folderPreview = buildGridPreview();
            break;
          case BookshelfFolderStyle.stacked:
            folderPreview = buildStackedPreview();
        }

        final selectedCount = widget.books
            .where((book) => widget.selectedBookIds.contains(book.id))
            .length;
        final allSelected = selectedCount == widget.books.length;
        void toggleSelection() {
          for (final book in widget.books) {
            widget.onSelectionChanged?.call(book, !allSelected);
          }
        }

        if (widget.listMode) {
          return InkWell(
            highlightColor: Theme.of(context).colorScheme.primaryContainer,
            onLongPress: toggleSelection,
            onSecondaryTap: toggleSelection,
            onTap: () => widget.selectionMode
                ? toggleSelection()
                : openFolder(groupName),
            child: ColoredBox(
              color: candidateData.isNotEmpty
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(children: [
                  if (widget.selectionMode)
                    Checkbox(
                      tristate: true,
                      value: allSelected
                          ? true
                          : selectedCount > 0
                              ? null
                              : false,
                      onChanged: (_) => toggleSelection(),
                    )
                  else ...[
                    const Icon(Icons.folder_outlined),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(groupName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                            ModuStrings.format(
                                context, '{count} 本书', '{count} books',
                                values: {'count': widget.books.length}),
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (widget.selectionMode)
                    FolderPinMenu(
                      groupId: widget.books.first.groupId,
                      menuKey: _menuKey,
                    )
                  else
                    const Icon(Icons.chevron_right),
                ]),
              ),
            ),
          );
        }

        return scaleTransition(
          Column(
            children: [
              Expanded(
                child: InkWell(
                  onLongPress: toggleSelection,
                  onSecondaryTap: toggleSelection,
                  onTap: () {
                    if (!widget.selectionMode) {
                      openFolder(groupName);
                      return;
                    }
                    toggleSelection();
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      folderPreview,
                      if (widget.selectionMode)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: FolderPinMenu(
                            groupId: widget.books.first.groupId,
                            menuKey: _menuKey,
                            onCover: true,
                          ),
                        ),
                      if (widget.selectionMode)
                        Positioned(
                          right: 7,
                          top: 7,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: allSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.black.withAlpha(110),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: allSelected
                                  ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 17,
                                    )
                                  : selectedCount > 0
                                      ? Center(
                                          child: Text(
                                            '$selectedCount',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 50,
                child: Text(
                  groupName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          candidateData.isNotEmpty,
        );
      },
    );

    return RepaintBoundary(
      child: widget.books.first.groupId == 0 ? singleBookTarget : groupTarget,
    );
  }
}
