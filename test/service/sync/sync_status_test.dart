import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
