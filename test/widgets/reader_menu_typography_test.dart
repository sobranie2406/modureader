import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:modu_reader/widgets/reading_page/widget_title.dart';
import 'package:modu_reader/widgets/reading_page/reader_settings_scroll_view.dart';
import 'package:modu_reader/widgets/reading_page/document_panel_widgets.dart';
import 'package:modu_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  for (final panel in ['ebook', 'document', 'quick']) {
    testWidgets(
        '$panel descriptions are smaller without changing headings or text scaling',
        (tester) async {
      late TextStyle description;
      late TextStyle originalTitle;
      final content = Builder(builder: (context) {
        description = ListTileTheme.of(context).subtitleTextStyle!;
        originalTitle = Theme.of(context).textTheme.titleMedium!;
        expect(MediaQuery.textScalerOf(context).scale(12), 18);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          widgetTitle('Title', null),
          const ListTile(title: Text('Action'), subtitle: Text('Help')),
        ]);
      });
      final theme = ThemeData(fontFamily: 'Roboto');
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(800, 600), textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
              body: switch (panel) {
            'ebook' => ReaderSettingsScrollView(child: content),
            'document' => DocumentPanelTheme(child: content),
            _ => ReaderQuickStylePanel(
                content: content, toolbar: const SizedBox()),
          }),
        ),
      ));
      expect(description.fontSize, 12);
      expect(
          originalTitle,
          Theme.of(tester.element(find.byType(Scaffold)))
              .textTheme
              .titleMedium);
      expect(description.fontFamily, 'Roboto');
      expect(
          tester.widget<Text>(find.text('Title')).style, readerMenuTitleStyle);
      expect(tester.takeException(), isNull);
    });
  }
  for (final brightness in Brightness.values) {
    testWidgets('submenu changes only title font: $brightness', (tester) async {
      late TextStyle base;
      late TextStyle heading;
      late TextStyle body;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness, fontFamily: 'Roboto'),
        home: Builder(builder: (context) {
          base = Theme.of(context).textTheme.titleLarge!;
          body = Theme.of(context).textTheme.bodyMedium!;
          heading = readerSubmenuTitleStyle(context)!;
          return Scaffold(
              body: Column(children: [
            widgetTitle('Existing title', null),
            Text('Submenu', style: heading),
            const Text('Option description'),
          ]));
        }),
      ));
      expect(heading, base.copyWith(fontFamily: 'SourceHanSerif'));
      expect(body.fontFamily, 'Roboto');
      final oldTitle = tester.widget<Text>(find.text('Existing title'));
      expect(
          oldTitle.style,
          const TextStyle(
            fontSize: 28,
            fontFamily: 'SourceHanSerif',
            fontWeight: FontWeight.bold,
          ));
      expect(tester.takeException(), isNull);
    });
  }
}
