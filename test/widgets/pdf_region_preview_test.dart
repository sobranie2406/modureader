import 'dart:async';
import 'package:anx_reader/widgets/reading_page/pdf_region_preview.dart';
import 'package:anx_reader/models/document_page_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const pixel =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==';
Map<String, dynamic> info(int? page) =>
    {'page': page ?? 2, 'total': 6, 'width': 600, 'height': 800};
Future<void> ready(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'failed next-page lookup retries the requested page instead of returning to old page',
      (tester) async {
    var fail = true;
    final lookedUp = <int?>[];
    await tester.pumpWidget(MaterialApp(
        home: PdfRegionPreview(
      info: (page) async {
        lookedUp.add(page);
        if (page == 3 && fail) throw StateError('parse');
        return info(page);
      },
      render: (_) async => {'dataUrl': pixel},
      cancelRender: () {},
      close: () {},
    )));
    await ready(tester);
    await tester.tap(find.byTooltip('Next original page'));
    await ready(tester);
    expect(
        find.text('Preview failed. The source is unchanged.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await ready(tester);
    expect(lookedUp, [null, 3, 3]);
    expect(find.text('4 / 6'), findsOneWidget);
  });
  testWidgets(
      'saved panels render in order; crossing boundaries retains original page indices',
      (tester) async {
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: PdfRegionPreview(
      initialLayout: const DocumentLayoutConfig(
          all: DocumentPageLayout(
              crop: Rect.fromLTWH(.1, .2, .8, .6),
              preset: 'horizontal2',
              order: 'row-rtl')),
      saveLayout: (_) async {},
      info: (page) async => info(page),
      render: (request) async {
        requests.add(request);
        return {'dataUrl': pixel};
      },
      cancelRender: () {},
      close: () {},
    )));
    await ready(tester);
    expect((requests.last['region'] as Map)['x'], closeTo(.5, 1e-9));
    expect(find.textContaining('Region 1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Next region'));
    await ready(tester);
    expect(requests.last['page'], 2);
    expect((requests.last['region'] as Map)['x'], closeTo(.1, 1e-9));
    await tester.tap(find.byTooltip('Next region'));
    await ready(tester);
    expect(requests.last['page'], 3);
    expect((requests.last['region'] as Map)['x'], closeTo(.5, 1e-9));
    await tester.tap(find.byTooltip('Previous region'));
    await ready(tester);
    expect(requests.last['page'], 2);
    expect(find.textContaining('Region 2 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Rotate right'));
    await ready(tester);
    expect((requests.last['region'] as Map)['x'], closeTo(.2, 1e-9));
    expect((requests.last['region'] as Map)['width'], closeTo(.6, 1e-9));
    await tester.tap(find.text('Compare original'));
    await ready(tester);
    expect((requests.last['region'] as Map)['width'], 1);
    await tester.tap(find.text('Apply saved layout'));
    await ready(tester);
    expect((requests.last['region'] as Map)['width'], closeTo(.6, 1e-9));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'editor confirmation applies saved layout; cancellation leaves it unchanged',
      (tester) async {
    final saved = <DocumentLayoutConfig>[];
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: PdfRegionPreview(
      saveLayout: (config) async {
        saved.add(config);
      },
      info: (page) async => info(page),
      render: (request) async {
        requests.add(request);
        return {'dataUrl': pixel};
      },
      cancelRender: () {},
      close: () {},
    )));
    await ready(tester);
    await tester.tap(find.byTooltip('Crop and panels'));
    await ready(tester);
    tester
        .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('layout-grid')))
        .onChanged!('four');
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await ready(tester);
    expect(saved, isEmpty);
    expect((requests.last['region'] as Map)['width'], 1);
    await tester.tap(find.byTooltip('Crop and panels'));
    await ready(tester);
    tester
        .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('layout-grid')))
        .onChanged!('four');
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await ready(tester);
    expect(saved.length, 1);
    expect(saved.single.forPage(2).preset, 'four');
    expect((requests.last['region'] as Map)['width'], .5);
    expect(find.textContaining('Region 1 / 4'), findsOneWidget);
  });
  testWidgets(
      'opens current original page; zoom is 100-1500 and pan stays within page',
      (tester) async {
    final requests = <Map<String, dynamic>>[];
    var closed = 0;
    await tester.pumpWidget(MaterialApp(
        home: PdfRegionPreview(
      info: (page) async => info(page),
      render: (request) async {
        requests.add(request);
        return {'dataUrl': pixel};
      },
      cancelRender: () {},
      close: () => closed++,
    )));
    await ready(tester);
    expect(find.text('3 / 6'), findsOneWidget);
    expect(requests.last['page'], 2);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 1);
    expect(slider.max, 15);
    slider.onChanged!(15);
    await ready(tester);
    expect(find.text('1500%'), findsOneWidget);
    expect((requests.last['region'] as Map)['width'], closeTo(1 / 15, 1e-9));
    await tester.drag(find.byKey(const ValueKey('pdf-region-viewport')),
        const Offset(10000, 10000));
    await ready(tester);
    final region = requests.last['region'] as Map;
    expect(region['x'], greaterThanOrEqualTo(0));
    expect(region['y'], greaterThanOrEqualTo(0));
    await tester.pumpWidget(const SizedBox());
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'rotate/reset and next page request original indices, with no saved reading position',
      (tester) async {
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: PdfRegionPreview(
      info: (page) async => info(page),
      render: (request) async {
        requests.add(request);
        return {'dataUrl': pixel};
      },
      cancelRender: () {},
      close: () {},
    )));
    await ready(tester);
    await tester.tap(find.byTooltip('Rotate right'));
    await ready(tester);
    expect(requests.last['rotation'], 90);
    await tester.tap(find.byTooltip('Reset view'));
    await ready(tester);
    expect(requests.last['rotation'], 0);
    expect((requests.last['region'] as Map)['width'], 1);
    await tester.tap(find.byTooltip('Next original page'));
    await ready(tester);
    expect(find.text('4 / 6'), findsOneWidget);
    expect(requests.last['page'], 3);
  });

  testWidgets('failed render can retry and closing a pending reply is safe',
      (tester) async {
    var fails = true, cancelled = 0;
    final waiting = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(MaterialApp(
        home: PdfRegionPreview(
      info: (page) async => info(page),
      render: (_) =>
          fails ? Future.error(StateError('failed')) : waiting.future,
      cancelRender: () => cancelled++,
      close: () => cancelled++,
    )));
    await ready(tester);
    expect(
        find.text('Preview failed. The source is unchanged.'), findsOneWidget);
    fails = false;
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpWidget(const SizedBox());
    waiting.complete({'dataUrl': pixel});
    await tester.pump();
    expect(cancelled, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale response cannot replace a newer zoom; mobile layout fits',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = Completer<Map<String, dynamic>>();
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: PdfRegionPreview(
      info: (page) async => info(page),
      render: (_) {
        calls++;
        return calls == 1 ? first.future : Future.value({'dataUrl': pixel});
      },
      cancelRender: () {},
      close: () {},
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    tester.widget<Slider>(find.byType(Slider)).onChanged!(3);
    await ready(tester);
    first.completeError(StateError('obsolete'));
    await tester.pump();
    expect(find.text('300%'), findsOneWidget);
    expect(find.text('Preview failed. The source is unchanged.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
