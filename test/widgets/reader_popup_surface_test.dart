import 'dart:io';
import 'dart:ui' as ui;

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/utils/color_scheme.dart';
import 'package:anx_reader/widgets/reading_page/document_panel_widgets.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final eink in [false, true]) {
    for (final dark in [false, true]) {
      for (final kind in ['inline', 'modal', 'dialog']) {
        testWidgets(
            '$kind clips nested panel backgrounds dark=$dark eink=$eink',
            (tester) async {
          Prefs().eInkMode = eink;
          await Prefs().saveThemeModeToPrefs(dark ? 'dark' : 'light');
          const panel =
              DocumentPanelTheme(child: SizedBox(width: 400, height: 200));
          late ThemeData theme;
          const boundaryKey = ValueKey('popup-surface');
          await tester.pumpWidget(RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(home: Builder(builder: (context) {
                theme = colorSchema(Prefs(), context, Brightness.light);
                return Theme(
                  data: theme,
                  child: Builder(builder: (context) {
                    return Scaffold(
                      backgroundColor: Colors.blueGrey,
                      body: kind == 'inline'
                          ? Align(
                              alignment: Alignment.bottomCenter,
                              child: BottomSheet(
                                  onClosing: () {},
                                  enableDrag: false,
                                  builder: (_) => panel))
                          : TextButton(
                              onPressed: () {
                                if (kind == 'modal') {
                                  showReaderPopup(context,
                                      builder: (_) => panel);
                                } else {
                                  showDialog<void>(
                                      context: context,
                                      builder: (_) =>
                                          const Dialog(child: panel));
                                }
                              },
                              child: const Text('Open')),
                    );
                  }),
                );
              }))));
          if (kind != 'inline') {
            await tester.tap(find.text('Open'));
          }
          await tester.pumpAndSettle();
          final shell =
              kind == 'dialog' ? find.byType(Dialog) : find.byType(BottomSheet);
          final material = tester.widget<Material>(find
              .descendant(of: shell, matching: find.byType(Material))
              .first);
          expect(material.clipBehavior, Clip.antiAlias,
              reason: 'A rounded outline alone cannot clip a child Material.');
          final shape = material.shape! as RoundedRectangleBorder;
          expect(shape.borderRadius.resolve(TextDirection.ltr).topLeft.x,
              greaterThan(0));
          expect(material.color, theme.colorScheme.surface);
          expect(material.elevation, eink ? 0 : greaterThanOrEqualTo(4));
          if (!eink && !dark) {
            final rect = tester.getRect(find
                .descendant(of: shell, matching: find.byType(Material))
                .first);
            final boundary = tester
                .renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes =
                  (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
              int redAt(double x, double y) =>
                  bytes.getUint8((y.floor() * image.width + x.floor()) * 4);
              expect(redAt(rect.left + 1, rect.top + 1), lessThan(220),
                  reason: 'The outer corner must expose the backdrop, not a '
                      'square child background.');
              // The panel paints the theme surface; its exact colour now comes
              // from the active preset canvas.
              expect(redAt(rect.center.dx, rect.top + 30),
                  (theme.colorScheme.surface.r * 255).round());
              const preview = String.fromEnvironment('POPUP_PREVIEW');
              if (preview.isNotEmpty) {
                final png =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                await File('$preview-$kind.png')
                    .writeAsBytes(png!.buffer.asUint8List());
              }
              image.dispose();
            });
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
