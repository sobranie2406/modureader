import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/dashboard_tiles_provider.dart';
import 'package:anx_reader/providers/reading_insights.dart';
import 'package:anx_reader/service/statistic/reading_insights.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const additions = [
  StatisticsDashboardTileType.recentReading,
  StatisticsDashboardTileType.weeklyReview,
  StatisticsDashboardTileType.dailyReadingAverage,
  StatisticsDashboardTileType.mostAnnotatedBooks,
];

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('en'));
    await L10n.delegate.load(const Locale('zh'));
  });

  test(
      'new cards can be added, reordered and restored without changing saved layouts',
      () {
    const saved = [
      StatisticsDashboardTileType.topBook,
      StatisticsDashboardTileType.totalTime
    ];
    Prefs().statisticsDashboardTiles = saved;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(dashboardTilesProvider.notifier);
    expect(notifier.workingTiles, saved);
    expect(notifier.availableTiles, containsAll(additions));
    for (final type in additions) {
      notifier.addTile(type);
    }
    final desired = [...additions.reversed, ...saved];
    notifier.reorder(desired.map((type) => type.index).toList());
    notifier.saveLayout();
    expect(Prefs().statisticsDashboardTiles, desired);
    final restored = DashboardTilesNotifier();
    addTearDown(restored.dispose);
    expect(restored.workingTiles, desired);
    restored.removeTile(additions.first);
    restored.saveLayout();
    expect(Prefs().statisticsDashboardTiles, isNot(contains(additions.first)));
    expect(defaultStatisticsDashboardTiles, isNot(contains(additions.first)));
    expect(StatisticsDashboardTileType.continueReading.index, 12);
  });

  for (final language in ['en', 'zh']) {
    for (final eink in [false, true]) {
      testWidgets(
          'four cards fit small cells with large text ($language, eink=$eink)',
          (tester) async {
        Prefs().eInkMode = eink;
        final book = Book.mock()
          ..title = 'A long title with enough text to wrap across the card'
          ..coverPath = 'missing-insight-cover.png';
        final data = ReadingInsights(
          totalSeconds: 3600,
          activeDays: 3,
          bestDaySeconds: 2400,
          weekSeconds: 3000,
          weekDays: 2,
          weekBooks: 2,
          recent: [ReadingInsightBook(book, lastDay: DateTime(2026, 10, 8))],
          mostAnnotated: [ReadingInsightBook(book, noteCount: 12)],
        );
        for (final type in additions) {
          await tester.pumpWidget(ProviderScope(
            overrides: [
              readingInsightsProvider.overrideWith((ref) async => data)
            ],
            child: MaterialApp(
              navigatorKey: navigatorKey,
              locale: Locale(language),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: Scaffold(
                  body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                child: Center(
                    child: SizedBox(
                  width: 170,
                  height: 190,
                  child: Consumer(
                      builder: (context, ref, _) => dashboardTileRegistry[type]!
                          .buildContent(context, ref)),
                )),
              )),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: type.name);
          final title = dashboardTileRegistry[type]!.metadata.title;
          expect(find.text(title), findsOneWidget);
          expect(find.byType(IconButton), findsOneWidget);
        }
      });
    }
  }

  testWidgets('all cards share one query and refresh is explicit',
      (tester) async {
    var queries = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        readingInsightsProvider.overrideWith((ref) async {
          queries++;
          return const ReadingInsights();
        })
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
            body: Column(children: [
          for (final type in additions)
            SizedBox(
                height: 130,
                child: Consumer(
                    builder: (context, ref, _) => dashboardTileRegistry[type]!
                        .buildContent(context, ref))),
        ])),
      ),
    ));
    await tester.pumpAndSettle();
    expect(queries, 1);
    expect(find.text('No reading history yet'), findsOneWidget);
    expect(find.text('No annotations yet'), findsOneWidget);
    await tester.tap(find.byType(IconButton).first);
    await tester.pumpAndSettle();
    expect(queries, 2);
    expect(tester.takeException(), isNull);
  });
}
