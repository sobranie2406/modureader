import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/page/settings_page/ai_reading_skills.dart';
import 'package:modu_reader/page/settings_page/selection_toolbar.dart';
import 'package:modu_reader/widgets/common/container/filled_container.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/reading_settings.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/other_settings.dart';
import 'package:modu_reader/widgets/reading_page/reader_menu_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final width in [390.0, 1200.0]) {
    Future<void> mount(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(body: page),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Rect surface(WidgetTester tester, Finder frame) => tester.getRect(
        find.descendant(of: frame, matching: find.byType(Material)).first);

    void aligned(Rect a, Rect b) {
      expect(b.left, closeTo(a.left, .01));
      expect(b.right, closeTo(a.right, .01));
      expect(b.height, greaterThan(0));
    }

    testWidgets('reading groups share edges across categories at $width',
        (tester) async {
      Rect? reference;
      for (final page in [
        const ReadingMoreSettings(readerMenu: true),
        const StyleSettings(readerMenu: true),
        const OtherSettings(readerMenu: true),
      ]) {
        await mount(tester, SingleChildScrollView(child: page));
        final groups = find.byType(ReaderMenuGroup);
        expect(groups, findsWidgets);
        for (var i = 0; i < groups.evaluate().length; i++) {
          final rect = surface(tester, groups.at(i));
          reference ??= rect;
          aligned(reference, rect);
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('toolbar cards align with settings group at $width',
        (tester) async {
      await mount(tester, const SelectionToolbarSettings());
      final header = surface(tester, find.byType(FilledContainer).first);
      final cards = find.byType(Card);
      expect(cards, findsWidgets);
      for (var i = 0; i < cards.evaluate().length; i++) {
        aligned(header, surface(tester, cards.at(i)));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('skill list aligns with header and footer at $width',
        (tester) async {
      await mount(tester, const AiReadingSkillsSettings());
      final header = surface(tester, find.byType(FilledContainer).first);
      final entry = find.byWidgetPredicate((w) =>
          w is Card && w.key.toString().contains('reading-skill-entry-'));
      expect(entry, findsWidgets);
      for (var i = 0; i < entry.evaluate().length; i++) {
        aligned(header, surface(tester, entry.at(i)));
      }
      final scroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text('功能提示词'), 500,
          scrollable: scroll, maxScrolls: 100);
      await tester.pumpAndSettle();
      aligned(header, surface(tester, find.byType(FilledContainer).last));
      expect(tester.takeException(), isNull);
    });
  }
}
