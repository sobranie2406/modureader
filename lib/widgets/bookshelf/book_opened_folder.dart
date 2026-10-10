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
    // Re-sort the original folder order so unpinning restores that order.
    final pins = ref.watch(bookshelfPinsProvider);
    final ids = books.map((book) => book.id).toSet();
    final original =
        widget.books.where((book) => ids.contains(book.id)).toList();
    if (original.isNotEmpty) {
      books = applyBookshelfPins([BookList().sortBooks(original)], pins).single;
    }
    return AlertDialog(
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
        width: MediaQuery.of(context).size.width * 0.7,
        child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: Prefs().bookCoverWidth,
              childAspectRatio: 1 / 2.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: books.length,
            itemBuilder: (context, index) => Stack(
                  children: [
                    BookItem(
                      book: books[index],
                      selectionMode: selectionMode,
                      selected: selectedIds.contains(books[index].id),
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
                              onPressed: () {
                                ref
                                    .read(bookListProvider.notifier)
                                    .removeFromGroup(books[index]);
                                books.removeAt(index);
                                if (books.isEmpty) {
                                  Navigator.pop(context);
                                }
                                setState(() {});
                              },
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
        if (selectionMode) ...[
          BookSelectionActions(
            books:
                books.where((book) => selectedIds.contains(book.id)).toList(),
            onCompleted: () => Navigator.pop(context),
          ),
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
        ] else ...[
          if (books.isNotEmpty) FolderPinMenu(groupId: books.first.groupId),
          TextButton(
              onPressed: () {
                ref.read(bookListProvider.notifier).dissolveGroup(books);
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
    );
  }
}
