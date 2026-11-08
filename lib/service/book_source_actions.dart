import 'package:anx_reader/service/read_only_book_file.dart';
import 'dart:io';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/book_local_sources.dart';
import 'package:anx_reader/service/ios_linked_books.dart';
import 'package:anx_reader/service/md5_service.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';

/// Create/verify the owned copy before changing the source or releasing access.
Future<void> copyLinkedBookToLibrary(Book book) async {
  if (!book.isLinked) return;
  final sources = BookSources.store;
  if (sources == null) throw StateError('Local source storage unavailable');
  final original = readOnlyBookFile(book.fileFullPath);
  final locator =
      sources.read(book.md5, book.filePath)?['locator'] ?? book.filePath;
  final extension = book.filePath.split('.').last;
  final relative =
      'file/copied-${DateTime.now().microsecondsSinceEpoch}.$extension';
  final target = File(getBasePath(relative));
  await target.parent.create(recursive: true);
  try {
    await original.copy(target.path);
    final hash = await MD5Service.calculateFileMd5(target.path);
    if (hash == null ||
        (book.md5 != null && hash.toLowerCase() != book.md5!.toLowerCase())) {
      throw const FileSystemException(
          'Original content changed; add it as a new book');
    }
    await sources.save(book.md5, book.filePath,
        kind: 'internal', locator: relative);
  } catch (_) {
    if (await target.exists()) await target.delete();
    rethrow;
  }
  if (IosLinkedBooks.isLinked(locator)) await IosLinkedBooks.forget(locator);
}

/// Only the source binding/owned file changes, never synchronized book records.
Future<void> removeBookFromDevice(Book book) async {
  final sources = BookSources.store;
  if (sources == null) throw StateError('Local source storage unavailable');
  final path = book.fileFullPath;
  final linked = book.isLinked;
  final locator =
      sources.read(book.md5, book.filePath)?['locator'] ?? book.filePath;
  await sources.save(book.md5, book.filePath,
      kind: linked ? 'unlinked' : 'internal-removed', locator: book.filePath);
  if (linked) {
    if (IosLinkedBooks.isLinked(locator)) await IosLinkedBooks.forget(locator);
  } else {
    final owned = File(path);
    if (await owned.exists()) await owned.delete();
  }
}
