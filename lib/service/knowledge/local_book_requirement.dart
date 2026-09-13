import 'dart:io';

import 'package:anx_reader/models/book.dart';

/// A synchronized bookshelf record does not imply a downloaded book file.
class LocalBookRequiredException implements Exception {
  const LocalBookRequiredException();

  static const message = '书籍尚未下载或本地文件不可用，请先下载书籍，再进行向量化。';

  @override
  String toString() => message;
}

Future<void> requireLocalBookForIndexing(Book book) async {
  try {
    if (book.filePath.trim().isNotEmpty &&
        await File(book.fileFullPath).exists()) {
      return;
    }
  } on FileSystemException {
    // Do not expose personal paths or low-level filesystem errors in feedback.
  }
  throw const LocalBookRequiredException();
}
