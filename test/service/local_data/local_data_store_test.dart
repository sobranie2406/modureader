import 'package:anx_reader/service/local_data/local_data_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stores a book and restores its reader location', () async {
    final store = InMemoryLocalDataStore();
    const book =
        LibraryBook(id: 'book-1', title: '测试书', path: '/books/test.epub');
    const location = ReaderLocation(
      bookId: 'book-1',
      chapterId: 'chapter-2',
      cfi: 'epubcfi(/6/4!/4/2)',
      page: 12,
      textOffset: 48,
    );

    await store.saveBook(book);
    await store.saveProgress(location);

    expect(await store.getBook('book-1'), book);
    expect(await store.getProgress('book-1'), location);
  });

  test('does not return progress for a missing book', () async {
    final store = InMemoryLocalDataStore();

    expect(await store.getProgress('missing'), isNull);
  });
}
