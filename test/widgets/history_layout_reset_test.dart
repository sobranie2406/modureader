import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/providers/dashboard_tiles_provider.dart';
import 'package:modu_reader/providers/total_reading_time.dart';
import 'package:modu_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:modu_reader/widgets/statistic/statistics_dashboard_title.dart';
import 'package:modu_reader/widgets/common/anx_segmented_button.dart';
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
    SharedPreferences.setMockInitialValues({'unrelatedSetting': 'keep'});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('en'));
    await L10n.delegate.load(const Locale('zh'));
  });

  test(
      'tap choice defaults to details; draft, discard, save and reload are isolated',
      () async {
    expect(Prefs().historyOpenBookDirectly, isFalse);
    final notifier = DashboardTilesNotifier();
    addTearDown(notifier.dispose);
    notifier.startEditing();
    expect(notifier.state.isEditing, isTrue);
    expect(notifier.state.hasUnsavedChanges, isFalse);
    notifier.setOpenBookDirectly(true);
    expect(notifier.state.hasUnsavedChanges, isTrue);
    expect(Prefs().historyOpenBookDirectly, isFalse);
    Prefs().developerOptionsEnabled = true;
    expect(notifier.state.openBookDirectly, isTrue);
    expect(notifier.state.isEditing, isTrue);
    notifier.discardChanges();
    expect(notifier.state.openBookDirectly, isFalse);
    notifier.setOpenBookDirectly(true);
    notifier.saveLayout();
    expect(Prefs().historyOpenBookDirectly, isTrue);
    expect(notifier.state.isEditing, isFalse);
    await Prefs().initPrefs();
    final reloaded = DashboardTilesNotifier();
    addTearDown(reloaded.dispose);
    expect(reloaded.state.openBookDirectly, isTrue);
    reloaded.restoreDefaults();
    expect(Prefs().historyOpenBookDirectly, isTrue,
        reason:
            'layout reset must not silently change the selected tap action');
    reloaded.setOpenBookDirectly(false);
    reloaded.saveLayout();
    expect(Prefs().historyOpenBookDirectly, isFalse);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('tap selector only appears while editing and saves at $width',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 740);
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
          overrides: [totalReadingTimeProvider.overrideWith(_ReadingTime.new)]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: const Scaffold(body: StatisticsDashboardTitle()))));
      await tester.pumpAndSettle();
      final selector = find.byKey(const ValueKey('history-book-tap-action'));
      expect(selector, findsNothing);
      await tester.tap(find.byKey(const ValueKey('history-edit')));
      await tester.pumpAndSettle();
      expect(
          tester.widget<AnxSegmentedButton<bool>>(selector).selected, {false});
      await tester.tap(find.text('Read directly'));
      await tester.pumpAndSettle();
      expect(Prefs().historyOpenBookDirectly, isFalse);
      expect(
          tester.widget<AnxSegmentedButton<bool>>(selector).selected, {true});
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
      expect(selector, findsNothing);
      expect(Prefs().historyOpenBookDirectly, isTrue);
      await tester.tap(find.byKey(const ValueKey('history-edit')));
      await tester.pumpAndSettle();
      expect(
          tester.widget<AnxSegmentedButton<bool>>(selector).selected, {true});
      expect(tester.takeException(), isNull);
    });
  }

  for (final saveFirst in [false, true]) {
    test('reset restores card membership/order and persists (saved=$saveFirst)',
        () async {
      final notifier = DashboardTilesNotifier();
      addTearDown(notifier.dispose);
      notifier.removeTile(defaultStatisticsDashboardTiles.first);
      notifier.addTile(StatisticsDashboardTileType.totalTime);
      notifier.reorder(
          notifier.workingTiles.reversed.map((type) => type.index).toList());
      if (saveFirst) notifier.saveLayout();
      final before = {
        for (final key in Prefs().prefs.getKeys())
          if (key != 'statisticsDashboardTiles') key: Prefs().prefs.get(key),
      };

      notifier.restoreDefaults();
      expect(notifier.workingTiles, defaultStatisticsDashboardTiles);
      expect(Prefs().statisticsDashboardTiles, defaultStatisticsDashboardTiles);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final state = container.read(dashboardTilesProvider);
      expect(state.savedTiles, defaultStatisticsDashboardTiles);
      expect(state.workingTiles, defaultStatisticsDashboardTiles);
      expect(state.hasUnsavedChanges, isFalse);
      expect(state.isEditing, isFalse);
      notifier.restoreDefaults();
      expect(notifier.workingTiles, defaultStatisticsDashboardTiles);
      expect({
        for (final key in Prefs().prefs.getKeys())
          if (key != 'statisticsDashboardTiles') key: Prefs().prefs.get(key),
      }, before, reason: 'reset must only change the layout preference');
    });
  }

  for (final language in ['zh', 'en']) {
    testWidgets(
        'reset is edit-only, immediate and fits a narrow header ($language)',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Prefs().statisticsDashboardTiles = [StatisticsDashboardTileType.topBook];
      final container = ProviderContainer(overrides: [
        totalReadingTimeProvider.overrideWith(_ReadingTime.new),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(
            body: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: StatisticsDashboardTitle(),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final label = language == 'zh' ? '恢复默认' : 'Restore defaults';
      expect(find.text(label), findsNothing);
      container
          .read(dashboardTilesProvider.notifier)
          .addTile(StatisticsDashboardTileType.totalTime);
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text(label), findsNothing);
      expect(find.byIcon(Icons.save), findsNothing);
      expect(Prefs().statisticsDashboardTiles, defaultStatisticsDashboardTiles);
      final state = container.read(dashboardTilesProvider);
      expect(state.workingTiles, defaultStatisticsDashboardTiles);
      expect(state.hasUnsavedChanges, isFalse);
      expect(state.isEditing, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
