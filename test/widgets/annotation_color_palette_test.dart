import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/constants/note_annotations.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_notes_state.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:anx_reader/widgets/context_menu/annotation_color_palette.dart';
import 'package:anx_reader/widgets/context_menu/excerpt_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget body) => MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        ...GlobalMaterialLocalizations.delegates
      ],
      home: Scaffold(body: body),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test(
      'original colours remain unchanged and every new colour is included in note filters',
      () {
    expect(notesColors.take(5),
        ['66CCFF', 'FF0000', '00FF00', 'EB3BFF', 'FFD700']);
    expect(notesColors.length, 10);
    expect(notesColors.toSet().length, 10);
    final enabled = NoteFilterDefaults.initialTypeColorSelection();
    for (final color in notesColors) {
      expect(RegExp(r'^[0-9A-F]{6}$').hasMatch(color), isTrue);
      for (final type in notesType) {
        expect(enabled, contains('${type.type}#$color'));
      }
    }
  });

  test('new highlight colours remain visible on common pale backgrounds', () {
    for (final hex in notesColors.skip(5)) {
      final highlight = Color(int.parse('FF$hex', radix: 16));
      for (final background in const [
        Color(0xFFFBFBF3), // Default paper.
        Color(0xFFFFFFFF),
        Color(0xFFE1F8FC), // Pale blue.
        Color(0xFFBEECC8), // Pale green.
      ]) {
        // Match the reader's default 30% highlight opacity.
        final blended =
            Color.alphaBlend(highlight.withValues(alpha: 0.3), background);
        final contrast = (background.computeLuminance() + 0.05) /
            (blended.computeLuminance() + 0.05);
        expect(contrast, greaterThan(1.15), reason: '$hex on $background');
      }
    }
  });

  for (final axis in Axis.values) {
    testWidgets('all ten colours are tappable in a compact $axis palette',
        (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(app(Center(
          child: AnnotationColorPalette(
        axis: axis,
        selectedColor: '00897b',
        onSelected: (color) {
          selected.add(color);
          Prefs().annotationColor = color;
        },
      ))));
      await tester.pumpAndSettle();
      final palette = tester.getSize(find.byType(AnnotationColorPalette));
      expect(palette,
          axis == Axis.horizontal ? const Size(160, 64) : const Size(64, 160));
      expect(find.byIcon(Icons.check), findsOneWidget);
      final first = tester.getCenter(
          find.byKey(ValueKey('annotation-color-${notesColors.first}')));
      final sixth = tester.getCenter(
          find.byKey(ValueKey('annotation-color-${notesColors[5]}')));
      expect(
          axis == Axis.horizontal ? sixth.dy - first.dy : sixth.dx - first.dx,
          32);
      for (final color in notesColors) {
        await tester.tap(find.byKey(ValueKey('annotation-color-$color')));
        await tester.pump();
        expect(Prefs().annotationColor, color);
      }
      expect(selected, notesColors);
      await Prefs().initPrefs();
      expect(Prefs().annotationColor, notesColors.last);
      expect(tester.takeException(), isNull);
    });

    testWidgets('actual excerpt menu fits a narrow viewport in $axis reading',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(Padding(
        padding: const EdgeInsets.all(16),
        child: AxisFlex(axis: axis, children: [
          ExcerptMenu(
            annoCfi: 'test-cfi',
            annoContent: '用于测试的正文',
            onClose: () {},
            footnote: false,
            decoration: const BoxDecoration(),
            toggleTranslationMenu: () {},
            toggleReaderNoteMenu: ({bool? show}) {},
            openReaderNoteMenu: (_) async {},
            onNoteCreated: (_) {},
            axis: axis,
            reverse: false,
          )
        ]),
      )));
      await tester.pumpAndSettle();
      expect(find.byType(ExcerptMenu), findsOneWidget);
      expect(find.byType(AnnotationColorPalette), findsOneWidget);
      for (final color in notesColors) {
        final button = find.byKey(ValueKey('annotation-color-$color'));
        expect(button.hitTestable(), findsOneWidget);
        final rect = tester.getRect(button);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.bottom, lessThanOrEqualTo(640));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
