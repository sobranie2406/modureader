import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/reading_streak_provider.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReadingStreakTile extends StatisticsDashboardTileBase {
  const ReadingStreakTile();

  @override
  StatisticsDashboardTileMetadata get metadata {
    final l10n = l10nLocal;
    return StatisticsDashboardTileMetadata(
      type: StatisticsDashboardTileType.readingStreak,
      title: l10n.tileReadingStreakTitle,
      description: l10n.tileReadingStreakDescription,
      columnSpan: 2,
      rowSpan: 2,
      icon: Icons.local_fire_department_outlined,
    );
  }

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final asyncValue = ref.watch(readingStreakProvider);
    return AsyncSkeletonWrapper<ReadingStreakData>(
      asyncValue: asyncValue,
      mock: const ReadingStreakData(
        currentStreak: 4,
        longestStreak: 12,
        lastQualifiedDay: null,
        qualifiedDays: 12,
        todaySeconds: 0,
        goalSeconds: 600,
      ),
      builder: (data, _) => _ReadingStreakContent(data: data),
    );
  }
}

class _ReadingStreakContent extends StatelessWidget {
  const _ReadingStreakContent({required this.data});

  final ReadingStreakData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final hasQualifiedToday = data.hasQualifiedToday;
    final fireColor = hasQualifiedToday
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;

    final encouragement = hasQualifiedToday
        ? l10n.tileReadingStreakEncouragementActive
        : data.hasGoal
            ? l10n.tileReadingStreakEncouragementGoalPending
            : l10n.tileReadingStreakEncouragementInactive;

    return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_fire_department, color: fireColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.tileReadingStreakCurrent(
                                    data.currentStreak),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: fireColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _goalSubtitle(l10n, hasQualifiedToday),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                    if (data.hasGoal) ...[
                      const SizedBox(height: 10),
                      _GoalProgress(data: data),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _StatPill(
                              label: l10n.tileReadingStreakBestLabel,
                              value: l10n
                                  .tileReadingStreakCurrent(data.longestStreak),
                            ),
                          ),
                        ),
                        if (data.hasGoal && data.qualifiedDays > 0) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: _StatPill(
                                label: l10n.tileReadingStreakQualifiedDaysLabel,
                                value:
                                    '${data.qualifiedDays} ${l10n.tileReadingDaysUnit}',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    Text(
                      encouragement,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                )))));
  }

  /// 连击数字下方的一行状态说明
  String _goalSubtitle(L10n l10n, bool hasQualifiedToday) {
    if (!data.hasGoal) {
      return hasQualifiedToday
          ? l10n.tileReadingStreakSubtitleActive
          : l10n.tileReadingStreakSubtitleInactive;
    }
    if (hasQualifiedToday) {
      return l10n.tileReadingStreakTodayDone;
    }
    final remainingMinutes = (data.remainingSeconds / 60).ceil();
    return l10n.tileReadingStreakTodayRemaining('$remainingMinutes');
  }
}

/// 今日打卡进度：进度条 + 「今日已读 / 目标」文字
class _GoalProgress extends StatelessWidget {
  const _GoalProgress({required this.data});

  final ReadingStreakData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final goalMinutes = (data.goalSeconds / 60).round();
    final readMinutes = data.todaySeconds ~/ 60;
    final progress = data.goalSeconds <= 0
        ? 0.0
        : (data.todaySeconds / data.goalSeconds).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.tileReadingStreakTodayProgress('$readMinutes', '$goalMinutes'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          Text(
            value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
