import 'package:anx_reader/dao/reading_round.dart';
import 'package:anx_reader/models/reading_round.dart';
import 'package:anx_reader/providers/sync_database_revision.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reading_round_provider.g.dart';

/// 某本书的全部阅读轮次（进行中 + 已完成，按轮次号升序）
@Riverpod(keepAlive: true)
class ReadingRounds extends _$ReadingRounds {
  @override
  Future<List<ReadingRound>> build(int bookId) async {
    // 同步合并后自动重算（轮次记录、撤销造成的时长改判等）
    ref.watch(syncDatabaseRevisionProvider);
    return readingRoundDao.selectRoundsByBookId(bookId);
  }

  void refresh() {
    ref.invalidateSelf();
  }
}
