import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/reading_position_snapshot.dart';
import 'package:sqflite/sqflite.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/replaced_book_files.dart';
import 'package:anx_reader/service/sync/converted_book_checksum.dart';
import 'package:anx_reader/utils/reading_progress.dart';

class BookDao extends BaseDao {
  BookDao();

  static const String table = 'tb_books';

  /// Create a folder and move its books atomically, or move into a live folder.
  /// Only membership changes: never write a stale Book snapshot over sync data.
  Future<int> moveBooksToFolder(Iterable<int> bookIds,
      {int? groupId, String? newFolderName}) async {
    final ids = bookIds.toSet();
    final name = newFolderName?.trim();
    if (ids.isEmpty || ids.any((id) => id <= 0)) {
      throw ArgumentError('Select at least one book');
    }
    if ((groupId == null) == (newFolderName == null) ||
        (groupId != null && groupId <= 0) ||
        (name != null && (name.isEmpty || name.length > 100))) {
      throw ArgumentError('Invalid folder destination');
    }
    return transaction((txn) async {
      // Per-ID checks avoid SQLite parameter limits on large selections.
      for (final id in ids) {
        final rows = await txn.query(table,
            columns: ['id'],
            where: 'id = ? AND is_deleted = 0',
            whereArgs: [id]);
        if (rows.isEmpty) throw StateError('Selected book no longer exists');
      }
      final now = DateTime.now().toIso8601String();
      final int target;
      if (groupId != null) {
        final groups = await txn.query('tb_groups',
            columns: ['id'],
            where: 'id = ? AND is_deleted = 0',
            whereArgs: [groupId]);
        if (groups.isEmpty) throw StateError('Folder no longer exists');
        target = groupId;
      } else {
        target = await txn.insert('tb_groups', {
          'name': name,
          'parent_id': 0,
          'is_deleted': 0,
          'create_time': now,
          'update_time': now,
        });
      }
      for (final id in ids) {
        await txn.update(table, {'group_id': target, 'update_time': now},
            where: 'id = ? AND (group_id IS NULL OR group_id != ?)',
            whereArgs: [id, target]);
      }
      return target;
    });
  }

  Future<int> save(Book book) async {
    if (book.id != -1) {
      await updateBook(book);
      await setDeleted(book.id, book.isDeleted);
      return book.id;
    }
    return insert(table, book.toMap());
  }

  Future<int> insertBook(Book book, {String? sourceMd5}) {
    if (book.id != -1 || sourceMd5 == null) return save(book);
    return transaction((txn) =>
        ConvertedBookChecksum.insert(txn, book.toMap(), sourceMd5: sourceMd5));
  }

  Future<void> updateBook(Book book) async {
    book.updateTime = DateTime.now();
    final values = book.toMap()
      ..remove('last_read_position')
      ..remove('reading_percentage')
      ..remove('is_deleted');
    await transaction((txn) async {
      final previous =
          await txn.query(table, where: 'id = ?', whereArgs: [book.id]);
      if (previous.length == 1) {
        await ReplacedBookFiles.record(txn, previous.single, book.filePath);
      }
      await txn.update(table, values, where: 'id = ?', whereArgs: [book.id]);
    });
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
    // Converted books retain their source identity while file_md5 checks the
    // actual EPUB. The same import must still find the original shelf entry.
    return rawQuerySingle('''SELECT b.* FROM tb_books b
      LEFT JOIN $syncRecordsTable r ON r.kind='book' AND r.local_id=b.id
      WHERE lower(b.file_md5)=? OR r.sync_id=?
      ORDER BY b.is_deleted ASC, b.id ASC LIMIT 1''',
        arguments: [md5.toLowerCase(), 'md5:${md5.toLowerCase()}'],
        mapper: Book.fromDb);
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

  Future<List<Book>> selectBooksByIds(List<int> ids,
      {bool includeDeleted = false}) async {
    if (ids.isEmpty) {
      return const [];
    }

    final placeholders = List.filled(ids.length, '?').join(',');
    return rawQueryList(
      'SELECT * FROM $table WHERE ${includeDeleted ? '' : 'is_deleted = 0 AND '}id IN ($placeholders)',
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
