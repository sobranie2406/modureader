import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/reading_round.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/reading_round.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/utils/reading_progress.dart';
import 'package:sqflite/sqflite.dart';

/// 多刷阅读统计：轮次管理服务
///
/// 一次「完成本轮」或「撤销」会同时改动三张表（tb_reading_time /
/// tb_reading_rounds / tb_books），因此**所有读写都在同一个 SQLite 事务里**
/// 完成：要么全部成功，要么全部回滚，不会留下「旧轮已结束、新轮没建」之类的
/// 中间状态。
class ReadingRoundService {
  ReadingRoundService._();

  static const _bookTable = BookDao.table;
  static const _roundTable = ReadingRoundDao.table;
  static const _timeTable = ReadingTimeDao.table;

  /// 完成当前轮，开启下一轮；返回更新后的 [Book]
  static Future<Book> finishCurrentRound(Book book) async {
    await readingRoundDao.transaction((txn) async {
      // 以数据库中的最新状态为准：调用方可能持有较早加载的 Book 实例
      final row = await _selectBookRow(txn, book.id);
      if (row == null) {
        throw StateError('Book ${book.id} not found');
      }

      final currentRound = (row['current_round'] as int?) ?? 1;
      final endPercentage = normalizeReadingProgress(
          (row['reading_percentage'] as num?)?.toDouble());
      final endPosition = (row['last_read_position'] as String?) ?? '';
      final now = DateTime.now().toIso8601String();

      // 当前轮可能从未在详情页打开过：补建一条进行中记录
      if (await _selectRoundRow(txn, book.id, currentRound) == null) {
        await txn.insert(_roundTable, {
          'book_id': book.id,
          'round_number': currentRound,
          'status': ReadingRound.statusReading,
          'start_time': now,
          'start_percentage': endPercentage,
          'end_percentage': 0.0,
          'end_position': null,
          'total_reading_time': 0,
          'create_time': now,
          'update_time': now,
        });
      }

      final totalTime = await _sumReadingTime(txn, book.id, currentRound);
      await txn.update(
        _roundTable,
        {
          'status': ReadingRound.statusFinished,
          'end_time': now,
          'end_percentage': endPercentage,
          'end_position': endPosition,
          'total_reading_time': totalTime,
          'update_time': now,
        },
        where: 'book_id = ? AND round_number = ?',
        whereArgs: [book.id, currentRound],
      );

      // 开启下一轮：如果历史上留下了同号记录（早期版本/异常数据），
      // 复用它而不是再插入一条，避免出现重复轮次。
      final nextRound = currentRound + 1;
      final nextExisting = await _selectRoundRow(txn, book.id, nextRound);
      final nextTotalTime = await _sumReadingTime(txn, book.id, nextRound);
      if (nextExisting == null) {
        await txn.insert(_roundTable, {
          'book_id': book.id,
          'round_number': nextRound,
          'status': ReadingRound.statusReading,
          'start_time': now,
          'start_percentage': 0.0,
          'end_percentage': 0.0,
          'end_position': null,
          'total_reading_time': nextTotalTime,
          'create_time': now,
          'update_time': now,
        });
      } else {
        await txn.update(
          _roundTable,
          {
            'status': ReadingRound.statusReading,
            'start_time': now,
            'start_percentage': 0.0,
            'end_time': null,
            'end_percentage': 0.0,
            'end_position': null,
            'total_reading_time': nextTotalTime,
            'update_time': now,
          },
          where: 'id = ?',
          whereArgs: [nextExisting['id']],
        );
      }

      // 轮次号、进度、位置一次写完；position 触发器会自动记录同步事件
      await txn.update(
        _bookTable,
        {
          'current_round': nextRound,
          'last_read_position': '',
          'reading_percentage': 0.0,
          'update_time': now,
        },
        where: 'id = ?',
        whereArgs: [book.id],
      );
      await RowSyncStore.markPositionReset(txn, book.id);
    });

    return bookDao.selectBookById(book.id);
  }

  /// 撤销最近一次【完成本轮】：
  ///
  /// - 删除当前（误开的）新轮记录
  /// - 把上一轮从 finished **恢复为 reading**，保留其 start_time / start_percentage
  /// - 把误开新轮期间已经产生的阅读时长**归回上一轮**（否则会变成孤儿数据）
  /// - 恢复上一轮结束时的进度与精确阅读位置
  ///
  /// 返回更新后的 [Book]；已是第 1 刷时原样返回。
  static Future<Book> undoLastRound(Book book) async {
    final changed = await readingRoundDao.transaction<bool>((txn) async {
      final row = await _selectBookRow(txn, book.id);
      if (row == null) {
        throw StateError('Book ${book.id} not found');
      }

      final currentRound = (row['current_round'] as int?) ?? 1;
      if (currentRound <= 1) {
        return false;
      }

      final previousRound = currentRound - 1;
      final now = DateTime.now().toIso8601String();
      final currentPercentage = normalizeReadingProgress(
          (row['reading_percentage'] as num?)?.toDouble());
      final currentPosition = (row['last_read_position'] as String?) ?? '';

      final previous = await _selectRoundRow(txn, book.id, previousRound);
      var restoredPercentage = currentPercentage;
      var restoredPosition = currentPosition;
      if (previous != null &&
          previous['status'] == ReadingRound.statusFinished) {
        restoredPercentage = normalizeReadingProgress(
            (previous['end_percentage'] as num?)?.toDouble());
        restoredPosition = (previous['end_position'] as String?) ?? '';
      }

      // 误开新轮期间读的时长归回上一轮（round = currentRound 的行）
      await txn.update(
        _timeTable,
        {'round': previousRound},
        where: 'book_id = ? AND round = ?',
        whereArgs: [book.id, currentRound],
      );
      final totalTime = await _sumReadingTime(txn, book.id, previousRound);

      // 撤销：把新轮标记为 cancelled（软取消），而不是 DELETE。
      // 删除会生成同步墓碑；同一轮次号之后可能被再次使用（再次完成上一轮），
      // 保留行 + 状态位可以让它安全复活，也能让同步端稳定合并。
      await txn.update(
        _roundTable,
        {
          'status': ReadingRound.statusCancelled,
          'end_time': now,
          'total_reading_time': 0,
          'update_time': now,
        },
        where: 'book_id = ? AND round_number = ?',
        whereArgs: [book.id, currentRound],
      );

      if (previous == null) {
        await txn.insert(_roundTable, {
          'book_id': book.id,
          'round_number': previousRound,
          'status': ReadingRound.statusReading,
          'start_time': now,
          'start_percentage': restoredPercentage,
          'end_percentage': 0.0,
          'end_position': null,
          'total_reading_time': totalTime,
          'create_time': now,
          'update_time': now,
        });
      } else {
        await txn.update(
          _roundTable,
          {
            'status': ReadingRound.statusReading,
            'end_time': null,
            'end_percentage': 0.0,
            'end_position': null,
            'total_reading_time': totalTime,
            'update_time': now,
          },
          where: 'id = ?',
          whereArgs: [previous['id']],
        );
      }

      await txn.update(
        _bookTable,
        {
          'current_round': previousRound,
          'last_read_position': restoredPosition,
          'reading_percentage': restoredPercentage,
          'update_time': now,
        },
        where: 'id = ?',
        whereArgs: [book.id],
      );
      return true;
    });

    if (!changed) {
      return book;
    }
    return bookDao.selectBookById(book.id);
  }

  static Future<Map<String, dynamic>?> _selectBookRow(
    DatabaseExecutor txn,
    int bookId,
  ) async {
    final rows = await txn.query(
      _bookTable,
      columns: [
        'id',
        'current_round',
        'reading_percentage',
        'last_read_position',
      ],
      where: 'id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<Map<String, dynamic>?> _selectRoundRow(
    DatabaseExecutor txn,
    int bookId,
    int roundNumber,
  ) async {
    final rows = await txn.query(
      _roundTable,
      where: 'book_id = ? AND round_number = ?',
      whereArgs: [bookId, roundNumber],
      orderBy: 'id ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  static Future<int> _sumReadingTime(
    DatabaseExecutor txn,
    int bookId,
    int roundNumber,
  ) async {
    final rows = await txn.rawQuery(
      'SELECT COALESCE(SUM(reading_time), 0) AS total FROM $_timeTable '
      'WHERE book_id = ? AND round = ?',
      [bookId, roundNumber],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }
}
