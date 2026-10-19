import 'package:anx_reader/dao/base_dao.dart';
import 'package:anx_reader/models/reading_round.dart';

class ReadingRoundDao extends BaseDao {
  ReadingRoundDao();

  static const String table = 'tb_reading_rounds';

  /// 查询某本书的全部轮次（按轮次号升序）。
  ///
  /// 总时长从 `tb_reading_time` 现算，保证另一端同步过来的时长立刻反映在
  /// 轮次明细里；`cancelled`（撤销后的软取消行）不展示。
  Future<List<ReadingRound>> selectRoundsByBookId(int bookId) {
    return rawQueryList(
      '''
      SELECT r.*, COALESCE((
        SELECT SUM(t.reading_time) FROM tb_reading_time t
        WHERE t.book_id = r.book_id AND t.round = r.round_number
      ), 0) AS total_reading_time
      FROM $table r
      WHERE r.book_id = ? AND r.status != ?
      ORDER BY r.round_number ASC
      ''',
      arguments: [bookId, ReadingRound.statusCancelled],
      mapper: ReadingRound.fromDb,
    );
  }

  /// 阅读计时入库后，把本次时长累加到该书进行中的轮次（幂等：无记录时静默跳过）。
  ///
  /// 注意：轮次切换（完成/撤销）以 `tb_reading_time` 的汇总为准确值，
  /// 这里只是滚动累计，方便未来做「本轮实时时长」而不必每次 SUM。
  Future<void> accumulateReadingTime({
    required int bookId,
    required int roundNumber,
    required int seconds,
  }) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE $table SET total_reading_time = total_reading_time + ?, update_time = ? '
      'WHERE book_id = ? AND round_number = ? AND status = ?',
      [
        seconds,
        DateTime.now().toIso8601String(),
        bookId,
        roundNumber,
        ReadingRound.statusReading,
      ],
    );
  }
}

final readingRoundDao = ReadingRoundDao();
