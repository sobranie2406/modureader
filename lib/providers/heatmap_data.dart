import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/providers/reading_data_revision.dart';
import 'package:anx_reader/providers/sync_database_revision.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'heatmap_data.g.dart';

@riverpod
class HeatmapData extends _$HeatmapData {
  @override
  FutureOr<Map<DateTime, int>> build() async {
    // 阅读时长入库后自动重算（见 reading_data_revision.dart）
    ref.watch(readingDataRevisionProvider);
    ref.watch(syncDatabaseRevisionProvider);
    return await readingTimeDao.selectAllReadingTimeGroupByDay();
  }
}
