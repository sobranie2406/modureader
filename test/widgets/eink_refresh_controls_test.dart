import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/widgets/reading_page/eink_refresh_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  Widget screen(
          {required bool supported,
          required Future<bool> Function() refresh}) =>
      MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: EinkRefreshControls(
                      supported: Future.value(supported), refresh: refresh))));

  testWidgets('manual refresh and interval controls save 0..100',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(screen(
        supported: true,
        refresh: () async {
          calls++;
          return true;
        }));
    await tester.pumpAndSettle();
    expect(find.text(ModuStrings.label(const Locale('en'), '关闭', 'Off')),
        findsOneWidget);
    await tester.tap(find.text('Refresh now'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.byTooltip('+10'));
    await tester.pumpAndSettle();
    expect(Prefs().eInkRefreshPages, 10);
    await tester.tap(find.byTooltip('-1'));
    await tester.pumpAndSettle();
    expect(Prefs().eInkRefreshPages, 9);
    await tester.tap(find.byTooltip('-10'));
    await tester.pumpAndSettle();
    expect(Prefs().eInkRefreshPages, 0);
    await Prefs().setEInkRefreshPages(200);
    expect(Prefs().eInkRefreshPages, 100);
  });
  testWidgets(
      'unsupported devices explain why and do not expose fake auto refresh',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(screen(
        supported: false,
        refresh: () async {
          calls++;
          return true;
        }));
    await tester.pumpAndSettle();
    expect(find.textContaining('No supported E-Ink'), findsOneWidget);
    expect(find.byTooltip('+1'), findsNothing);
    await tester.tap(find.text('Refresh now'));
    expect(calls, 0);
  });
  testWidgets('failure is visible; controls fit a narrow screen and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: EinkRefreshControls(
                    supported: Future.value(true),
                    refresh: () async => false)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh now'));
    await tester.pumpAndSettle();
    expect(
        find.text('Refresh operation failed. Please retry.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
