import 'package:modu_reader/widgets/reading_page/reader_menu_group.dart';
import 'package:modu_reader/widgets/reading_page/reader_settings_scroll_view.dart';
import 'package:modu_reader/widgets/reading_page/widget_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 640), const Size(1200, 800)]) {
      testWidgets(
          'outlined menu preserves typography, scroll and actions $brightness $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var taps = 0;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness, fontFamily: 'Roboto'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: ReaderSettingsScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  widgetTitle('Title', null),
                  const ReaderMenuGroup(
                    child: ListTile(
                        title: Text('Control'), subtitle: Text('Help')),
                  ),
                  const SizedBox(height: 1000),
                  ReaderMenuGroup(
                    child: ListTile(
                      title: const Text('Last action'),
                      onTap: () => taps++,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
        expect(tester.widget<Text>(find.text('Title')).style,
            readerMenuTitleStyle);
        final context = tester.element(find.text('Help'));
        final material = tester.widget<Material>(find
            .descendant(
                of: find.byType(ReaderMenuGroup).first,
                matching: find.byType(Material))
            .first);
        final border = (material.shape! as OutlinedBorder).side;
        expect(border.color, Theme.of(context).colorScheme.outlineVariant);
        expect(border.width, greaterThan(0));
        expect(DefaultTextStyle.of(context).style.fontFamily, 'Roboto');
        expect(ListTileTheme.of(context).subtitleTextStyle!.fontSize, 12);
        expect(MediaQuery.textScalerOf(context).scale(12), closeTo(19.2, 1e-9));
        await tester.ensureVisible(find.text('Last action'));
        await tester.tap(find.text('Last action'));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
