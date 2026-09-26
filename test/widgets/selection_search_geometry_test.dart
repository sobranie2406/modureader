import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:anx_reader/widgets/reading_page/selection_search_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  for (final spec in <(Size, double, double)>[
    (const Size(390, 844), 0, 1),
    (const Size(844, 390), 260, 1),
    (const Size(320, 568), 350, 2),
  ]) {
    testWidgets('search toolbar fits keyboard ${spec.$2}, scale ${spec.$3}',
        (tester) async {
      tester.view.physicalSize = spec.$1;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: spec.$2);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                viewInsets: EdgeInsets.only(bottom: spec.$2),
                textScaler: TextScaler.linear(spec.$3)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showSelectionSearchBrowserForTest(context),
                    child: const Text('Open')))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
          MediaQuery.of(tester.element(find.byType(ReaderPopup)))
              .viewInsets
              .bottom,
          spec.$2);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(const ValueKey('results'))).height,
          greaterThan(30));
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectionSearchBrowser), findsNothing);
    });
  }
}

Future<void> showSelectionSearchBrowserForTest(BuildContext context) =>
    showReaderPopup(context,
        enableDrag: false,
        builder: (_) => SelectionSearchBrowser(
            text: '测试',
            pageBuilder: (_, __) => ListView(
                key: const ValueKey('results'),
                children: List.generate(40, (i) => Text('结果$i')))));
