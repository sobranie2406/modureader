import 'dart:async';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/service/ocr/document_reflow_store.dart';
import 'package:anx_reader/service/ocr/document_text_style.dart';
import 'package:anx_reader/service/ocr/ocr_model_store.dart';
import 'package:anx_reader/widgets/reading_page/document_reflow_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'pdf_region_preview_test.dart' as fixture;

class MemoryStore extends DocumentReflowStore {
  MemoryStore() : super('test');
  final latest = <String, DocumentReflowPage>{},
      revisions = <String, DocumentReflowPage>{};
  @override
  Future<DocumentReflowPage?> read(int page, String profile) async =>
      latest['$page:$profile'];
  @override
  Future<DocumentReflowPage?> readAnchor(DocumentReflowAnchor anchor) async =>
      revisions[anchor.revision];
  @override
  Future<void> save(DocumentReflowPage value, String profile) async {
    latest['${value.page}:$profile'] = value;
    revisions[value.revision] = value;
  }
}

class Model extends OcrModelStore {
  bool ready = true;
  @override
  Future<bool> available() async => ready;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryStore store;
  late Model model;
  late List<BookNote> notes;
  late List<int> pages;
  late GlobalKey<DocumentReflowReaderState> key;
  const wordChannel = MethodChannel('com.modu.reader/word_selection');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(wordChannel, null);
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    store = MemoryStore();
    model = Model();
    notes = [];
    pages = [];
    key = GlobalKey<DocumentReflowReaderState>();
  });
  Future<void> open(WidgetTester tester,
      {bool ocr = false,
      DocumentReflowAnchor? anchor,
      Future<String> Function(int)? extract,
      Future<String> Function()? recognize,
      ReflowSelection? selection,
      Future<void> Function(int)? navigate,
      VoidCallback? close,
      Future<Map<String, dynamic>> Function(int?)? info,
      void Function(Map<String, dynamic>)? extractionRequest,
      void Function(Map<String, dynamic>)? renderRequest,
      VoidCallback? clearMenu,
      double textScale = 1,
      bool settle = true}) async {
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: Scaffold(
            body: DocumentReflowReader(
          key: key,
          store: store,
          modelStore: model,
          forceOcr: ocr,
          anchor: anchor,
          info: info ??
              (page) async =>
                  {'page': page ?? 0, 'total': 3, 'width': 600, 'height': 800},
          extractText: (r) async {
            extractionRequest?.call(r);
            return {
              'text': await (extract?.call(r['page'] as int) ??
                  Future.value('第${r['page']}页正文。\n\n下一段内容。'))
            };
          },
          render: (r) async {
            renderRequest?.call(r);
            return {'dataUrl': fixture.pixel};
          },
          cancelRender: () {},
          recognize: (_, cancel, progress) async =>
              await (recognize?.call() ?? Future.value('识别文字。\n\n另一段。')),
          onClose: close ?? () {},
          onPageChanged: navigate ?? (page) async => pages.add(page),
          clearMenu: clearMenu ?? () {},
          loadNotes: () async => notes,
          initialStyle: const DocumentTextStyle(),
          saveStyle: (_) async {},
          onSelection: selection ?? (_, text, context, rect, ids) async {},
        ))));
    if (settle) await tester.pumpAndSettle();
  }

  String text(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('reflow-text')))
      .controller!
      .text;

  Offset textPoint(WidgetTester tester, int offset) {
    final render = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
    return render.localToGlobal(caret.center + const Offset(2, 0));
  }

  testWidgets('macOS mouse drag publishes selection without a secondary click',
      (tester) async {
    final selected = <String>[];
    var wordCalls = 0;
    messenger.setMockMethodCallHandler(wordChannel, (_) async {
      wordCalls++;
      return [0, 5];
    });
    await open(tester,
        ocr: true,
        recognize: () async => 'Hello reader. Another sentence.',
        selection: (_, value, context, rect, ids) async {
          selected.add(value);
          expect(rect.isFinite, true);
        });
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.down(textPoint(tester, 1));
    await mouse.moveTo(textPoint(tester, 10));
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
    final controller = tester
        .widget<TextField>(find.byKey(const ValueKey('reflow-text')))
        .controller!;
    expect(controller.selection.isCollapsed, false);
    expect(selected.last, controller.selection.textInside(controller.text));
    expect(wordCalls, 0); // A drag keeps its precise user-selected boundaries.
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets(
      'Android initial OCR long press expands once and preserves handles',
      (tester) async {
    var wordCalls = 0;
    final selected = <String>[];
    messenger.setMockMethodCallHandler(wordChannel, (_) async {
      wordCalls++;
      return [0, 2];
    });
    await open(tester,
        ocr: true,
        recognize: () async => '中国文化源远流长。\n\n第二段。',
        selection: (_, value, context, rect, ids) async => selected.add(value));
    await tester.longPressAt(textPoint(tester, 0));
    await tester.pumpAndSettle();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.textEditingValue.selection,
        const TextSelection(baseOffset: 0, extentOffset: 2));
    expect(selected.last, '中国');
    expect(editable.selectionOverlay?.handlesAreVisible, true);
    expect(wordCalls, 1);
    editable.userUpdateTextEditingValue(
        editable.textEditingValue.copyWith(
            selection: const TextSelection(baseOffset: 1, extentOffset: 5)),
        SelectionChangedCause.drag);
    await tester.pumpAndSettle();
    expect(editable.textEditingValue.selection,
        const TextSelection(baseOffset: 1, extentOffset: 5));
    expect(selected.last, '国文化源');
    expect(wordCalls, 1);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets(
      'macOS double click uses system word bounds and opens reading menu',
      (tester) async {
    final selected = <String>[];
    var calls = 0;
    messenger.setMockMethodCallHandler(wordChannel, (_) async {
      calls++;
      return [0, 2];
    });
    await open(tester,
        ocr: true,
        recognize: () async => '中国文化源远流长。',
        selection: (_, value, context, rect, ids) async => selected.add(value));
    final point = textPoint(tester, 0);
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(selected.last, '中国');
    expect(calls, 1);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('page change discards pending word bounds and menu',
      (tester) async {
    final pending = Completer<List<int>?>();
    messenger.setMockMethodCallHandler(wordChannel, (_) => pending.future);
    var selections = 0;
    await open(tester,
        extract: (_) async => '中国文化源远流长。',
        selection: (_, value, context, rect, ids) async => selections++);
    await tester.longPressAt(textPoint(tester, 0));
    await tester.pump(const Duration(milliseconds: 90));
    await key.currentState!.turnOriginalPage(1);
    pending.complete([0, 2]);
    await tester.pumpAndSettle();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.textEditingValue.selection.isCollapsed, true);
    expect(selections, 0);
  });

  testWidgets('macOS press and hold expands OCR text without a double click',
      (tester) async {
    final selected = <String>[];
    messenger.setMockMethodCallHandler(wordChannel, (_) async => [0, 2]);
    await open(tester,
        ocr: true,
        recognize: () async => '中国文化源远流长。',
        selection: (_, value, context, rect, ids) async => selected.add(value));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.down(textPoint(tester, 0));
    await tester.pump(kLongPressTimeout);
    await tester.pump(const Duration(milliseconds: 90));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(selected.last, '中国');
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets(
      'OCR uses ordinary reader paragraph preference only on initial selection',
      (tester) async {
    Prefs().longPressSelectParagraph = true;
    await open(tester, extract: (_) async => '中国文化源远流长。\n\n第二段。');
    await tester.longPressAt(textPoint(tester, 2));
    await tester.pumpAndSettle();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(
        editable.textEditingValue.selection
            .textInside(editable.textEditingValue.text),
        '中国文化源远流长。');
    expect(editable.selectionOverlay?.handlesAreVisible, true);
  });

  testWidgets('late word lookup cannot overwrite a manually adjusted selection',
      (tester) async {
    final pending = Completer<List<int>?>();
    messenger.setMockMethodCallHandler(wordChannel, (_) => pending.future);
    await open(tester, extract: (_) async => '中国文化源远流长。');
    await tester.longPressAt(textPoint(tester, 0));
    await tester.pump(const Duration(milliseconds: 90));
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    editable.userUpdateTextEditingValue(
        editable.textEditingValue.copyWith(
            selection: const TextSelection(baseOffset: 1, extentOffset: 5)),
        SelectionChangedCause.drag);
    pending.complete([0, 2]);
    await tester.pumpAndSettle();
    expect(editable.textEditingValue.selection,
        const TextSelection(baseOffset: 1, extentOffset: 5));
  });
  testWidgets(
      'cropped whole-page bounds feed text and OCR and invalidate cached output',
      (tester) async {
    var crop = <String, num>{'x': .1, 'y': .2, 'width': .8, 'height': .6};
    final extracted = <Map<String, dynamic>>[],
        rendered = <Map<String, dynamic>>[];
    await open(tester,
        info: (page) async => {'page': page ?? 0, 'total': 3, 'region': crop},
        extractionRequest: extracted.add,
        renderRequest: rendered.add);
    expect(extracted.single['region'], crop);
    await key.currentState!.setMode(true);
    await tester.pumpAndSettle();
    expect(rendered.single['region'], crop);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Selected area'), findsNothing);
    await key.currentState!.setMode(false);
    expect(extracted.length, 1);
    crop = {'x': 0, 'y': 0, 'width': 1, 'height': 1};
    await key.currentState!.turnOriginalPage(1);
    await key.currentState!.turnOriginalPage(-1);
    await tester.pumpAndSettle();
    expect(extracted.length, 3);
    expect(extracted.last['region'], crop);
  });
  testWidgets(
      'reflow is inline, turns original pages and reuses cached text without OCR',
      (tester) async {
    var extractions = 0, recognitions = 0;
    await open(tester, extract: (page) async {
      extractions++;
      return 'Page $page text.';
    }, recognize: () async {
      recognitions++;
      return 'OCR';
    });
    expect(find.byType(Dialog), findsNothing);
    expect(text(tester), 'Page 0 text.');
    await tester.tap(find.byKey(const ValueKey('reflow-next')));
    await tester.pumpAndSettle();
    expect(text(tester), 'Page 1 text.');
    await tester.tap(find.byKey(const ValueKey('reflow-previous')));
    await tester.pumpAndSettle();
    expect(text(tester), 'Page 0 text.');
    expect(extractions, 2);
    expect(recognitions, 0);
    expect(pages, [0, 1, 0]);
  });
  testWidgets(
      'OCR mode bypasses embedded text, and mode switch uses separate caches',
      (tester) async {
    var extracted = 0, ocr = 0;
    await open(tester, ocr: true, extract: (_) async {
      extracted++;
      return 'Text layer';
    }, recognize: () async {
      ocr++;
      return 'OCR words';
    });
    expect(text(tester), 'OCR words');
    expect(extracted, 0);
    await key.currentState!.setMode(false);
    await tester.pumpAndSettle();
    expect(text(tester), 'Text layer');
    await key.currentState!.setMode(true);
    await tester.pumpAndSettle();
    expect(text(tester), 'OCR words');
    expect(ocr, 1);
  });
  testWidgets(
      'missing model asks for explicit download; failure keeps last successful page',
      (tester) async {
    model.ready = false;
    await open(tester,
        extract: (page) async => page == 0 ? 'Existing text' : '');
    await tester.tap(find.byKey(const ValueKey('reflow-next')));
    await tester.pumpAndSettle();
    expect(find.text('OCR model settings'), findsOneWidget);
    expect(text(tester), 'Existing text');
    expect(pages, [0]);
  });
  testWidgets(
      'cancelled or disposed extraction never commits late text or navigation',
      (tester) async {
    final pending = Completer<String>();
    await open(tester,
        extract: (page) => page == 0 ? Future.value('First') : pending.future);
    await tester.tap(find.byKey(const ValueKey('reflow-next')));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    pending.complete('Late second');
    await tester.pumpAndSettle();
    expect(text(tester), 'First');
    expect(pages, [0]);
    final next = Completer<String>();
    await tester.pumpWidget(const SizedBox());
    // Fresh reader, pending first-page extraction.
    await open(tester, extract: (_) => next.future, settle: false);
    await tester.pumpWidget(const SizedBox());
    next.complete('After disposal');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'native selection forwards exact range, context and overlapping marks to existing toolbar',
      (tester) async {
    final page = DocumentReflowPage(
        page: 0, ocr: false, rawText: 'Selected words and context.');
    notes = [
      BookNote(
          id: 7,
          bookId: 1,
          content: 'Selected',
          cfi: DocumentReflowAnchor(0, false, page.revision, 0, 8).encode(),
          chapter: '1',
          type: 'highlight',
          color: 'ffff00',
          updateTime: DateTime.now())
    ];
    DocumentReflowAnchor? selected;
    String? selectedText;
    List<int>? ids;
    await open(tester,
        extract: (_) async => page.rawText,
        selection: (a, t, c, r, i) async {
          selected = a;
          selectedText = t;
          ids = i;
          expect(c, contains('context'));
        });
    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('reflow-text')));
    field.controller!.selection =
        const TextSelection(baseOffset: 2, extentOffset: 8);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    field.contextMenuBuilder!(
        tester.element(find.byType(EditableText)), editable);
    await tester.pump();
    expect(selectedText, 'lected');
    expect(selected!.start, 2);
    expect(selected!.end, 8);
    expect(ids, [7]);
    expect(key.currentState!.speechText(selected!.encode()), 'lected');
    final span = field.controller!.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: const TextStyle(),
        withComposing: false);
    expect(
        span.children!
            .whereType<TextSpan>()
            .any((s) => s.style?.backgroundColor != null),
        true);
    notes.clear();
    await key.currentState!.refreshNotes();
    await tester.pump();
    final cleared = field.controller!.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        withComposing: false);
    expect(
        cleared.children!
            .whereType<TextSpan>()
            .every((s) => s.style?.backgroundColor == null),
        true);
  });
  testWidgets('saved note opens its cached revision rather than new OCR output',
      (tester) async {
    final page = DocumentReflowPage(
        page: 2, ocr: true, rawText: 'Saved recognition text');
    await store.save(page, 'old-model');
    var extraction = 0;
    final anchor = DocumentReflowAnchor(2, true, page.revision, 6, 17);
    await open(tester, anchor: anchor, extract: (_) async {
      extraction++;
      return 'Different';
    });
    expect(text(tester), page.text);
    expect(pages, [2]);
    expect(extraction, 0);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('reflow-text')))
            .controller!
            .selection
            .start,
        6);
  });
  testWidgets(
      'touch selection exposes handles and clears stale menu after collapsing',
      (tester) async {
    var selections = 0, cleared = 0;
    await open(tester,
        extract: (_) async => 'Hello reader. Select and annotate this page.',
        selection: (a, text, context, rect, ids) async {
          selections++;
          expect(text.isNotEmpty, true);
        },
        clearMenu: () => cleared++);
    final field = find.byKey(const ValueKey('reflow-text'));
    await tester.longPressAt(tester.getTopLeft(field) + const Offset(30, 15));
    await tester.pumpAndSettle();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.textEditingValue.selection.isCollapsed, false);
    expect(editable.selectionOverlay?.handlesAreVisible, true);
    expect(selections, greaterThan(0));
    final previous = cleared;
    tester.widget<TextField>(field).controller!.selection =
        const TextSelection.collapsed(offset: 2);
    await tester.pump();
    expect(cleared, greaterThan(previous));
  });
  testWidgets('saved long-page annotation scrolls to its passage',
      (tester) async {
    final page = DocumentReflowPage(
        page: 1,
        ocr: false,
        rawText:
            '${List.generate(100, (i) => 'Paragraph $i on the original page.').join('\n\n')}\n\nTarget passage.');
    await store.save(page, 'old');
    final start = page.text.indexOf('Target');
    await open(tester,
        anchor:
            DocumentReflowAnchor(1, false, page.revision, start, start + 6));
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(scroll.controller!.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'phone landscape and large text keep original and page controls reachable',
      (tester) async {
    for (final size in [const Size(320, 640), const Size(740, 320)]) {
      await tester.pumpWidget(const SizedBox());
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await open(tester, textScale: 1.5);
      expect(find.byKey(const ValueKey('reflow-original')), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
