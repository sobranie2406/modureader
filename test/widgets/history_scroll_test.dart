import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/widgets/home_navigation_shell.dart';
import 'package:anx_reader/widgets/common/app_scroll_behavior.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/statistic_data_model.dart';
import 'package:anx_reader/page/home_page/statistics_page.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/providers/total_reading_time.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Statistics extends StatisticData {
  _Statistics(this.count);
  final int count;
  @override
  Future<StatisticDataModel> build() async =>
      StatisticDataModel.mock().copyWith(readingTime: [
        120
      ], xLabels: [
        '1'
      ], bookReadingTime: [
        for (var i = 0; i < count; i++)
          {
            Book.mock()
              ..id = i + 1
              ..title = 'History $i': 120
          },
      ]);
}

class _Total extends TotalReadingTime {
  @override
  Future<int> build() async => 3600;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().statisticsDashboardTiles = [StatisticsDashboardTileType.totalTime];
  });

  for (final count in [1, 3, 40]) {
    for (final fast in [false, true]) {
      testWidgets(
          'history stays at bottom after overscroll (count=$count, fast=$fast)',
          (tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        late ScrollController controller;
        await tester.pumpWidget(ProviderScope(
          overrides: [
            statisticDataProvider.overrideWith(() => _Statistics(count)),
            totalReadingTimeProvider.overrideWith(_Total.new),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            scrollBehavior: const AppScrollBehavior()
                .copyWith(physics: const BouncingScrollPhysics()),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(0.5)),
              child: child!,
            ),
            theme: ThemeData(platform: TargetPlatform.android),
            locale: const Locale('en'),
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: L10n.localizationsDelegates,
            home:
                HomeNavigationShell(pageBuilder: (identifier, pageController) {
              controller = pageController!;
              return StatisticPage(controller: pageController);
            }),
          ),
        ));
        await tester.pumpAndSettle();
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pumpAndSettle();
        for (var i = 0; i < 25; i++) {
          if (fast) {
            await tester.flingFrom(
                const Offset(200, 580), const Offset(0, -450), 7000);
          } else {
            await tester.dragFrom(
                const Offset(200, 580), const Offset(0, -400));
          }
          await tester.pumpAndSettle();
        }
        final bottom = controller.position.maxScrollExtent;
        expect(controller.offset, closeTo(bottom, 1));
        expect(bottom, greaterThan(0));
        await tester.flingFrom(
            const Offset(200, 580), const Offset(0, -450), 7000);
        await tester.pumpAndSettle();
        expect(controller.offset, closeTo(bottom, 1));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('wide history date panel starts at the top', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        statisticDataProvider.overrideWith(() => _Statistics(1)),
        totalReadingTimeProvider.overrideWith(_Total.new),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('en'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: const Scaffold(body: StatisticPage()),
      ),
    ));
    await tester.pumpAndSettle();

    final row =
        tester.widget<Row>(find.byKey(const ValueKey('history-wide-layout')));
    expect(row.crossAxisAlignment, CrossAxisAlignment.start);
    expect(find.byType(DateBooks), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
