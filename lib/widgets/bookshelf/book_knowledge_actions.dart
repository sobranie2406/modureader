import 'dart:io';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:anx_reader/service/knowledge/local_book_requirement.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> queueBookForVectorization(
  Book book, {
  BookKnowledgeIndexQueue? queue,
  void Function(String)? showMessage,
}) async {
  final notify = showMessage ?? (message) => AnxToast.show(message);
  try {
    await requireLocalBookForIndexing(book);
  } on LocalBookRequiredException {
    notify('《${book.title}》${LocalBookRequiredException.message}');
    return;
  }
  final added = (queue ?? bookKnowledgeIndexQueue).enqueue(book);
  notify(
    added ? '《${book.title}》已加入向量化队列' : '《${book.title}》已在向量化队列中',
  );
}

Future<void> queueBooksForVectorization(
  Iterable<Book> books, {
  BookKnowledgeIndexQueue? queue,
  void Function(String)? showMessage,
}) async {
  final notify = showMessage ?? (message) => AnxToast.show(message);
  // Count each book once, even when a selection contains duplicate records.
  final list = {for (final book in books) book.id: book}.values.toList();
  if (list.isEmpty) return;
  final localBooks = <Book>[];
  for (final book in list) {
    try {
      await requireLocalBookForIndexing(book);
      localBooks.add(book);
    } on LocalBookRequiredException {
      // Continue with local books; missing files must not become failed jobs.
    }
  }
  final added = (queue ?? bookKnowledgeIndexQueue).enqueueAll(localBooks);
  final missing = list.length - localBooks.length;
  if (missing > 0) {
    final queued = added > 0
        ? '已将 $added 本书加入向量化队列。'
        : localBooks.isNotEmpty
            ? '本地书籍已在队列中或队列暂不可用。'
            : '';
    notify('$queued已跳过 $missing 本尚未下载或本地文件不可用的书籍，请先下载后再向量化。');
    return;
  }
  if (added == 0) {
    notify('所选书籍已在向量化队列中');
  } else {
    notify('已将 $added 本书加入向量化队列');
  }
}

Future<bool> confirmAndDeleteBooksFromBookshelf(
  BuildContext context,
  WidgetRef ref,
  Iterable<Book> books,
) async {
  final list = books.toList(growable: false);
  if (list.isEmpty) return false;

  final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(list.length == 1 ? '删除书籍' : '删除 ${list.length} 本书'),
          content: Text(
            list.length == 1
                ? '确定删除《${list.first.title}》吗？书籍文件及本地向量索引也会被删除。'
                : '确定删除所选 ${list.length} 本书吗？书籍文件及本地向量索引也会被删除。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;
  if (!confirmed) return false;

  await deleteBooksFromBookshelf(ref, list);
  return true;
}

/// Performs the existing soft-delete/file-delete behavior and also removes
/// queue work plus the persisted knowledge index.
Future<void> deleteBooksFromBookshelf(
  WidgetRef ref,
  Iterable<Book> books,
) async {
  final list = books.toList(growable: false);
  for (final book in list) {
    await bookKnowledgeIndexQueue.cancelAndRemove(book.id);
    await bookDao.setDeleted(book.id, true);
    await _deleteIfPresent(File(book.fileFullPath));
    await _deleteIfPresent(File(book.coverFullPath));
    await BookKnowledgeIndexService().deleteIndex(book);
  }
  await ref.read(bookListProvider.notifier).refresh();
  AnxToast.show(list.length == 1 ? '书籍已删除' : '已删除 ${list.length} 本书');
}

Future<void> _deleteIfPresent(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } on Object catch (error, stackTrace) {
    AnxLog.severe('Failed to delete ${file.path}: $error\n$stackTrace');
  }
}
