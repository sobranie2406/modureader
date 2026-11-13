import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/total_reading_time.dart';
import 'package:anx_reader/widgets/statistic/statistics_dashboard_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReadingTime extends TotalReadingTime {
  @override
  Future<int> build() async => 3600;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<void> pumpTitle(WidgetTester tester, Size size,
      {double textScale = 1.0}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
        overrides: [totalReadingTimeProvider.overrideWith(_ReadingTime.new)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
            child: const StatisticsDashboardTitle(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(360, 740), const Size(1200, 740)]) {
    testWidgets('edit button shares the "since" line at $size', (tester) async {
      await pumpTitle(tester, size);
      final caption = find.textContaining(
          L10n.of(tester.element(find.byType(Scaffold))).statisticToPresent);
      final edit = find.byKey(const ValueKey('history-edit'));
      expect(caption, findsOneWidget);
      expect(edit, findsOneWidget);

      final captionRect = tester.getRect(caption);
      final editRect = tester.getRect(edit);
      // Same visual line: the button's centre sits on the caption's centre.
      expect((editRect.center.dy - captionRect.center.dy).abs(),
          lessThanOrEqualTo(4));
      // And it sits to the right of the date, not above/below it.
      expect(editRect.left, greaterThan(captionRect.right - 8));
      expect(editRect.top, lessThan(captionRect.bottom));
      expect(editRect.bottom, greaterThan(captionRect.top));
      // One compact line of chrome, not two stacked rows.
      expect(editRect.bottom - captionRect.top, lessThan(80));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('inline edit button still opens the layout editor',
      (tester) async {
    await pumpTitle(tester, const Size(360, 740));
    expect(find.byKey(const ValueKey('history-book-tap-action')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('history-edit')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('history-book-tap-action')), findsOneWidget);
    // While editing the inline pencil is replaced by the editor actions.
    expect(find.byKey(const ValueKey('history-edit')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
