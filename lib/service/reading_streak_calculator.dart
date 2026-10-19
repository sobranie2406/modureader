/// 打卡（连续阅读）判定的纯计算逻辑。
///
/// 与数据访问、偏好设置解耦，便于单元测试；调用方负责提供
/// 「每天累计阅读秒数」与「每日目标秒数」。
class ReadingStreakResult {
  const ReadingStreakResult({
    required this.currentStreak,
    required this.longestStreak,
    required this.qualifiedDays,
    required this.lastQualifiedDay,
    required this.todaySeconds,
  });

  /// 当前连击（达标天数）
  final int currentStreak;

  /// 历史最长连击（达标天数）
  final int longestStreak;

  /// 累计达标天数
  final int qualifiedDays;

  /// 最近一个达标日
  final DateTime? lastQualifiedDay;

  /// 今日累计阅读秒数
  final int todaySeconds;
}

class ReadingStreakCalculator {
  const ReadingStreakCalculator._();

  /// 依据 [dailySeconds]（`日期 -> 当天累计秒数`）计算打卡统计。
  ///
  /// - [goalSeconds] 为 0 时，任何有记录的一天都算达标（旧口径）
  /// - [today] 仅用于测试注入，默认为当前日期
  static ReadingStreakResult compute({
    required Map<DateTime, int> dailySeconds,
    required int goalSeconds,
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();

    final todaySeconds = dailySeconds.entries
        .where((entry) => _isSameDay(entry.key, now))
        .fold<int>(0, (sum, entry) => sum + entry.value);

    final qualifiedDays = dailySeconds.entries
        .where((entry) => _differenceInDays(entry.key, now) >= 0)
        .where((entry) => goalSeconds <= 0 || entry.value >= goalSeconds)
        .map((entry) => entry.key)
        .toList()
      ..sort();

    if (qualifiedDays.isEmpty) {
      return ReadingStreakResult(
        currentStreak: 0,
        longestStreak: 0,
        qualifiedDays: 0,
        lastQualifiedDay: null,
        todaySeconds: todaySeconds,
      );
    }

    return ReadingStreakResult(
      currentStreak: _computeCurrent(qualifiedDays, now),
      longestStreak: _computeLongest(qualifiedDays),
      qualifiedDays: qualifiedDays.length,
      lastQualifiedDay: qualifiedDays.last,
      todaySeconds: todaySeconds,
    );
  }

  static int _computeLongest(List<DateTime> sortedDays) {
    var longest = 1;
    var streak = 1;
    for (var i = 1; i < sortedDays.length; i++) {
      final previous = sortedDays[i - 1];
      final current = sortedDays[i];
      if (_differenceInDays(previous, current) == 1) {
        streak++;
      } else if (previous != current) {
        streak = 1;
      }
      if (streak > longest) {
        longest = streak;
      }
    }
    return longest;
  }

  static int _computeCurrent(List<DateTime> sortedDays, DateTime now) {
    final lastDay = sortedDays.last;
    final daysFromLastRead = _differenceInDays(lastDay, now);
    if (daysFromLastRead > 1) {
      return 0;
    }

    var streak = 1;
    for (var i = sortedDays.length - 2; i >= 0; i--) {
      // Calendar days, not 24-hour intervals across daylight-saving changes.
      if (_differenceInDays(sortedDays[i], sortedDays[i + 1]) == 1) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  static int _differenceInDays(DateTime from, DateTime to) {
    final fromUtc = DateTime.utc(from.year, from.month, from.day);
    final toUtc = DateTime.utc(to.year, to.month, to.day);
    return toUtc.difference(fromUtc).inDays;
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
