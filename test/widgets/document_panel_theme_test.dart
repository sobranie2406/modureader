import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/pdf_reading_view.dart';
import 'package:anx_reader/utils/color_scheme.dart';
import 'package:anx_reader/widgets/reading_page/document_panel_widgets.dart';
import 'package:anx_reader/widgets/reading_page/pdf_reading_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final brightness in Brightness.values) {
    for (final seed in [Colors.blue, Colors.green]) {
      testWidgets(
          'document menu follows app color and e-ink toggle $brightness $seed',
          (tester) async {
        await Prefs().saveThemeModeToPrefs(brightness.name);
        await Prefs().saveThemeToPrefs(seed.toARGB32());
        late ThemeData applicationTheme;
        await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
          return ListenableBuilder(
              listenable: Prefs(),
              builder: (context, child) {
                applicationTheme = colorSchema(Prefs(), context, brightness);
                return Theme(
                    data: applicationTheme,
                    child: Scaffold(
                        body: DocumentPanelTheme(
                            child: SingleChildScrollView(
                                child: PdfReadingControls(
                                    initial: const PdfReadingView(),
                                    save: (_) async {},
                                    pan: (_, __) async {})))));
              });
        })));
        await tester.pumpAndSettle();
        void verifyInherited() {
          final theme =
              Theme.of(tester.element(find.byType(PdfReadingControls)));
          expect(theme.colorScheme, applicationTheme.colorScheme);
          expect(theme.sliderTheme, applicationTheme.sliderTheme);
          final chip = tester.widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Single page'));
          expect(chip.selectedColor, applicationTheme.colorScheme.primary);
          expect((chip.label as Text).style!.color,
              applicationTheme.colorScheme.onPrimary);
          final material = tester.widget<Material>(find
              .descendant(
                  of: find.byType(DocumentPanelTheme),
                  matching: find.byType(Material))
              .first);
          expect(material.color, applicationTheme.colorScheme.surface);
        }

        verifyInherited();
        final normal = applicationTheme.colorScheme;
        expect(normal.primary, isNot(Colors.black));
        expect(normal.brightness, brightness);

        Prefs().eInkMode = true;
        await tester.pumpAndSettle();
        verifyInherited();
        expect(applicationTheme.colorScheme.primary, Colors.black);
        expect(applicationTheme.colorScheme.surface, Colors.white);

        Prefs().eInkMode = false;
        await tester.pumpAndSettle();
        verifyInherited();
        expect(applicationTheme.colorScheme, normal);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
