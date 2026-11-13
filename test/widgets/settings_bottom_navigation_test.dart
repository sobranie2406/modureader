import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/page/home_page/settings_page.dart';
import 'package:anx_reader/page/settings_page/bug_report.dart';
import 'package:anx_reader/page/settings_page/developer/developer_options_page.dart';
import 'package:anx_reader/page/settings_page/settings_page.dart';
import 'package:anx_reader/widgets/home_navigation_metrics.dart';
import 'package:anx_reader/widgets/settings/about.dart';
import 'package:anx_reader/widgets/common/container/filled_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_floating_bottom_bar/flutter_floating_bottom_bar.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Modu',
      packageName: 'com.modu.reader',
      version: '1.1.6-test.1',
      buildNumber: '10048',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    // Do not reuse a cached Future from a previous test's FakeAsync zone.
    rootBundle.evict('pubspec.yaml');
  });

  for (final width in [390.0, 1200.0]) {
    for (final bottom in [0.0, 24.0, 48.0]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets(
            'About clears floating bar and opens as settings: width=$width inset=$bottom scale=$scale',
            (tester) async {
          tester.view.physicalSize = Size(width, 740);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          late ScrollController controller;
          await tester.pumpWidget(ProviderScope(
              child: MaterialApp(
            navigatorKey: navigatorKey,
            locale: const Locale('zh'),
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: const [
              L10n.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: EdgeInsets.only(bottom: bottom),
                viewPadding: EdgeInsets.only(bottom: bottom),
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: Builder(
                builder: (context) => Scaffold(
                      extendBody: true,
                      body: BottomBar(
                        width: 330,
                        offset: HomeNavigationMetrics.barOffset,
                        hideOnScroll: false,
                        body: (_, suppliedController) {
                          controller = suppliedController;
                          return HomeNavigationBody(
                            hasBottomBar: true,
                            scrollBehindBar: true,
                            child: SettingsPage(controller: suppliedController),
                          );
                        },
                        child: SizedBox(
                          key: const ValueKey('floating-bar'),
                          height: HomeNavigationMetrics.barHeightFor(context),
                          child: const ColoredBox(color: Colors.blue),
                        ),
                      ),
                    )),
          )));
          await tester.pumpAndSettle();
          expect(controller.hasClients, isTrue);
          // Lazy variable-height tiles refine maxScrollExtent after layout.
          // Reach the actual bottom, not the initial estimate (large text can
          // change it after the first jump). Keep the clearance assertion exact.
          for (var attempt = 0; attempt < 5; attempt++) {
            controller.jumpTo(controller.position.maxScrollExtent);
            await tester.pumpAndSettle();
            if (controller.position.extentAfter < 0.01) break;
          }
          expect(controller.position.extentAfter, lessThan(0.01));
          final about = find.byType(About);
          final aboutFrame = tester.widget<FilledContainer>(find
              .ancestor(of: about, matching: find.byType(FilledContainer))
              .first);
          expect(aboutFrame.radius, 12);
          expect(aboutFrame.margin,
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6));
          final aboutRect = tester.getRect(about);
          final barRect =
              tester.getRect(find.byKey(const ValueKey('floating-bar')));
          expect(
              aboutRect.bottom,
              lessThanOrEqualTo(
                  barRect.top - HomeNavigationMetrics.contentGap));
          expect(aboutRect.top, greaterThan(0));
          await tester.tap(about);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          final aboutSettings = find.byType(AboutSettings);
          expect(aboutSettings, findsOneWidget);
          final page = tester.widget<SettingsPageBody>(find
              .ancestor(
                  of: aboutSettings, matching: find.byType(SettingsPageBody))
              .first);
          expect(page.isMobile, width <= 600);
          expect(navigatorKey.currentState!.canPop(), width <= 600);
          expect(find.byKey(const ValueKey('about-app-frame')), findsOneWidget);
          expect(find.textContaining('1.1.6-test.1+10048'), findsOneWidget);
          final appFrame = tester.getRect(find.descendant(
              of: find.byKey(const ValueKey('about-app-frame')),
              matching: find.byType(FilledContainer)));
          final contentScroll = find
              .descendant(of: aboutSettings, matching: find.byType(Scrollable))
              .first;
          final credits = find.byKey(const ValueKey('about-credits-frame'));
          await tester.scrollUntilVisible(credits, 200,
              scrollable: contentScroll);
          await tester.pumpAndSettle();
          final creditsFrame = tester.getRect(find.descendant(
              of: credits, matching: find.byType(FilledContainer)));
          expect(creditsFrame.left, closeTo(appFrame.left, 0.01));
          expect(creditsFrame.right, closeTo(appFrame.right, 0.01));
          expect(creditsFrame.height, greaterThan(0));
          final feedback = find.byKey(const ValueKey('about-feedback'));
          await tester.scrollUntilVisible(feedback, -200,
              scrollable: contentScroll);
          await Scrollable.ensureVisible(tester.element(feedback),
              alignment: .5);
          await tester.pumpAndSettle();
          // Linux diagnostics starts a real process; let its I/O finish outside
          // FakeAsync before waiting for the loading animation to settle.
          await tester.runAsync(() async {
            await tester.tap(feedback);
            for (var attempt = 0; attempt < 300; attempt++) {
              await tester.pump(const Duration(milliseconds: 50));
              if (find.byType(BugReportSettings).evaluate().isNotEmpty &&
                  find.byType(LinearProgressIndicator).evaluate().isEmpty) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 50));
            }
          });
          expect(find.byType(LinearProgressIndicator), findsNothing);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.byType(BugReportSettings), findsOneWidget);
          Navigator.of(tester.element(find.byType(BugReportSettings))).pop();
          await tester.pumpAndSettle();
          expect(find.byType(AboutSettings), findsOneWidget);
          expect(find.byType(BugReportSettings), findsNothing);
          if (width <= 600) {
            Navigator.of(tester.element(find.byType(AboutSettings))).pop();
            await tester.pumpAndSettle();
            expect(find.byType(AboutSettings), findsNothing);
          } else {
            expect(navigatorKey.currentState!.canPop(), isFalse);
            expect(tester.widget<About>(find.byType(About)).selected, isTrue);
          }
          expect(find.byType(SettingsPage), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('About returns from licenses and developer options',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('zh'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const Scaffold(body: About()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(About));
    await tester.pumpAndSettle();
    final l10n = L10n.of(tester.element(find.byType(AboutSettings)));
    final contentScroll = find
        .descendant(
            of: find.byType(AboutSettings), matching: find.byType(Scrollable))
        .first;
    final licenses = find.text(l10n.appLicense);
    await tester.scrollUntilVisible(licenses, 200, scrollable: contentScroll);
    await Scrollable.ensureVisible(tester.element(licenses), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(licenses);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AboutSettings), findsOneWidget);

    final version = find.textContaining('1.1.6-test.1+10048');
    await tester.scrollUntilVisible(version, -200, scrollable: contentScroll);
    await Scrollable.ensureVisible(tester.element(version), alignment: .5);
    await tester.pumpAndSettle();
    for (var i = 0; i < 7; i++) {
      await tester.tap(version);
    }
    await tester.pumpAndSettle();
    expect(Prefs().developerOptionsEnabled, isTrue);
    expect(find.byType(DeveloperOptionsPage), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AboutSettings), findsOneWidget);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(About), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}
