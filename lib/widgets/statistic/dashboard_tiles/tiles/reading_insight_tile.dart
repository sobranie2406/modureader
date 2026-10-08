import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/providers/reading_insights.dart';
import 'package:anx_reader/service/statistic/reading_insights.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:anx_reader/widgets/statistic/reading_history_book_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReadingInsightTile extends StatisticsDashboardTileBase {
  const ReadingInsightTile(this.type);

  @override
  final StatisticsDashboardTileType type;

  @override
  StatisticsDashboardTileMetadata get metadata {
    final context = navigatorKey.currentContext!;
    final (title, description, icon, columns) = switch (type) {
      StatisticsDashboardTileType.recentReading => (
          ModuStrings.text(context, '最近阅读', 'Recently read'),
          ModuStrings.text(context, '最近读过的三本书，点击书名或封面继续阅读。',
              'Your three most recently read books. Tap a title or cover to continue.'),
          Icons.history,
          4,
        ),
      StatisticsDashboardTileType.weeklyReview => (
          ModuStrings.text(context, '本周阅读回顾', 'This week'),
          ModuStrings.text(context, '本周一至今天的阅读时长、天数和书籍数。',
              'Reading time, active days and books from Monday through today.'),
          Icons.date_range_outlined,
          2,
        ),
      StatisticsDashboardTileType.dailyReadingAverage => (
          ModuStrings.text(context, '阅读日均时长', 'Daily reading average'),
          ModuStrings.text(context, '累计时长除以实际阅读天数，不计未阅读的日期。',
              'Total reading time divided by active reading days, excluding days without reading.'),
          Icons.av_timer_outlined,
          2,
        ),
      StatisticsDashboardTileType.mostAnnotatedBooks => (
          ModuStrings.text(context, '笔记最多的书', 'Most annotated'),
          ModuStrings.text(context, '按累计划线、高亮和书签数量排列的前三本书。',
              'Top three books by all-time highlights, underlines and bookmarks.'),
          Icons.edit_note_outlined,
          4,
        ),
      _ => throw ArgumentError.value(type, 'type'),
    };
    return StatisticsDashboardTileMetadata(
        type: type,
        title: title,
        description: description,
        columnSpan: columns,
        rowSpan: 2,
        icon: icon);
  }

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final details = metadata;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(details.title,
                style: Theme.of(context).textTheme.titleSmall)),
        IconButton(
          tooltip: ModuStrings.text(context, '刷新', 'Refresh'),
          visualDensity: VisualDensity.compact,
          iconSize: 18,
          onPressed: () => ref.invalidate(readingInsightsProvider),
          icon: const Icon(Icons.refresh),
        ),
      ]),
      Expanded(
          child: AsyncSkeletonWrapper<ReadingInsights>(
        asyncValue: ref.watch(readingInsightsProvider),
        enabled: false,
        builder: (data, _) => SingleChildScrollView(
          child: switch (type) {
            StatisticsDashboardTileType.recentReading =>
              _bookList(context, data.recent, recent: true),
            StatisticsDashboardTileType.mostAnnotatedBooks =>
              _bookList(context, data.mostAnnotated, recent: false),
            StatisticsDashboardTileType.weeklyReview => _metrics(
                context,
                duration: data.weekSeconds,
                labels: [
                  ModuStrings.format(
                      context, '本周阅读 {days} 天', '{days} active days this week',
                      values: {'days': data.weekDays}),
                  ModuStrings.format(
                      context, '读过 {books} 本书', '{books} books read',
                      values: {'books': data.weekBooks}),
                ],
                explanation:
                    ModuStrings.text(context, '本周一至今天', 'Monday through today'),
              ),
            StatisticsDashboardTileType.dailyReadingAverage => _metrics(
                context,
                duration: data.dailyAverageSeconds,
                labels: [
                  ModuStrings.format(
                      context, '累计阅读 {days} 天', '{days} active days in total',
                      values: {'days': data.activeDays}),
                  ModuStrings.format(
                      context, '单日最多 {duration}', 'Best day: {duration}',
                      values: {
                        'duration': _duration(context, data.bestDaySeconds)
                      }),
                ],
                explanation: ModuStrings.text(context, '仅按有阅读记录的日期计算',
                    'Average over active reading days only'),
              ),
            _ => const SizedBox.shrink(),
          },
        ),
      )),
    ]);
  }

  Widget _metrics(BuildContext context,
          {required int duration,
          required List<String> labels,
          required String explanation}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_duration(context, duration),
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [for (final label in labels) _pill(context, label)]),
          const SizedBox(height: 8),
          Text(explanation, style: Theme.of(context).textTheme.bodySmall),
        ],
      );

  Widget _bookList(BuildContext context, List<ReadingInsightBook> entries,
      {required bool recent}) {
    if (entries.isEmpty) {
      return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(recent
              ? ModuStrings.text(context, '还没有阅读记录', 'No reading history yet')
              : ModuStrings.text(context, '还没有笔记记录', 'No annotations yet')));
    }
    return Column(children: [
      for (final entry in entries)
        ReadingHistoryBookLink(
            book: entry.book,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                BookCover(book: entry.book, width: 40, height: 56, radius: 5),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 4),
                    Wrap(spacing: 4, runSpacing: 4, children: [
                      _pill(
                          context,
                          recent
                              ? MaterialLocalizations.of(context)
                                  .formatCompactDate(entry.lastDay!)
                              : ModuStrings.format(
                                  context, '{count} 条笔记', '{count} annotations',
                                  values: {'count': entry.noteCount})),
                      _pill(
                          context,
                          entry.book.isDeleted
                              ? L10n.of(context).bookDeleted
                              : '${(entry.book.readingPercentage.clamp(0, 1) * 100).round()}%'),
                    ]),
                  ],
                )),
              ]),
            )),
    ]);
  }

  Widget _pill(BuildContext context, String label) {
    final colors = Theme.of(context).colorScheme;
    final eink = Prefs().eInkMode;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: eink ? Colors.white : colors.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
        border: eink ? Border.all(color: Colors.black) : null,
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: eink ? Colors.black : colors.onSecondaryContainer)),
    );
  }

  String _duration(BuildContext context, int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = seconds % 3600 ~/ 60;
    if (hours > 0) {
      return ModuStrings.format(
          context, '{hours}小时 {minutes}分钟', '{hours}h {minutes}m',
          values: {'hours': hours, 'minutes': minutes});
    }
    if (seconds > 0 && seconds < 60) {
      return ModuStrings.text(context, '不足1分钟', 'Less than 1m');
    }
    return ModuStrings.format(context, '{minutes}分钟', '{minutes}m',
        values: {'minutes': minutes});
  }
}
