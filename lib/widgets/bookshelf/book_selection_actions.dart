import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/widgets/bookshelf/book_folder_dialog.dart';
import 'package:anx_reader/widgets/bookshelf/book_knowledge_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Share the same confirmed batch operations inside and outside folders.
class BookSelectionActions extends ConsumerWidget {
  const BookSelectionActions(
      {super.key, required this.books, required this.onCompleted});
  final List<Book> books;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> organize(bool createNew) async {
      final moved = await showDialog<bool>(
        animationStyle: AppMotion.style,
        context: context,
        barrierDismissible: false,
        builder: (_) => BookFolderDialog(
          bookIds: books.map((book) => book.id).toList(),
          createNew: createNew,
        ),
      );
      if (moved == true && context.mounted) onCompleted();
    }

    return Wrap(spacing: 8, runSpacing: 4, children: [
      TextButton.icon(
        onPressed: books.isEmpty ? null : () => organize(true),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: Text(ModuStrings.text(context, '新建文件夹', 'New folder')),
      ),
      TextButton.icon(
        onPressed: books.isEmpty ? null : () => organize(false),
        icon: const Icon(Icons.drive_file_move_outline),
        label: Text(ModuStrings.text(context, '移入文件夹', 'Move to folder')),
      ),
      TextButton.icon(
        onPressed: books.isEmpty
            ? null
            : () {
                queueBooksForVectorization(books);
                onCompleted();
              },
        icon: const Icon(Icons.hub_outlined),
        label: Text(ModuStrings.text(context, '向量化', 'Vectorize')),
      ),
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: Colors.red),
        onPressed: books.isEmpty
            ? null
            : () async {
                final deleted = await confirmAndDeleteBooksFromBookshelf(
                    context, ref, books);
                if (deleted && context.mounted) onCompleted();
              },
        icon: const Icon(Icons.delete_outline),
        label: Text(ModuStrings.text(context, '删除', 'Delete')),
      ),
    ]);
  }
}
