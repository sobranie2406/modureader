import 'dart:io';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:modu_reader/widgets/common/app_scroll_behavior.dart';
import 'package:modu_reader/widgets/reading_page/reader_popup.dart';
import 'package:modu_reader/widgets/reading_page/reader_settings_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1200, 900),
  ]) {
    for (final long in [false, true]) {
      testWidgets(
          'quick style fits content and keeps toolbar reachable: $size $long',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var taps = 0;
        const footerKey = ValueKey('footer');
        const lastKey = ValueKey('last');
        await tester.pumpWidget(MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ReaderQuickStylePanel(
                content: ReaderSettingsScrollView(
                  child: Column(children: [
                    SizedBox(height: long ? 1600 : 100),
                    SizedBox(
                      key: lastKey,
                      height: 48,
                      child: TextButton(
                          onPressed: () => taps++,
                          child: const Text('Background')),
                    ),
                  ]),
                ),
                toolbar: const SizedBox(key: footerKey, height: 48),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        final panel = tester.getRect(find.byType(ReaderQuickStylePanel));
        expect(panel.height, closeTo(long ? size.height * .8 : 196, .01));
        expect(tester.getRect(find.byKey(footerKey)).bottom, size.height);
        if (long) {
          final scroll = tester.widget<SingleChildScrollView>(
              find.byType(SingleChildScrollView));
          scroll.controller!
              .jumpTo(scroll.controller!.position.maxScrollExtent);
          await tester.pumpAndSettle();
        }
        expect(tester.getRect(find.byKey(lastKey)).bottom,
            closeTo(tester.getRect(find.byKey(footerKey)).top, .01));
        await tester.tap(find.text('Background'));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('reader only shows top toolbar in the unexpanded menu', () {
    final source = File('lib/page/reading_page.dart').readAsStringSync();
    expect(
        source,
        matches(
            r'if \(identical\(_currentPage, empty\)\)\s+HarmonyReaderToolbar\(\s+enabled: AnxPlatform\.isOhos,\s+child: LayoutBuilder\(\s+builder: \(context, constraints\) => AppBar\('));
    expect(source, contains('ReaderQuickStylePanel('));
    // Brightness/background must rebuild the outer toolbar visibility too.
    expect(source, isNot(contains('StatefulBuilder(')));
    expect(source, contains('_currentPage = empty;'));
  });
}
