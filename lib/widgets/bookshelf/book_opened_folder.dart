import 'dart:math' as math;
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/bookshelf_pins.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:anx_reader/widgets/bookshelf/book_selection_actions.dart';
import 'package:anx_reader/widgets/bookshelf/folder_pin_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BookOpenedFolder extends ConsumerStatefulWidget {
  const BookOpenedFolder({
    super.key,
    required this.books,
    required this.groupName,
  });

  final List<Book> books;
  final String groupName;

  @override
  ConsumerState<BookOpenedFolder> createState() => _BookOpenedFolderState();
}

class _BookOpenedFolderState extends ConsumerState<BookOpenedFolder> {
  bool isEditing = false;
  bool isEditingName = false;
  bool selectionMode = false;
  final selectedIds = <int>{};
  List<Book> books = [];
  late TextEditingController _nameController;
  String currentGroupName = "";
  bool _movingOut = false;
  String? _moveError;

  Future<void> _moveOut(List<Book> dragged) async {
    if (_movingOut) return;
    final ids = dragged.map((book) => book.id).toSet();
    setState(() {
      _movingOut = true;
      _moveError = null;
    });
    try {
      await ref
          .read(bookListProvider.notifier)
          .moveBooksToFolder(ids, groupId: 0);
      if (!mounted) return;
      setState(() {
        books.removeWhere((entry) => ids.contains(entry.id));
        selectedIds.removeAll(ids);
        _movingOut = false;
      });
      if (books.isEmpty) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _movingOut = false;
        _moveError = ModuStrings.text(
            context, '移出失败，请重试', 'Could not move the book. Please try again.');
      });
    }
  }

  Widget _shelfDropTarget({required bool outside}) => DragTarget<List<Book>>(
        key: ValueKey(outside ? 'folder-outside-drop' : 'folder-shelf-drop'),
        onWillAcceptWithDetails: (details) =>
            !_movingOut &&
            details.data.isNotEmpty &&
            details.data
                .every((dragged) => books.any((book) => book.id == dragged.id)),
        onAcceptWithDetails: (details) => _moveOut(details.data),
        builder: (context, candidates, _) => outside
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: ColoredBox(
                  color: candidates.isEmpty
                      ? Colors.transparent
                      : Theme.of(context).colorScheme.primary.withAlpha(30),
                ),
              )
            : Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: candidates.isEmpty
                      ? Theme.of(context).colorScheme.surface
                      : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Theme.of(context).colorScheme.outline),
                ),
                child: Text(ModuStrings.text(context, '拖到这里或文件夹外，移回书架',
                    'Drop here or outside the folder to move to the shelf')),
              ),
      );

  @override
  void initState() {
    super.initState();
    books = List.of(widget.books);
    currentGroupName = widget.groupName;
    _nameController = TextEditingController(text: currentGroupName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _updateGroupName() async {
    if (books.isEmpty) return;

    final groupId = books.first.groupId;
    if (groupId <= 0) return;

    try {
      final group = await ref.read(groupDaoProvider.notifier).getGroup(groupId);
      if (group == null) return;
      final updatedGroup = group.copyWith(name: _nameController.text);
      await ref.read(groupDaoProvider.notifier).updateGroup(updatedGroup);

      setState(() {
        currentGroupName = _nameController.text;
        isEditingName = false;
      });
    } catch (e) {
      // Handle error
      setState(() {
        isEditingName = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(bookListProvider, (_, next) {
      if (next.isLoading || !next.hasValue || next.hasError) return;
      final groupId = widget.books.first.groupId;
      final latest = next.requireValue
          .expand((group) => group)
          .where((book) => book.groupId == groupId)
          .toList();
      setState(() {
        books = latest;
        selectedIds.retainAll(latest.map((book) => book.id));
      });
    });
    final pins = ref.watch(bookshelfPinsProvider);
    if (books.isNotEmpty) {
      books = applyBookshelfPins([BookList().sortBooks(List.of(books))], pins)
          .single;
    }
    final media = MediaQuery.of(context);
    // Size the dialog around its cards, rather than stretching a partial row.
    final availableWidth = math.max(
        0.0, math.min(520.0, media.size.width - media.padding.horizontal - 88));
    final coverWidth = Prefs().bookCoverWidth.clamp(80.0, 260.0);
    final columns = math.max(
        1,
        math.min(math.max(2, books.length),
            ((availableWidth + 10) / (coverWidth + 10)).round()));
    final contentWidth = math.min(availableWidth,
        math.max(240.0, columns * coverWidth + (columns - 1) * 10));
    final dialog = AlertDialog(
      // OHOS defaults to an outer scroll view; the grid needs bounded height.
      scrollable: false,
      insetPadding: const EdgeInsets.all(24),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: selectionMode
          ? Text(ModuStrings.format(
              context, '已选 {count} 本', '{count} books selected',
              values: {'count': selectedIds.length}))
          : isEditingName
              ? Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        autofocus: true,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.check),
                      onPressed: _updateGroupName,
                    ),
                    IconButton(
                      icon: Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _nameController.text = currentGroupName;
                          isEditingName = false;
                        });
                      },
                    ),
                  ],
                )
              : TextButton(
                  onPressed: () {
                    setState(() {
                      isEditingName = true;
                    });
                  },
                  child: Text(
                    currentGroupName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
      content: SizedBox(
        width: contentWidth,
        child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: 1 / 2.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: books.length,
            itemBuilder: (context, index) => Stack(
                  children: [
                    BookItem(
                      key: ValueKey(books[index].id),
                      book: books[index],
                      selectionMode: selectionMode,
                      selected: selectedIds.contains(books[index].id),
                      dragBooks: books
                          .where((book) => selectedIds.contains(book.id))
                          .toList(),
                      onSelectionChanged: (book, selected) {
                        setState(() {
                          selectionMode = true;
                          isEditing = false;
                          isEditingName = false;
                          if (selected) {
                            selectedIds.add(book.id);
                          } else {
                            selectedIds.remove(book.id);
                          }
                        });
                      },
                    ),
                    isEditing
                        ? Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton(
                              onPressed: () => _moveOut([books[index]]),
                              icon: const Icon(
                                Icons.remove_circle,
                                size: 30,
                                color: Colors.red,
                              ),
                            ),
                          )
                        : Container(),
                  ],
                )),
      ),
      actions: [
        SizedBox(
          width: contentWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4),
            child: SingleChildScrollView(
                child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (_moveError != null)
                  Text(_moveError!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                if (_movingOut) const LinearProgressIndicator(),
                if (selectionMode) ...[
                  _shelfDropTarget(outside: false),
                  TextButton(
                    onPressed: () => setState(() {
                      if (selectedIds.length == books.length) {
                        selectedIds.clear();
                      } else {
                        selectedIds.addAll(books.map((book) => book.id));
                      }
                    }),
                    child: Text(selectedIds.length == books.length
                        ? ModuStrings.text(context, '取消全选', 'Deselect all')
                        : ModuStrings.text(context, '全选', 'Select all')),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      selectionMode = false;
                      selectedIds.clear();
                    }),
                    child: Text(L10n.of(context).commonCancel),
                  ),
                  BookSelectionActions(
                    books: books
                        .where((book) => selectedIds.contains(book.id))
                        .toList(),
                    onCompleted: () => Navigator.pop(context),
                  ),
                ] else ...[
                  if (books.isNotEmpty)
                    FolderPinMenu(groupId: books.first.groupId),
                  TextButton(
                      onPressed: books.isEmpty
                          ? null
                          : () {
                              ref
                                  .read(bookListProvider.notifier)
                                  .dissolveGroup(books);
                              Navigator.pop(context);
                            },
                      child: Text(L10n.of(context).commonDissolve)),
                  TextButton(
                      onPressed: () {
                        isEditing = !isEditing;
                        setState(() {});
                      },
                      child: Text(isEditing
                          ? L10n.of(context).commonCancel
                          : L10n.of(context).commonEdit)),
                ],
              ],
            )),
          ),
        )
      ],
    );
    return PopScope(
      canPop: !_movingOut,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _shelfDropTarget(outside: true),
          AbsorbPointer(absorbing: _movingOut, child: dialog),
        ],
      ),
    );
  }
}
