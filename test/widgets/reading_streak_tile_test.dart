import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/reading_streak_provider.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/reading_streak_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Streak extends ReadingStreak {
  _Streak(this.data);
  final ReadingStreakData data;
  @override
  Future<ReadingStreakData> build() async => data;
}

void main() {
  for (final locale in [const Locale('en'), const Locale('zh', 'CN')]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('goal card fits small tiles at $locale scale=$scale',
          (tester) async {
        await tester.runAsync(() => L10n.delegate.load(locale));
        await tester.pumpWidget(ProviderScope(
            overrides: [
              readingStreakProvider.overrideWith(() => _Streak(
                  const ReadingStreakData(
                      currentStreak: 123,
                      longestStreak: 456,
                      lastQualifiedDay: null,
                      qualifiedDays: 789,
                      todaySeconds: 59,
                      goalSeconds: 600))),
            ],
            child: MaterialApp(
                locale: locale,
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: Scaffold(
                    body: Center(
                        child: SizedBox(
                            width: 210,
                            height: 200,
                            child: Consumer(
                                builder: (context, ref, _) =>
                                    const ReadingStreakTile()
                                        .buildContent(context, ref))))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      });
    }
  }
}
