import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/sync/book_cloud_deletions.dart';
import 'package:modu_reader/service/sync/sync_paths.dart';
import 'replaced_book_files_test.dart' show CleanupClient;

void main() {
  late Directory dir;
  late BookCloudDeletions queue;
  late CleanupClient client;
  late Book book;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('modu-delete-');
    queue = BookCloudDeletions(File('${dir.path}/queue.json'));
    client = CleanupClient();
    book = Book.mock().copyWith(
        filePath: 'file/a.epub',
        coverPath: 'cover/a',
        md5: '1234567890abcdef1234567890abcdef');
    client.files[SyncPaths.data(book.filePath)] = [1];
    client.files[SyncPaths.data(book.coverPath)] = [2];
  });
  tearDown(() => dir.delete(recursive: true));
  test('intent survives restart and failure; only tombstoned books are removed',
      () async {
    await queue.enqueue(client, [book]);
    book = book.copyWith(isDeleted: true);
    client.failRemove = true;
    await expectLater(queue.apply(client, [book]), throwsStateError);
    client.failRemove = false;
    await BookCloudDeletions(queue.file).apply(client, [book]);
    expect(client.files, isEmpty);
    // An old offline writer must not resurrect an explicitly deleted binary.
    client.files[SyncPaths.data(book.filePath)] = [1];
    await queue.apply(client, [book]);
    expect(client.files, isEmpty);
  });
  test('restoring a book cancels its old deletion intent', () async {
    await queue.enqueue(client, [book]);
    await queue.apply(client, [book]);
    await queue.apply(client, [book.copyWith(isDeleted: true)]);
    expect(client.removed, isEmpty);
  });
  test('shared live cover is protected', () async {
    await queue.enqueue(client, [book]);
    await queue.apply(client, [
      book.copyWith(isDeleted: true),
      Book.mock().copyWith(id: 2, filePath: 'file/b.epub', coverPath: 'cover/a')
    ]);
    expect(client.removed, [SyncPaths.data('file/a.epub')]);
    expect(client.files.containsKey(SyncPaths.data('cover/a')), isTrue);
  });
  test('another deletion generation requires a new intent', () async {
    await queue.enqueue(client, [book]);
    final deleted = book.copyWith(isDeleted: true);
    await queue.apply(client, [deleted]);
    client.files[SyncPaths.data(book.filePath)] = [1];
    await queue.apply(client, [
      deleted.copyWith(
          updateTime: deleted.updateTime.add(const Duration(seconds: 1)))
    ]);
    expect(client.files.containsKey(SyncPaths.data(book.filePath)), isTrue);
    final again = deleted.copyWith(
        updateTime: deleted.updateTime.add(const Duration(seconds: 2)));
    await queue.enqueue(client, [again]);
    await queue.apply(client, [again]);
    expect(client.files, isEmpty);
  });
  test('unsafe paths never reach remote deletion', () async {
    book = book.copyWith(filePath: 'file/../important');
    await queue.enqueue(client, [book]);
    await expectLater(queue.apply(client, [book.copyWith(isDeleted: true)]),
        throwsFormatException);
    expect(client.removed, isEmpty);
  });
}
