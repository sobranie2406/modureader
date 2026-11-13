import 'dart:async';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:modu_reader/service/ocr/document_text_geometry.dart';
import 'package:modu_reader/widgets/reading_page/document_original_note.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pdf_region_preview_test.dart' as fixture;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  final page = DocumentReflowPage(
      page: 3,
      ocr: true,
      rawText: '朱熹',
      rawRegions: const [
        DocumentTextRegion(0, 2, DocumentImageRect(.2, .3, .4, .05))
      ]);
  Map<String, dynamic> image() =>
      {'page': 3, 'width': 1, 'height': 1, 'dataUrl': fixture.pixel};

  for (final size in [const Size(360, 640), const Size(1024, 768)]) {
    testWidgets('original image is read-only and rectangles scale with $size',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var calls = 0, cancels = 0;
      final anchor = page.anchor(0, 2);
      final saved = anchor.encode();
      await tester.pumpWidget(MaterialApp(
          home: DocumentOriginalNote(
        anchor: anchor,
        render: (r) async {
          calls++;
          expect(r['page'], 3);
          expect(r['region'], {'x': 0, 'y': 0, 'width': 1, 'height': 1});
          expect(r['rotation'], 0);
          expect(r['hideWatermarks'], false);
          return image();
        },
        cancelRender: () => cancels++,
      )));
      await tester.pumpAndSettle();
      final overlay = find.byKey(const ValueKey('original-note-regions'));
      final painter = tester.widget<CustomPaint>(overlay).painter!
          as DocumentOriginalNotePainter;
      expect(painter.rects.single.toJson(), [.2, .3, .4, .05]);
      expect(tester.getSize(overlay), tester.getSize(find.byType(Image)));
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(calls, 1);
      expect(anchor.encode(), saved);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(cancels, 1);
    });
  }
  testWidgets(
      'legacy notes show only their source page and never invent geometry',
      (tester) async {
    final anchor =
        DocumentReflowPage(page: 3, ocr: true, rawText: '旧字').anchor(0, 2);
    await tester.pumpWidget(MaterialApp(
        home: DocumentOriginalNote(
      anchor: anchor,
      render: (_) async => image(),
      cancelRender: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('This note has no reliable image position'),
        findsNothing);
    final painter = tester
        .widget<CustomPaint>(
            find.byKey(const ValueKey('original-note-regions')))
        .painter! as DocumentOriginalNotePainter;
    expect(painter.rects, isEmpty);
  });
  testWidgets(
      'invalid page response is retryable and late result after close is ignored',
      (tester) async {
    var calls = 0;
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(MaterialApp(
        home: DocumentOriginalNote(
      anchor: page.anchor(0, 2),
      render: (_) async =>
          ++calls == 1 ? {...image(), 'page': 4} : pending.future,
      cancelRender: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('Retry'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    await tester.pump();
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
    pending.complete(image());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
