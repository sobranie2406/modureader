import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reading_data_revision.g.dart';

/// 阅读数据版本号（时长 / 打卡 / 热力图共用）。
///
/// 任何写入或删除 `tb_reading_time` 的代码路径都应调用
/// [bumpReadingDataRevision]，依赖它的统计 provider 会自动重算。
/// 这样刷新就与调用方的 Widget 生命周期无关——例如阅读页在
/// `dispose()` 里补写最后一段时长时，已经无法安全使用 `ref`。
final ValueNotifier<int> readingDataRevision = ValueNotifier<int>(0);

/// 标记阅读数据已变更（时长入库、删除记录等）
void bumpReadingDataRevision() {
  readingDataRevision.value++;
}

@riverpod
class ReadingDataRevision extends _$ReadingDataRevision {
  @override
  int build() {
    void listener() => ref.invalidateSelf();
    readingDataRevision.addListener(listener);
    ref.onDispose(() => readingDataRevision.removeListener(listener));
    return readingDataRevision.value;
  }
}
