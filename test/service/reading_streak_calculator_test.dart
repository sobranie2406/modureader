import 'package:anx_reader/service/reading_streak_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

/// 打卡判定单元测试。
///
/// 约定：`dailySeconds` 已是「当天所有书籍累计秒数」，
/// `goalSeconds` 为 0 时表示旧口径（有记录即打卡）。
void main() {
  DateTime day(int month, int d) => DateTime(2026, month, d);

  const tenMinutes = 600;

  group('ReadingStreakCalculator', () {
    test('future-dated records cannot award future check-ins', () {
      final result = ReadingStreakCalculator.compute(
          dailySeconds: {day(10, 4): 600, day(10, 5): 600, day(10, 9): 600},
          goalSeconds: tenMinutes,
          today: day(10, 5));
      expect(result.currentStreak, 2);
      expect(result.qualifiedDays, 2);
      expect(result.lastQualifiedDay, day(10, 5));
    });

    test('calendar streak survives daylight-saving clock changes', () {
      for (final start in [DateTime(2026, 3, 7), DateTime(2026, 10, 31)]) {
        final days = List.generate(
            4, (i) => DateTime(start.year, start.month, start.day + i));
        final result = ReadingStreakCalculator.compute(
            dailySeconds: {for (final date in days) date: 600},
            goalSeconds: tenMinutes,
            today: days.last);
        expect(result.currentStreak, 4);
        expect(result.longestStreak, 4);
      }
    });
    test('没有任何阅读记录时全部为 0', () {
      final result = ReadingStreakCalculator.compute(
        dailySeconds: const {},
        goalSeconds: tenMinutes,
        today: day(10, 5),
      );

      expect(result.currentStreak, 0);
      expect(result.longestStreak, 0);
      expect(result.qualifiedDays, 0);
      expect(result.lastQualifiedDay, isNull);
      expect(result.todaySeconds, 0);
    });

    test('目标为 0（旧口径）时任何有记录的天都算打卡', () {
      final result = ReadingStreakCalculator.compute(
        dailySeconds: {
          day(10, 3): 3, // 只有 3 秒
          day(10, 4): 1,
          day(10, 5): 0,
        },
        goalSeconds: 0,
        today: day(10, 5),
      );

      expect(result.qualifiedDays, 3);
      expect(result.currentStreak, 3);
      expect(result.longestStreak, 3);
    });

    test('默认 10 分钟：几秒钟的天被剔除，连击随之断裂', () {
      final result = ReadingStreakCalculator.compute(
        dailySeconds: {
          day(10, 1): tenMinutes,
          day(10, 2): 59, // 不足 1 分钟
          day(10, 3): tenMinutes,
        },
        goalSeconds: tenMinutes,
        today: day(10, 3),
      );

      expect(result.qualifiedDays, 2);
      expect(result.longestStreak, 1);
      expect(result.currentStreak, 1);
      expect(result.lastQualifiedDay, day(10, 3));
    });

    test('跨书累计由上层求和：当天合计达标即算打卡', () {
      // A 书 6 分钟 + B 书 5 分钟 = 11 分钟
      final result = ReadingStreakCalculator.compute(
        dailySeconds: {day(10, 5): 360 + 300},
        goalSeconds: tenMinutes,
        today: day(10, 5),
      );

      expect(result.currentStreak, 1);
      expect(result.todaySeconds, 660);
    });

    test('今日未达标：今日进度照常可读，连击从最近达标日算起', () {
      final result = ReadingStreakCalculator.compute(
        dailySeconds: {
          day(10, 4): tenMinutes,
          day(10, 5): 120, // 2 分钟，未达标
        },
        goalSeconds: tenMinutes,
        today: day(10, 5),
      );

      expect(result.todaySeconds, 120);
      expect(result.currentStreak, 1);
      expect(result.lastQualifiedDay, day(10, 4));
    });

    test('连续多日达标累加连击，断档后重新计数', () {
      final result = ReadingStreakCalculator.compute(
        dailySeconds: {
          day(9, 28): 600,
          day(9, 29): 700,
          day(9, 30): 800,
          // 10-01 断档
          day(10, 2): 900,
          day(10, 3): 1000,
        },
        goalSeconds: tenMinutes,
        today: day(10, 3),
      );

      expect(result.qualifiedDays, 5);
      expect(result.longestStreak, 3);
      expect(result.currentStreak, 2);
    });

    test('超过一天未达标时当前连击归零，历史最长仍保留', () {
      final result = ReadingStreakCalculator.compute(
        dailySeconds: {day(9, 30): 1200},
        goalSeconds: tenMinutes,
        today: day(10, 3),
      );

      expect(result.currentStreak, 0);
      expect(result.longestStreak, 1);
    });

    test('恰好等于目标秒数算达标（边界）', () {
      final result = ReadingStreakCalculator.compute(
        dailySeconds: {day(10, 5): tenMinutes},
        goalSeconds: tenMinutes,
        today: day(10, 5),
      );

      expect(result.qualifiedDays, 1);
      expect(result.currentStreak, 1);
    });

    test('比目标少 1 秒不算达标（边界）', () {
      final result = ReadingStreakCalculator.compute(
        dailySeconds: {day(10, 5): tenMinutes - 1},
        goalSeconds: tenMinutes,
        today: day(10, 5),
      );

      expect(result.qualifiedDays, 0);
      expect(result.currentStreak, 0);
      expect(result.todaySeconds, 599);
    });
  });
}
