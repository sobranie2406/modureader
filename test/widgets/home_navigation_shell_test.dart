import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/enums/app_layout_mode.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/widgets/home_navigation_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

Widget _page(String identifier, ScrollController? controller) =>
    Text('page-$identifier');

Widget host({bool productionTopology = false}) {
  final app = MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: L10n.localizationsDelegates,
    home: const HomeNavigationShell(pageBuilder: _page),
  );
  if (!productionTopology) return app;
  // The real app exposes this shell as a const home route. That route is not
  // rebuilt when Prefs notifies, so the shell must refresh itself.
  return provider.ChangeNotifierProvider.value(
    value: Prefs(),
    child: provider.Consumer<Prefs>(
      builder: (context, prefs, child) => app,
    ),
  );
}

Future<void> pumpHome(
  WidgetTester tester,
  Size size, {
  bool productionTopology = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host(productionTopology: productionTopology));
  await tester.pumpAndSettle();
}

NavigationRail rail(WidgetTester tester) =>
    tester.widget<NavigationRail>(find.byType(NavigationRail));

BottomNavigationBar bottomBar(WidgetTester tester) =>
    tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().bottomNavigatorShowAI = true;
    Prefs().bottomNavigatorShowStatistics = true;
    Prefs().bottomNavigatorShowNote = true;
  });

  test('layout defaults, persistence and original automatic threshold',
      () async {
    expect(Prefs().appLayoutMode, AppLayoutMode.auto);
    for (final width in [320.0, 599.0, 600.0, 600.1, 1200.0]) {
      expect(AppLayoutMode.auto.usesWideLayout(width), width > 600);
      expect(AppLayoutMode.wide.usesWideLayout(width), isTrue);
      expect(AppLayoutMode.narrow.usesWideLayout(width), isFalse);
    }
    Prefs().appLayoutMode = AppLayoutMode.narrow;
    await Prefs().initPrefs();
    expect(Prefs().appLayoutMode, AppLayoutMode.narrow);
    await Prefs().prefs.setString('appLayoutMode', 'unknown');
    expect(Prefs().appLayoutMode, AppLayoutMode.auto);
  });

  for (final width in [390.0, 600.0, 601.0, 1200.0]) {
    testWidgets('manual layout and returning to auto at width $width',
        (tester) async {
      await pumpHome(tester, Size(width, 850), productionTopology: true);
      expect(find.byType(NavigationRail),
          width > 600 ? findsOneWidget : findsNothing);
      Prefs().appLayoutMode = AppLayoutMode.wide;
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      await tester.tap(find.byIcon(EvaIcons.settings_2));
      await tester.pumpAndSettle();
      expect(find.text('page-settings'), findsOneWidget);
      Prefs().appLayoutMode = AppLayoutMode.narrow;
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.text('page-settings'), findsOneWidget);
      Prefs().appLayoutMode = AppLayoutMode.auto;
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail),
          width > 600 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'wide rail shows a newly separated tab immediately after its switch '
      'changes', (tester) async {
    await pumpHome(tester, const Size(1200, 800));
    expect(rail(tester).destinations.length, 6);

    Prefs().bottomNavigatorShowNote = false;
    await tester.pump();
    expect(rail(tester).destinations.length, 5);
    expect(find.byIcon(Icons.note), findsNothing);

    Prefs().bottomNavigatorShowNote = true;
    await tester.pump();
    expect(rail(tester).destinations.length, 6);
    expect(find.byIcon(Icons.note), findsOneWidget);
  });

  testWidgets('wide rail keeps the other tab switches in sync too',
      (tester) async {
    await pumpHome(tester, const Size(1200, 800));

    Prefs().bottomNavigatorShowStatistics = false;
    await tester.pump();
    expect(rail(tester).destinations.length, 5);
    expect(find.byIcon(Icons.history), findsNothing);

    Prefs().bottomNavigatorShowAI = false;
    await tester.pump();
    expect(rail(tester).destinations.length, 4);

    Prefs().bottomNavigatorShowStatistics = true;
    Prefs().bottomNavigatorShowAI = true;
    await tester.pump();
    expect(rail(tester).destinations.length, 6);
  });

  testWidgets('remote switch hides and restores the remote destination',
      (tester) async {
    await pumpHome(tester, const Size(1200, 800));
    expect(rail(tester).destinations.length, 6);
    expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);

    Prefs().bottomNavigatorShowRemote = false;
    await tester.pump();
    expect(rail(tester).destinations.length, 5);
    expect(find.byIcon(Icons.cloud_download_outlined), findsNothing);

    Prefs().bottomNavigatorShowRemote = true;
    await tester.pump();
    expect(rail(tester).destinations.length, 6);
    expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);
  });

  testWidgets('bookshelf and settings remain when every optional tab is off',
      (tester) async {
    Prefs().bottomNavigatorShowRemote = false;
    Prefs().bottomNavigatorShowStatistics = false;
    Prefs().bottomNavigatorShowAI = false;
    Prefs().bottomNavigatorShowNote = false;
    await pumpHome(tester, const Size(1200, 800));

    expect(rail(tester).destinations.length, 2);
    expect(find.byIcon(Icons.cloud_download_outlined), findsNothing);
    expect(find.byIcon(Icons.history), findsNothing);
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    expect(find.byIcon(Icons.note), findsNothing);
    expect(find.byIcon(EvaIcons.book_open), findsOneWidget);
    expect(find.byIcon(EvaIcons.settings_2), findsOneWidget);
  });

  testWidgets('wide rail falls back when the selected tab is switched off',
      (tester) async {
    await pumpHome(tester, const Size(1200, 800));
    await tester.tap(find.byIcon(Icons.history));
    await tester.pumpAndSettle();
    expect(rail(tester).selectedIndex, 2);
    expect(find.text('page-statistics'), findsOneWidget);

    Prefs().bottomNavigatorShowStatistics = false;
    await tester.pump();
    expect(rail(tester).selectedIndex, 0);
    expect(find.text('page-bookshelf'), findsOneWidget);
  });

  testWidgets('compact bar shows a newly separated tab immediately',
      (tester) async {
    await pumpHome(tester, const Size(500, 800));
    expect(bottomBar(tester).items.length, 6);

    Prefs().bottomNavigatorShowAI = false;
    await tester.pump();
    expect(bottomBar(tester).items.length, 5);

    Prefs().bottomNavigatorShowAI = true;
    await tester.pump();
    expect(bottomBar(tester).items.length, 6);
  });

  testWidgets('rail refreshes under the const home route used by the app',
      (tester) async {
    await pumpHome(tester, const Size(1200, 800), productionTopology: true);
    expect(rail(tester).destinations.length, 6);

    Prefs().bottomNavigatorShowNote = false;
    await tester.pump();
    expect(rail(tester).destinations.length, 5);

    Prefs().bottomNavigatorShowNote = true;
    await tester.pump();
    expect(rail(tester).destinations.length, 6);
  });
}
