import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:modu_reader/widgets/common/app_scroll_behavior.dart';
import 'package:modu_reader/widgets/reading_page/document_panel_widgets.dart';
import 'package:modu_reader/widgets/reading_page/reader_popup.dart';
import 'package:modu_reader/widgets/reading_page/reader_settings_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:modu_reader/widgets/reading_page/reader_menu_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('three menu levels retain symmetric gutters at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Widget items(BuildContext context, int level) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReaderMenuGroup(
                  key: ValueKey('content-$level'),
                  child: const SizedBox(height: 48)),
              if (level < 3)
                TextButton(
                    child: Text('Open ${level + 1}'),
                    onPressed: () {
                      if (level == 1) {
                        showReaderPopup(context,
                            builder: (context) => ListView(
                                  children: [items(context, 2)],
                                ));
                      } else {
                        showDialog<void>(
                            context: context,
                            builder: (context) => Dialog(
                                  child: SizedBox(
                                      width: 500,
                                      height: 400,
                                      child: DocumentPanelTheme(
                                          child: ListView(
                                              children: [items(context, 3)]))),
                                ));
                      }
                    }),
              const SizedBox(height: 1200),
            ],
          );
      await tester.pumpWidget(MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        home: Scaffold(
            body: Builder(
                builder: (context) => Align(
                      alignment: Alignment.bottomCenter,
                      child: ReaderQuickStylePanel(
                        content:
                            ReaderSettingsScrollView(child: items(context, 1)),
                        toolbar: const SizedBox(height: 48),
                      ),
                    ))),
      ));
      await tester.pumpAndSettle();
      for (var level = 1; level <= 3; level++) {
        final child = find.byKey(ValueKey('content-$level'));
        final bounds = tester.getRect(child);
        final viewport = tester.getRect(find
            .ancestor(of: child, matching: find.byType(RawScrollbar))
            .first);
        expect(bounds.left - viewport.left,
            closeTo(viewport.right - bounds.right, .01));
        expect(viewport.right - bounds.right, greaterThanOrEqualTo(14));
        expect(tester.takeException(), isNull);
        if (level < 3) {
          await tester.tap(find.text('Open ${level + 1}'));
          await tester.pumpAndSettle();
        }
      }
    });
  }
}
