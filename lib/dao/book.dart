import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/reading_position_snapshot.dart';
import 'package:sqflite/sqflite.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/utils/reading_progress.dart';

class BookDao extends BaseDao {
  BookDao();

  static const String table = 'tb_books';

  Future<int> save(Book book) async {
    if (book.id != -1) {
      await updateBook(book);
      await setDeleted(book.id, book.isDeleted);
      return book.id;
    }
    return insert(table, book.toMap());
  }

  Future<int> insertBook(Book book) => save(book);

  Future<void> updateBook(Book book) async {
    book.updateTime = DateTime.now();
    final values = book.toMap()
      ..remove('last_read_position')
      ..remove('reading_percentage')
      ..remove('is_deleted');
    await update(
      table,
      values,
      where: 'id = ?',
      whereArgs: [book.id],
    );
  }

  Future<ReadingPositionSnapshot> readReadingPosition(int bookId) =>
      transaction((txn) => _readPosition(txn, bookId));

  Future<ReadingPositionSnapshot> _readPosition(
      Transaction txn, int bookId) async {
    final rows = await txn.rawQuery('''SELECT b.last_read_position,
      b.reading_percentage, b.is_deleted, r.clock, r.revision
      FROM tb_books b JOIN $syncRecordsTable r
      ON r.kind='position' AND r.local_id=b.id WHERE b.id=?''', [bookId]);
    if (rows.length != 1) throw StateError('Reading position unavailable');
    final row = rows.single;
    return ReadingPositionSnapshot(
      row['last_read_position'] as String? ?? '',
      normalizeReadingProgress(row['reading_percentage'] as num?),
      '${row['clock']}:${row['revision']}',
      deleted: row['is_deleted'] == 1,
    );
  }

  /// Only explicit reading actions call this. A stale page cannot overwrite a
  /// position imported by sync, even if the old page is saved later in time.
  Future<ReadingPositionSnapshot?> updateReadingPosition(
      int bookId, String position, double percentage,
      {required String expectedRevision}) async {
    return transaction((txn) async {
      final current = await _readPosition(txn, bookId);
      if (current.deleted || current.revision != expectedRevision) return null;
      final normalized = normalizeReadingProgress(percentage);
      if (current.position == position && current.percentage == normalized) {
        return current;
      }
      await txn.update(
          table,
          {
            'last_read_position': position,
            'reading_percentage': normalized,
            'update_time': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [bookId]);
      // The position trigger already records the actual change, exactly once.
      return _readPosition(txn, bookId);
    });
  }

  Future<void> setDeleted(int bookId, bool deleted) async {
    await update(
        table,
        {
          'is_deleted': deleted ? 1 : 0,
          'update_time': DateTime.now().toIso8601String()
        },
        where: 'id = ?',
        whereArgs: [bookId]);
  }

  Future<List<Book>> selectBooks({bool includeDeleted = true}) {
    return queryList(
      table,
      mapper: Book.fromDb,
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'update_time DESC',
    );
  }

  Future<List<Book>> selectNotDeleteBooks() {
    return selectBooks(includeDeleted: false);
  }

  Future<Book> selectBookById(int id) async {
    final book = await querySingle(
      table,
      mapper: Book.fromDb,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (book == null) {
      throw StateError('Book with id $id not found');
    }
    return book;
  }

  Future<List<String>> getCurrentBooks() async {
    final books = await selectNotDeleteBooks();
    return books.map((book) => book.filePath).toList(growable: false);
  }

  Future<List<String>> getCurrentCover() async {
    final books = await selectNotDeleteBooks();
    return books.map((book) => book.coverPath).toList(growable: false);
  }

  Future<List<Book>> selectAllBooks() {
    return selectBooks();
  }

  Future<Book?> getBookByMd5(String md5) {
    return querySingle(
      table,
      mapper: Book.fromDb,
      where: 'file_md5 = ?',
      whereArgs: [md5],
    );
  }

  Future<List<Book>> searchBooks(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) {
      return const [];
    }

    return queryList(
      table,
      mapper: Book.fromDb,
      where: 'is_deleted = 0 AND (title LIKE ? OR author LIKE ?)',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'update_time DESC',
    );
  }

  Future<List<Book>> selectBooksByIds(List<int> ids) async {
    if (ids.isEmpty) {
      return const [];
    }

    final placeholders = List.filled(ids.length, '?').join(',');
    return rawQueryList(
      'SELECT * FROM $table WHERE is_deleted = 0 AND id IN ($placeholders)',
      arguments: ids,
      mapper: Book.fromDb,
    );
  }

  Future<void> updateBookMd5(int bookId, String md5) {
    return update(
      table,
      {
        'file_md5': md5,
        'update_time': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<List<Book>> getBooksWithoutMd5() {
    return queryList(
      table,
      mapper: Book.fromDb,
      where: "is_deleted = 0 AND (file_md5 IS NULL OR file_md5 = '')",
      orderBy: 'update_time DESC',
    );
  }
}

final bookDao = BookDao();
