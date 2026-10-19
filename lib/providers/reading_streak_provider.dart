import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/providers/reading_data_revision.dart';
import 'package:anx_reader/providers/sync_database_revision.dart';
import 'package:anx_reader/service/reading_streak_calculator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'reading_streak_provider.g.dart';

/// 打卡（连续阅读）统计数据。
///
/// 判定口径由 [Prefs.dailyCheckInMinutes] 决定：
/// - `0`：当天只要产生过阅读记录即算「打卡日」（历史行为）
/// - `>0`：当天跨书累计阅读时长达到该值才算「打卡日」
class ReadingStreakData {
  const ReadingStreakData({
    required this.currentStreak,
    required this.longestStreak,
    required this.lastQualifiedDay,
    required this.qualifiedDays,
    required this.todaySeconds,
    required this.goalSeconds,
  });

  final int currentStreak;
  final int longestStreak;

  /// 最近一个达标日（未达标/无记录时为 null）
  final DateTime? lastQualifiedDay;

  /// 累计达标天数
  final int qualifiedDays;

  /// 今日累计阅读秒数（无记录为 0）
  final int todaySeconds;

  /// 每日打卡目标秒数；`0` 表示「打开书籍即打卡」
  final int goalSeconds;

  bool get hasData => lastQualifiedDay != null;

  /// 是否启用了「阅读满 N 分钟才打卡」的目标口径（0 分钟表示旧口径）
  bool get hasGoal => goalSeconds > 0;

  /// 今日是否已完成打卡
  bool get hasQualifiedToday {
    final last = lastQualifiedDay;
    if (last == null) return false;
    final now = DateTime.now();
    return last.year == now.year &&
        last.month == now.month &&
        last.day == now.day;
  }

  /// 距离今日打卡还差的秒数（已达标或旧口径时为 0）
  int get remainingSeconds {
    if (goalSeconds <= 0 || hasQualifiedToday) return 0;
    final remaining = goalSeconds - todaySeconds;
    return remaining > 0 ? remaining : 0;
  }
}

@riverpod
class ReadingStreak extends _$ReadingStreak {
  @override
  Future<ReadingStreakData> build() async {
    // 阅读时长入库后自动重算（见 reading_data_revision.dart）
    ref.watch(readingDataRevisionProvider);
    ref.watch(syncDatabaseRevisionProvider);
    final prefs = Prefs();
    final goal = prefs.dailyCheckInMinutes;
    void onGoalChanged() {
      if (prefs.dailyCheckInMinutes != goal) ref.invalidateSelf();
    }

    prefs.addListener(onGoalChanged);
    ref.onDispose(() => prefs.removeListener(onGoalChanged));
    return _calculateStreak();
  }

  Future<ReadingStreakData> _calculateStreak() async {
    final dailySeconds = await readingTimeDao.selectAllReadingTimeGroupByDay();
    final goalSeconds = Prefs().dailyCheckInMinutes * 60;

    final result = ReadingStreakCalculator.compute(
      dailySeconds: dailySeconds,
      goalSeconds: goalSeconds,
    );

    return ReadingStreakData(
      currentStreak: result.currentStreak,
      longestStreak: result.longestStreak,
      lastQualifiedDay: result.lastQualifiedDay,
      qualifiedDays: result.qualifiedDays,
      todaySeconds: result.todaySeconds,
      goalSeconds: goalSeconds,
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _calculateStreak());
  }
}
