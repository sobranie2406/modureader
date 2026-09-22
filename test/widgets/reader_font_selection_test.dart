import 'dart:io';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory temporary;
  late String oldPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    oldPath = documentPath;
    temporary = await Directory.systemTemp.createTemp('modu-font-menu-');
    documentPath = temporary.path;
    await getFontDir().create();
  });
  tearDown(() async {
    documentPath = oldPath;
    await temporary.delete(recursive: true);
  });
  Future<void> show(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: SizedBox(
              height: 420,
              child: StyleWidget(
                themes: const [],
                epubPlayerKey: GlobalKey<EpubPlayerState>(),
                setCurrentPage: (_) {},
                hideAppBarAndBottomBar: (_) {},
              ))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('English selection changes only English and can return to body',
      (tester) async {
    await show(tester);
    final body = Prefs().font.toJson();
    var menu = tester.widget<DropdownMenu<FontModel>>(
        find.byKey(const ValueKey('english-font-follow')));
    menu.onSelected!(
        FontModel(label: 'System', name: 'system', path: 'system'));
    await tester.pumpAndSettle();
    expect(Prefs().englishFont!.name, 'system');
    expect(Prefs().font.toJson(), body);
    menu = tester.widget<DropdownMenu<FontModel>>(
        find.byKey(const ValueKey('english-font-system')));
    menu.onSelected!(menu.dropdownMenuEntries.first.value);
    await tester.pumpAndSettle();
    expect(Prefs().englishFont, isNull);
    expect(Prefs().font.toJson(), body);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'font controls remain reachable on narrow screens with large text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(tester, scale: 1.5);
    await tester
        .ensureVisible(find.byKey(const ValueKey('english-font-follow')));
    expect(tester.takeException(), isNull);
  });
}
