import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/widgets/home_navigation_shell.dart';
import 'package:modu_reader/widgets/page_router/reading_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final width in [390.0, 1200.0]) {
    for (final animate in [true, false]) {
      testWidgets(
          'return keeps home geometry while system bars restore, width=$width, animate=$animate',
          (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final metrics = ValueNotifier(MediaQueryData(
          size: Size(width, 850),
          padding: const EdgeInsets.only(top: 24, bottom: 20),
          viewPadding: const EdgeInsets.only(top: 24, bottom: 20),
        ));
        addTearDown(metrics.dispose);
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(MaterialApp(
          navigatorKey: navigator,
          locale: const Locale('en'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: L10n.localizationsDelegates,
          builder: (context, child) => ValueListenableBuilder<MediaQueryData>(
            valueListenable: metrics,
            builder: (_, data, __) => MediaQuery(data: data, child: child!),
          ),
          home: HomeNavigationShell(
              pageBuilder: (_, __) => Scaffold(
                    body: SafeArea(
                        child: Column(children: [
                      const SizedBox(
                          key: ValueKey('shelf-cover'),
                          width: 100,
                          height: 160),
                      const Spacer(),
                      Builder(
                          builder: (context) => Text(
                                '${MediaQuery.viewInsetsOf(context).bottom}',
                                key: const ValueKey('keyboard-inset'),
                              )),
                    ])),
                  )),
        ));
        await tester.pumpAndSettle();
        final cover =
            find.byKey(const ValueKey('shelf-cover'), skipOffstage: false);
        final before = tester.getRect(cover);
        navigator.currentState!.push(readingRoute<void>(
            animate: animate,
            builder: (context) => Scaffold(
                body: Text(
                    'Reader inset: ${MediaQuery.paddingOf(context).top}'))));
        await tester.pumpAndSettle();
        metrics.value = metrics.value
            .copyWith(padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero);
        await tester.pump();
        expect(find.text('Reader inset: 0.0'), findsOneWidget);
        expect(tester.getRect(cover), before,
            reason: 'The hidden shelf is the return Hero destination');
        navigator.currentState!.pop();
        await tester.pump();
        for (final milliseconds in [16, 200, 420]) {
          await tester.pump(Duration(milliseconds: milliseconds));
          expect(tester.getRect(cover), before,
              reason: 'Returning before OS bars finish restoring');
        }
        metrics.value = metrics.value.copyWith(
          padding: const EdgeInsets.only(top: 24, bottom: 20),
          viewPadding: const EdgeInsets.only(top: 24, bottom: 20),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(cover), before);
        metrics.value = metrics.value.copyWith(
            viewInsets: const EdgeInsets.only(bottom: 300),
            padding: const EdgeInsets.only(top: 24));
        await tester.pumpAndSettle();
        final homeMedia = tester
            .widget<MediaQuery>(find
                .descendant(
                    of: find.byType(HomeNavigationShell),
                    matching: find.byType(MediaQuery))
                .first)
            .data;
        expect(homeMedia.viewInsets.bottom, 300);
        expect(homeMedia.padding.bottom, 0);
        metrics.value = metrics.value.copyWith(
          size: Size(width + 100, 850),
          viewInsets: EdgeInsets.zero,
          padding: const EdgeInsets.only(top: 32),
          viewPadding: const EdgeInsets.only(top: 32),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(cover).top, 32,
            reason: 'New window geometry must not retain old safe areas');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
