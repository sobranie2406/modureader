import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/sync_status.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful download atomically leaves remote-only and clears progress',
      () {
    const status = SyncStatusModel(
        localOnly: [],
        remoteOnly: [1, 2],
        both: [],
        nonExistent: [],
        downloading: [1],
        uploading: []);
    final done =
        completeBookTransfer(status, 1, download: true, completed: true);
    expect(done.remoteOnly, [2]);
    expect(done.both, [1]);
    expect(done.downloading, isEmpty);
    final again =
        completeBookTransfer(done, 1, download: true, completed: true);
    expect(again, done);
    final failed =
        completeBookTransfer(status, 1, download: true, completed: false);
    expect(failed.remoteOnly, [1, 2]);
    expect(failed.both, isEmpty);
    expect(failed.downloading, isEmpty);
  });
  final book = Book.mock().copyWith(filePath: 'file/book.epub');
  test('initial empty library and metadata/cover transfers do not throw', () {
    expect(syncingBookIds([], ''), isEmpty);
    expect(syncingBookIds([], 'book.epub'), isEmpty);
    expect(syncingBookIds([book], 'database8.db'), isEmpty);
    expect(syncingBookIds([book], 'cover.png'), isEmpty);
    expect(syncingBookIds([book], ''), isEmpty);
  });
  test('transfer status matches the exact book filename', () {
    expect(syncingBookIds([book], 'book.epub'), [book.id]);
    expect(syncingBookIds([book], 'book'), isEmpty);
  });
}
