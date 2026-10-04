import 'dart:async';
import 'package:anx_reader/models/document_page_layout.dart';
import 'package:anx_reader/widgets/reading_page/document_layout_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'pdf_region_preview_test.dart' as fixture;

Future<void> openEditor(WidgetTester tester,
    {DocumentLayoutConfig initial = const DocumentLayoutConfig(),
    int total = 6,
    Future<void> Function(DocumentLayoutConfig)? save,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
        render}) async {
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => showDialog<DocumentLayoutConfig>(
                      context: context,
                      builder: (_) => DocumentLayoutEditor(
                          initial: initial,
                          page: 0,
                          total: total,
                          info: (page) async =>
                              {...fixture.info(page), 'total': total},
                          render:
                              render ?? (_) async => {'dataUrl': fixture.pixel},
                          cancelRender: () {},
                          save: save ?? (_) async {})),
                  child: const Text('Open'))))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

DocumentPageLayout draft(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<DocumentCropPainter>()
    .single
    .layout;
void choose(WidgetTester tester, String key, String value) => tester
    .widget<DropdownButton<String>>(find.byKey(ValueKey(key)))
    .onChanged!(value);

void main() {
  testWidgets(
      'auto crop is a reviewable draft; margin and presets do not save until confirm',
      (tester) async {
    final requests = <Map<String, dynamic>>[], saved = <DocumentLayoutConfig>[];
    await openEditor(tester,
        save: (value) async => saved.add(value),
        render: (request) async {
          requests.add(request);
          return {
            'dataUrl': fixture.pixel,
            if (request['analyzeCrop'] == true)
              'cropDetection': {
                'detected': true,
                'crop': {'x': .1, 'y': .2, 'width': .8, 'height': .6}
              }
          };
        });
    tester
        .widget<Slider>(find.byKey(const ValueKey('crop-margin')))
        .onChanged!(5);
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('auto-crop')));
    await tester.tap(find.byKey(const ValueKey('auto-crop')));
    await tester.pumpAndSettle();
    expect(requests.last['margin'], .05);
    expect(draft(tester).crop, const Rect.fromLTWH(.1, .2, .8, .6));
    expect(saved, isEmpty);
    tester
        .widget<ActionChip>(
            find.widgetWithText(ActionChip, 'Manga: right-to-left spread'))
        .onPressed!();
    await tester.pump();
    expect(draft(tester).order, 'row-rtl');
    expect(draft(tester).regions.length, 2);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(saved.single.forPage(0).crop, const Rect.fromLTWH(.1, .2, .8, .6));
    expect(saved.single.all!.autoCrop, true);
    expect(saved.single.forPage(5).autoCrop, true);
    expect(saved.single.forPage(5).autoMargin, .05);
  });
  testWidgets(
      'reopening auto layout detects current page; drag switches to manual',
      (tester) async {
    final saved = <DocumentLayoutConfig>[];
    await openEditor(tester,
        initial: const DocumentLayoutConfig(
            all: DocumentPageLayout(autoCrop: true, autoMargin: .07)),
        save: (value) async => saved.add(value),
        render: (request) async => {
              'dataUrl': fixture.pixel,
              if (request['analyzeCrop'] == true)
                'cropDetection': {
                  'detected': true,
                  'crop': {'x': .1, 'y': .2, 'width': .8, 'height': .6}
                }
            });
    expect(draft(tester).autoCrop, true);
    expect(draft(tester).crop, const Rect.fromLTWH(.1, .2, .8, .6));
    expect(
        tester.widget<Slider>(find.byKey(const ValueKey('crop-margin'))).value,
        closeTo(7, 1e-9));
    await tester.drag(
        find.byKey(const ValueKey('crop-tl')), const Offset(15, 15));
    await tester.pumpAndSettle();
    expect(draft(tester).autoCrop, false);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(saved.single.forPage(0).autoCrop, false);
    expect(saved.single.forPage(1).autoCrop, true);
  });
  testWidgets('switching scope during automatic detection discards late crop',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    await openEditor(tester,
        render: (request) => request['analyzeCrop'] == true
            ? pending.future
            : Future.value({'dataUrl': fixture.pixel}));
    await tester.ensureVisible(find.byKey(const ValueKey('auto-crop')));
    await tester.tap(find.byKey(const ValueKey('auto-crop')));
    await tester.pump();
    tester
        .widget<DropdownButton<DocumentLayoutScope>>(
            find.byKey(const ValueKey('layout-scope')))
        .onChanged!(DocumentLayoutScope.all);
    await tester.pumpAndSettle();
    pending.complete({
      'dataUrl': fixture.pixel,
      'cropDetection': {
        'detected': true,
        'crop': {'x': .1, 'y': .1, 'width': .8, 'height': .8}
      }
    });
    await tester.pumpAndSettle();
    expect(draft(tester).crop, const Rect.fromLTWH(0, 0, 1, 1));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  testWidgets(
      'all four edge handles and interior movement respond and stay within the page',
      (tester) async {
    await openEditor(tester);
    for (final entry in {
      'tl': const Offset(25, 25),
      'tr': const Offset(-25, 25),
      'bl': const Offset(25, -25),
      'br': const Offset(-25, -25)
    }.entries) {
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(ValueKey('crop-${entry.key}')), entry.value);
      await tester.pumpAndSettle();
      expect(draft(tester).crop.width, lessThan(1));
      expect(draft(tester).crop.height, lessThan(1));
    }
    await tester.drag(
        find.byKey(const ValueKey('crop-move')), const Offset(1000, 1000));
    await tester.pumpAndSettle();
    expect(draft(tester).crop.right, lessThanOrEqualTo(1 + 1e-9));
    expect(draft(tester).crop.bottom, lessThanOrEqualTo(1 + 1e-9));
  });
  testWidgets('closing while switching parity discards the late page response',
      (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    var saves = 0;
    await openEditor(tester,
        save: (_) async {
          saves++;
        },
        render: (request) => request['page'] == 1
            ? pending.future
            : Future.value({'dataUrl': fixture.pixel}));
    await tester.tap(find.text('Odd / even'));
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButton<DocumentLayoutScope>>(
            find.byKey(const ValueKey('layout-scope')))
        .onChanged!(DocumentLayoutScope.even);
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    pending.completeError(StateError('late'));
    await tester.pump();
    expect(saves, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('corner drag and grid choices remain draft; cancel never saves',
      (tester) async {
    var writes = 0;
    await openEditor(tester, save: (_) async {
      writes++;
    });
    await tester.drag(
        find.byKey(const ValueKey('crop-tl')), const Offset(30, 30));
    await tester.pumpAndSettle();
    expect(draft(tester).crop.left, greaterThan(0));
    choose(tester, 'layout-grid', 'four');
    await tester.pumpAndSettle();
    expect(draft(tester).regions.length, 4);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Open'), findsOneWidget);
  });
  testWidgets(
      'explicit confirmation saves normalized crop and order for original page',
      (tester) async {
    DocumentLayoutConfig? saved;
    await openEditor(tester, save: (value) async {
      saved = value;
    });
    await tester.drag(
        find.byKey(const ValueKey('crop-br')), const Offset(-25, -25));
    choose(tester, 'layout-grid', 'horizontal2');
    choose(tester, 'layout-order', 'row-rtl');
    await tester.pumpAndSettle();
    final expected = draft(tester);
    expect(expected.crop.width, lessThan(1));
    expect(expected.crop.height, lessThan(1));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(saved!.forPage(0).toJson(), expected.toJson());
    expect(saved!.forPage(1).preset, 'single');
    expect(find.text('Open'), findsOneWidget);
  });
  testWidgets(
      'odd/even drafts are independent, both adjusted scopes save together',
      (tester) async {
    DocumentLayoutConfig? saved;
    final pages = <int>[];
    await openEditor(tester, save: (value) async {
      saved = value;
    }, render: (request) async {
      pages.add(request['page'] as int);
      return {'dataUrl': fixture.pixel};
    });
    await tester.tap(find.text('Odd / even'));
    await tester.pumpAndSettle();
    choose(tester, 'layout-grid', 'horizontal2');
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButton<DocumentLayoutScope>>(
            find.byKey(const ValueKey('layout-scope')))
        .onChanged!(DocumentLayoutScope.even);
    await tester.pumpAndSettle();
    expect(draft(tester).preset, 'single');
    expect(pages.last, 1);
    choose(tester, 'layout-grid', 'four');
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButton<DocumentLayoutScope>>(
            find.byKey(const ValueKey('layout-scope')))
        .onChanged!(DocumentLayoutScope.odd);
    await tester.pumpAndSettle();
    expect(draft(tester).preset, 'horizontal2');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(saved!.forPage(0).preset, 'horizontal2');
    expect(saved!.forPage(1).preset, 'four');
    expect(saved!.forPage(8).preset, 'horizontal2');
  });
  testWidgets(
      'reset returns to full page; failed save leaves draft editable for retry',
      (tester) async {
    var attempts = 0;
    await openEditor(tester,
        initial: const DocumentLayoutConfig(
            all: DocumentPageLayout(
                crop: Rect.fromLTWH(.1, .1, .8, .8),
                preset: 'four')), save: (_) async {
      if (++attempts == 1) throw StateError('disk');
    });
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(draft(tester).crop, const Rect.fromLTWH(0, 0, 1, 1));
    expect(draft(tester).preset, 'single');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(
        find.text('Save failed. Not applied. Please retry.'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('Open'), findsOneWidget);
  });
  testWidgets(
      'small portrait and landscape layouts have reachable handles and no overflow',
      (tester) async {
    for (final size in [const Size(360, 640), const Size(740, 360)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await openEditor(tester, total: 1);
      await tester.tap(find.text('Odd / even'));
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButton<DocumentLayoutScope>>(
          find.byKey(const ValueKey('layout-scope')));
      expect(dropdown.items!.last.enabled, false);
      expect(find.byKey(const ValueKey('crop-tl')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('saving disables cancellation until persistence completes',
      (tester) async {
    final save = Completer<void>();
    await openEditor(tester, save: (_) => save.future);
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull);
    expect(tester.widget<PopScope>(find.byType(PopScope).last).canPop, false);
    save.complete();
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });
}
