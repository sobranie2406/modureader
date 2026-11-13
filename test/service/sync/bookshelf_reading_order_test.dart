import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/dao/book.dart';
import 'package:modu_reader/dao/base_dao.dart';
import 'package:modu_reader/enums/sort_field.dart';
import 'package:modu_reader/enums/sort_order.dart';
import 'package:modu_reader/providers/book_list.dart';
import 'package:modu_reader/service/sync/row_sync_record.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'row_sync_test.dart' show fixture, bookRow;

class _Dao extends BookDao {
  _Dao(this.db);
  final Database db;
  @override
  Future<List<T>> rawQueryList<T>(String sql,
          {List<Object?>? arguments, required RowMapper<T> mapper}) async =>
      (await db.rawQuery(sql, arguments)).map(mapper).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('position-only sync updates shelf order with different local IDs',
      () async {
    final a = await fixture();
    final b = await fixture(bookId: 41);
    addTearDown(a.close);
    addTearDown(b.close);
    await a.insert('tb_books', bookRow(2, md5: 'second'));
    await b.insert('tb_books', bookRow(42, md5: 'second'));
    final storeA = RowSyncStore(a), storeB = RowSyncStore(b);
    await storeA.merge(await storeB.snapshot());
    await storeB.merge(await storeA.snapshot());
    final positions =
        (await storeA.snapshot()).where((r) => r.kind == 'position');
    final newest =
        positions.map((r) => r.clock).reduce((a, b) => a > b ? a : b) + 100;
    final old = positions.singleWhere((r) => r.id == 'md5:same-content');
    final progress = RowSyncRecord(old.kind, old.id, newest, 'explicit-reading',
        false, {'last_read_position': 'chapter-2', 'reading_percentage': 0.4});
    // Only the position changes: metadata update_time remains old on both devices.
    await storeA.merge([progress]);
    await storeB.merge([progress]);
    for (final db in [a, b]) {
      final books = await _Dao(db).selectNotDeleteBooks();
      final sorted = BookList().sortBooks(books);
      expect(sorted.first.md5, 'same-content');
      expect(sorted.first.readingPercentage, 0.4);
      expect(sorted.first.updateTime, DateTime.parse('2026-09-01T00:00:00Z'));
      expect(sorted.first.readingPositionClock, newest);
      expect(
          sorted.first.copyWith(title: 'Rename').readingPositionClock, newest);
      expect(sorted.first.toMap(), isNot(contains('reading_position_clock')));
      final before =
          (await RowSyncStore(db).snapshot()).map((r) => r.toMap()).toList();
      await _Dao(db).selectNotDeleteBooks();
      expect((await RowSyncStore(db).snapshot()).map((r) => r.toMap()).toList(),
          before);
      Prefs().sortField = SortFieldEnum.progress;
      Prefs().sortOrder = SortOrderEnum.ascending;
      expect(BookList().sortBooks(List.of(books)).first.md5, 'second');
      Prefs().sortField = SortFieldEnum.lastReadTime;
      Prefs().sortOrder = SortOrderEnum.descending;
    }
  });
}
