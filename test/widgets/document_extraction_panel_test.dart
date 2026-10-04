import 'dart:async';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anx_reader/service/ocr/ocr_model_store.dart';
import 'package:anx_reader/widgets/reading_page/document_extraction_panel.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'pdf_region_preview_test.dart' as fixture;

class FakeStore extends OcrModelStore {
  bool ready = false;
  int downloads = 0;
  @override
  Future<bool> available() async => ready;
  @override
  Future<void> download(
      CancelToken token, void Function(int, int) progress) async {
    downloads++;
    ready = true;
    progress(1, 1);
  }
}

Future<void> open(WidgetTester tester,
    {DocumentRequest? extract,
    FakeStore? store,
    DocumentOcr? ocr,
    bool forceOcr = false,
    ValueChanged<String?>? result}) async {
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () async {
                    final value = await showDialog<String>(
                        context: context,
                        builder: (_) => DocumentExtractionPanel(
                            forceOcr: forceOcr,
                            info: (page) async => {
                                  'page': page ?? 0,
                                  'total': 3,
                                  'width': 600,
                                  'height': 800
                                },
                            render: (_) async => {'dataUrl': fixture.pixel},
                            cancelRender: () {},
                            extractText: extract ??
                                (_) async =>
                                    {'text': 'First line\nSecond line'},
                            modelStore: store ?? FakeStore(),
                            recognize: ocr));
                    result?.call(value);
                  },
                  child: const Text('Open'))))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  testWidgets(
      'explicit OCR extraction preview bypasses text layer and never sends',
      (tester) async {
    final store = FakeStore()..ready = true;
    var reads = 0, runs = 0;
    String? draft;
    await open(tester,
        store: store,
        forceOcr: true,
        result: (v) => draft = v,
        extract: (_) async {
          reads++;
          return {'text': 'Hidden text'};
        },
        ocr: (_, c, p) async {
          runs++;
          return 'Visible OCR text';
        });
    expect(runs, 0);
    await tap(tester, 'Preview extracted text');
    expect(reads, 0);
    expect(runs, 1);
    expect(draft, isNull);
    expect(find.text('Visible OCR text'), findsOneWidget);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(runs, 1, reason: 'Changing extraction page must not start OCR');
    await tap(tester, 'Preview extracted text');
    expect(runs, 2);
    expect(draft, isNull);
  });
  testWidgets('region handles adjust selection without changing book state',
      (tester) async {
    await open(tester);
    final before = tester
        .widget<DocumentRegionSelector>(find.byType(DocumentRegionSelector))
        .region;
    final selector = find.byType(DocumentRegionSelector);
    final box = tester.getRect(selector);
    final handle = find
        .descendant(of: selector, matching: find.byType(GestureDetector))
        .at(1);
    await tester.drag(handle, Offset(box.width * .08, box.height * .06));
    await tester.pumpAndSettle();
    final after = tester.widget<DocumentRegionSelector>(selector).region;
    expect(after.left, greaterThan(before.left));
    expect(after.top, greaterThan(before.top));
    expect(after.right, before.right);
    expect(after.bottom, before.bottom);
  });
  testWidgets('embedded text returns a draft without model download or OCR',
      (tester) async {
    final store = FakeStore();
    String? draft;
    Map<String, dynamic>? request;
    await open(tester,
        store: store,
        result: (v) => draft = v,
        extract: (r) async {
          request = r;
          return {'text': 'Selected text'};
        });
    expect(store.downloads, 0);
    await tap(tester, 'Extract to AI draft');
    expect(draft, 'Selected text');
    expect(store.downloads, 0);
    expect(request!['region']['width'], .8);
  });
  testWidgets('scanned page requires explicit download and explicit retry',
      (tester) async {
    final store = FakeStore();
    var runs = 0;
    String? draft;
    await open(tester,
        store: store,
        extract: (_) async => {'text': ''},
        result: (v) => draft = v,
        ocr: (_, cancel, progress) async {
          runs++;
          return 'Recognized text';
        });
    await tap(tester, 'Whole page');
    await tap(tester, 'Extract to AI draft');
    expect(store.downloads, 0);
    expect(runs, 0);
    expect(draft, isNull);
    await tap(tester, 'Download / repair OCR model');
    expect(store.downloads, 1);
    expect(runs, 0);
    await tap(tester, 'Extract to AI draft');
    expect(runs, 1);
    expect(draft, 'Recognized text');
  });
  testWidgets(
      'extraction preview is local and preserves the raw extracted text',
      (tester) async {
    String? draft;
    await open(tester, result: (v) => draft = v);
    await tap(tester, 'Preview extracted text');
    expect(find.byType(SelectableText), findsOneWidget);
    expect(draft, isNull);
    await tester.tap(find.byTooltip('OCR text style'));
    await tester.pumpAndSettle();
    final slider =
        tester.widget<Slider>(find.byKey(const ValueKey('ocr-style-size')));
    slider.onChanged!(28);
    await tester.pumpAndSettle();
    await tap(tester, 'Apply');
    expect(
        tester
            .widget<SelectableText>(find.byType(SelectableText))
            .style!
            .fontSize,
        28);
    await tap(tester, 'Original');
    expect(find.byType(DocumentRegionSelector), findsOneWidget);
    await tap(tester, 'Extracted text');
    await tap(tester, 'Extract to AI draft');
    expect(draft, 'First line\nSecond line');
  });
  testWidgets('stop rejects stale OCR result, never fills AI', (tester) async {
    final store = FakeStore()..ready = true;
    final done = Completer<String>();
    String? draft;
    await open(tester,
        store: store,
        result: (v) => draft = v,
        extract: (_) async => {'text': ''},
        ocr: (_, c, p) => done.future);
    await tester.ensureVisible(find.text('Extract to AI draft'));
    await tester.tap(find.text('Extract to AI draft'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.ensureVisible(find.text('Stop'));
    await tester.tap(find.text('Stop'));
    done.complete('Discard this');
    await tester.pumpAndSettle();
    expect(draft, isNull);
    expect(find.byType(DocumentExtractionPanel), findsOneWidget);
  });
  for (final size in [
    const Size(320, 740),
    const Size(844, 390),
    const Size(1440, 900)
  ]) {
    testWidgets('responsive extraction panel at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester);
      expect(tester.takeException(), isNull);
      await tap(tester, 'Preview extracted text');
      expect(tester.takeException(), isNull);
    });
  }
}
