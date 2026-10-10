import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/book.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shares the bookshelf's local/remote book opening behavior without changing
/// the selected home tab or creating a new reading position.
class ReadingHistoryBookAccess {
  Future<Book?> load(int id) => bookDao.querySingle(
        BookDao.table,
        mapper: Book.fromDb,
        where: 'id = ?',
        whereArgs: [id],
      );

  Future<void> open(WidgetRef ref, BuildContext context, Book book,
          {required String heroTag}) =>
      pushToReadingPage(ref, context, book, heroTag: heroTag);
}

final readingHistoryBookAccessProvider =
    Provider<ReadingHistoryBookAccess>((ref) => ReadingHistoryBookAccess());

class ReadingHistoryBookLink extends ConsumerStatefulWidget {
  const ReadingHistoryBookLink({
    super.key,
    required this.book,
    required this.heroTag,
    required this.child,
    this.enabled = true,
  });

  final Book book;
  final String heroTag;
  final Widget child;
  final bool enabled;

  @override
  ConsumerState<ReadingHistoryBookLink> createState() =>
      _ReadingHistoryBookLinkState();
}

class _ReadingHistoryBookLinkState
    extends ConsumerState<ReadingHistoryBookLink> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    try {
      final access = ref.read(readingHistoryBookAccessProvider);
      // History may have been loaded before a deletion or a sync update.
      final book = await access.load(widget.book.id);
      if (!mounted) return;
      if (book == null || book.isDeleted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(L10n.of(context).bookDeleted)));
        return;
      }
      await access.open(ref, context, book, heroTag: widget.heroTag);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${L10n.of(context).commonError} · ${L10n.of(context).commonRetry}')));
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: widget.enabled ? _open : null,
        child: widget.child,
      );
}
