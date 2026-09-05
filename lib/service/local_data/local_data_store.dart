/// Stable location in a book, shared by the reader, AI citations and TTS.
class ReaderLocation {
  const ReaderLocation({
    required this.bookId,
    this.chapterId,
    this.cfi,
    this.page,
    this.textOffset,
  });

  final String bookId;
  final String? chapterId;
  final String? cfi;
  final int? page;
  final int? textOffset;

  @override
  bool operator ==(Object other) =>
      other is ReaderLocation &&
      other.bookId == bookId &&
      other.chapterId == chapterId &&
      other.cfi == cfi &&
      other.page == page &&
      other.textOffset == textOffset;

  @override
  int get hashCode => Object.hash(bookId, chapterId, cfi, page, textOffset);
}

class LibraryBook {
  const LibraryBook({
    required this.id,
    required this.title,
    required this.path,
    this.author,
    this.contentHash,
  });

  final String id;
  final String title;
  final String path;
  final String? author;
  final String? contentHash;

  @override
  bool operator ==(Object other) =>
      other is LibraryBook &&
      other.id == id &&
      other.title == title &&
      other.path == path &&
      other.author == author &&
      other.contentHash == contentHash;

  @override
  int get hashCode => Object.hash(id, title, path, author, contentHash);
}

abstract interface class LocalDataStore {
  Future<void> saveBook(LibraryBook book);

  Future<LibraryBook?> getBook(String bookId);

  Future<void> saveProgress(ReaderLocation location);

  Future<ReaderLocation?> getProgress(String bookId);
}

/// Deterministic store for unit tests and service previews.
class InMemoryLocalDataStore implements LocalDataStore {
  final Map<String, LibraryBook> _books = {};
  final Map<String, ReaderLocation> _progress = {};

  @override
  Future<LibraryBook?> getBook(String bookId) async => _books[bookId];

  @override
  Future<ReaderLocation?> getProgress(String bookId) async => _progress[bookId];

  @override
  Future<void> saveBook(LibraryBook book) async {
    _books[book.id] = book;
  }

  @override
  Future<void> saveProgress(ReaderLocation location) async {
    _progress[location.bookId] = location;
  }
}
