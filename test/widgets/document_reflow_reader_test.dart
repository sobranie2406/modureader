import 'package:modu_reader/models/custom_css_profile.dart';
import 'package:modu_reader/models/css_visual_style.dart';
import 'dart:async';
import 'dart:io';
import 'package:modu_reader/service/installed_fonts.dart';
import 'package:modu_reader/enums/translation_mode.dart';
import 'package:modu_reader/enums/lang_list.dart';
import 'package:modu_reader/service/translate/index.dart';
import 'package:modu_reader/service/tts/tts_page_source.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/widgets/common/app_scroll_behavior.dart';
import 'package:modu_reader/enums/text_alignment.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/models/book_note.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:modu_reader/service/ocr/document_ocr_precache.dart';
import 'package:modu_reader/service/ocr/document_text_geometry.dart';
import 'package:modu_reader/service/ocr/document_text_style.dart';
import 'package:modu_reader/service/ocr/ocr_model_store.dart';
import 'package:modu_reader/widgets/reading_page/document_reflow_reader.dart';
import 'package:modu_reader/widgets/reading_page/document_text_style_dialog.dart';
import 'package:modu_reader/widgets/reading_page/document_reader_surface.dart';
import 'package:modu_reader/widgets/reading_page/style_widget.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:flutter/material.dart';
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
      latest['$page'];
  @override
  Future<DocumentReflowPage?> readAnchor(DocumentReflowAnchor anchor) async =>
      revisions[anchor.revision];
  @override
  Future<void> save(DocumentReflowPage value, String profile,
      {bool onlyIfAbsent = false, bool replaceEmbeddedText = false}) async {
    final saved = latest['${value.page}'];
    if (onlyIfAbsent &&
        saved != null &&
        !(replaceEmbeddedText && value.ocr && !saved.ocr)) {
      return;
    }
    latest['${value.page}'] = value;
    revisions[value.revision] = value;
  }

  @override
  Future<DocumentReflowPage> saveEdit(
      DocumentReflowPage original, String text) async {
    if (text.trim().isEmpty) throw const FormatException('Empty edit');
    final edited = DocumentReflowPage(
        page: original.page,
        ocr: original.ocr,
        rawText: original.rawText,
        rawRegions: original.rawRegions,
        editedText: text);
    await save(edited, '');
    return edited;
  }
}

class Model extends OcrModelStore {
  bool ready = true;
  @override
  Future<bool> available() async => ready;
}

class PageTranslator extends TranslateServiceProvider {
  PageTranslator({this.stream});
  final Stream<String>? stream;
  final requests = <String>[];
  @override
  TranslateService get service => TranslateService.microsoftFree;
  @override
  String getLabel(BuildContext context) => 'Test translation';
  @override
  Widget translate(String text, LangListEnum from, LangListEnum to,
          {String? contextText}) =>
      const SizedBox();
  @override
  Stream<String> translateStream(
      String text, LangListEnum from, LangListEnum to,
      {String? contextText, bool isFullText = false}) {
    requests.add(text);
    return stream ?? Stream.value('Translated $text');
  }
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
      DocumentTextResult? sourceGeometry,
      ReflowSelection? selection,
      ReflowTranslatedSelection? translatedSelection,
      Future<void> Function(int)? navigate,
      VoidCallback? close,
      VoidCallback? cancelRender,
      DocumentOcrPrecache? precache,
      void Function(int, int)? sourcePageChanged,
      Future<Map<String, dynamic>> Function(int?)? info,
      void Function(Map<String, dynamic>)? extractionRequest,
      void Function(Map<String, dynamic>)? renderRequest,
      VoidCallback? clearMenu,
      VoidCallback? openReaderMenu,
      ValueChanged<Widget>? openReaderPanel,
      VoidCallback? closeReaderMenu,
      FocusOnKeyEventCallback? readerKeyEvent,
      bool Function()? readerTap,
      VoidCallback? keyboardEligibilityChanged,
      ValueChanged<int>? pdfWheelZoom,
      bool Function()? wheelZoomAllowed,
      void Function(TtsPageSource)? narrationInvalidated,
      bool quickMarkEnabled = false,
      ReflowQuickMark? quickMark,
      VoidCallback? quickMarkUnavailable,
      bool comparison = false,
      ValueChanged<bool>? onComparisonChanged,
      Future<void> Function(String, String, bool)? query,
      Future<void> Function(String)? draft,
      Future<void> Function(DocumentReflowAnchor, String)? bookmark,
      double textScale = 1,
      DocumentTextStyle initialStyle = const DocumentTextStyle(),
      bool settle = true}) async {
    await tester.pumpWidget(MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        localizationsDelegates: const [L10n.delegate],
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: Scaffold(
            body: DocumentReflowReader(
          key: key,
          onTranslatedSelection: translatedSelection,
          onReaderKeyEvent: readerKeyEvent,
          onReaderTap: readerTap,
          onKeyboardEligibilityChanged: keyboardEligibilityChanged,
          onPdfWheelZoom: pdfWheelZoom,
          wheelZoomAllowed: wheelZoomAllowed,
          onNarrationInvalidated: narrationInvalidated,
          quickMarkEnabled: quickMarkEnabled,
          onQuickMark: quickMark,
          onQuickMarkUnavailable: quickMarkUnavailable,
          comparison: comparison,
          onComparisonChanged: onComparisonChanged,
          store: store,
          precache: precache,
          onSourcePageChanged: sourcePageChanged,
          modelStore: model,
          forceOcr: ocr,
          anchor: anchor,
          info: info ??
              (page) async =>
                  {'page': page ?? 0, 'total': 3, 'width': 600, 'height': 800},
          extractText: (r) async {
            extractionRequest?.call(r);
            if (sourceGeometry != null) return sourceGeometry.toJson();
            return {
              'text': await (extract?.call(r['page'] as int) ??
                  Future.value('第${r['page']}页正文。\n\n下一段内容。'))
            };
          },
          render: (r) async {
            renderRequest?.call(r);
            return {'dataUrl': fixture.pixel};
          },
          cancelRender: cancelRender ?? () {},
          recognize: (_, cancel, progress) async =>
              await (recognize?.call() ?? Future.value('识别文字。\n\n另一段。')),
          recognizeWithRegions: sourceGeometry == null
              ? null
              : (_, cancel, progress) async => sourceGeometry,
          onClose: close ?? () {},
          onPageChanged: navigate ?? (page) async => pages.add(page),
          clearMenu: clearMenu ?? () {},
          onOpenReaderMenu: openReaderMenu,
          onOpenReaderPanel: openReaderPanel,
          onCloseReaderMenu: closeReaderMenu,
          loadNotes: () async => notes,
          initialStyle: initialStyle,
          saveStyle: (_) async {},
          onSelection: selection ?? (_, text, context, rect, ids) async {},
          onQuery: query,
          onAiDraft: draft,
          onBookmark: bookmark,
        ))));
    if (settle) await tester.pumpAndSettle();
  }

  String text(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const ValueKey('reflow-text')))
      .controller!
      .text;

  Finder reflowViewport() => find
      .ancestor(
          of: find.byKey(const ValueKey('reflow-text')),
          matching: find.byType(SingleChildScrollView))
      .first;

  ScrollController reflowScroll(WidgetTester tester) =>
      tester.widget<SingleChildScrollView>(reflowViewport()).controller!;

  (int, double) visibleAnchor(WidgetTester tester) {
    final render = tester
        .state<EditableTextState>(find.byType(EditableText).first)
        .renderEditable;
    final top = tester.getTopLeft(reflowViewport()).dy;
    final offset = render
        .getPositionForPoint(
            Offset(render.localToGlobal(Offset.zero).dx + 1, top + 1))
        .offset;
    final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
    return (offset, render.localToGlobal(caret.topLeft).dy - top);
  }

  double anchorTop(WidgetTester tester, int offset) {
    final render = tester
        .state<EditableTextState>(find.byType(EditableText).first)
        .renderEditable;
    final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
    return render.localToGlobal(caret.topLeft).dy -
        tester.getTopLeft(reflowViewport()).dy;
  }

  testWidgets('reflow style changes retain the visible source line and anchors',
      (tester) async {
    var reads = 0;
    await open(tester, extract: (_) async {
      reads++;
      return List.generate(100, (i) => 'Paragraph $i. More words for reflow.')
          .join('\n\n');
    });
    final scroll = reflowScroll(tester);
    scroll.jumpTo(900);
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('reflow-text'));
    final controller = tester.widget<TextField>(field).controller!;
    final source = key.currentState!.narrationSource!;
    final originalText = controller.text;
    final page = key.currentState!.quickMarkPage;
    for (final style in [
      const DocumentTextStyle(size: 30),
      const DocumentTextStyle(size: 30, height: 2.2, spacing: 1),
      const DocumentTextStyle(size: 30, height: 2.2, serif: true),
    ]) {
      final before = visibleAnchor(tester);
      final selection = controller.selection;
      await (key.currentState!.stylePanel() as DocumentTextStyleDialog)
          .save!(style);
      await tester.pumpAndSettle();
      expect(anchorTop(tester, before.$1), closeTo(before.$2, .1));
      expect(controller.selection, selection);
      expect(controller.text, originalText);
      expect(key.currentState!.narrationSource, same(source));
      expect(source.valid, isTrue);
      expect(key.currentState!.quickMarkPage, same(page));
    }
    expect(reads, 1);
    expect(pages, [0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rotation and comparison resizing retain a source line position',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester,
        comparison: true,
        extract: (_) async =>
            List.generate(150, (i) => '第$i段。源文字位置在重新排版后应当继续保持。').join('\n\n'));
    reflowScroll(tester).jumpTo(900);
    await tester.pumpAndSettle();
    for (final size in [
      const Size(350, 700),
      const Size(700, 350),
      const Size(600, 600),
    ]) {
      final before = visibleAnchor(tester);
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(anchorTop(tester, before.$1), closeTo(before.$2, .1));
    }
    expect(pages, [0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation wins over an already queued layout restoration',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester,
        extract: (page) async =>
            List.filled(100, 'Source page $page. More words.').join('\n\n'));
    reflowScroll(tester).jumpTo(900);
    await tester.pumpAndSettle();
    Future<void>? navigation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigation = key.currentState!.goToPage(1);
    });
    tester.view.physicalSize = const Size(350, 700);
    await tester.pumpAndSettle();
    await navigation;
    expect(text(tester), startsWith('Source page 1.'));
    expect(reflowScroll(tester).offset, 0);
    expect(pages, [0, 1]);
  });

  for (final operation in ['wheel', 'speech']) {
    testWidgets('$operation wins over a pending reflow layout restoration',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(700, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester,
          extract: (_) async => List.generate(
                  150, (i) => 'Paragraph $i. A long sentence for layout tests.')
              .join('\n\n'));
      final scroll = reflowScroll(tester);
      scroll.jumpTo(900);
      await tester.pumpAndSettle();
      final old = visibleAnchor(tester);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (operation == 'wheel') {
          GestureBinding.instance.handlePointerEvent(PointerScrollEvent(
              position: tester.getCenter(reflowViewport()),
              scrollDelta: const Offset(0, 80)));
        } else {
          final controller = tester
              .widget<TextField>(find.byKey(const ValueKey('reflow-text')))
              .controller!;
          key.currentState!.narrationSource!
              .onPosition!(controller.text.indexOf('Paragraph 100.'));
        }
      });
      tester.view.physicalSize = const Size(350, 700);
      await tester.pumpAndSettle();
      expect(anchorTop(tester, old.$1), isNot(closeTo(old.$2, 1)));
      expect(scroll.offset,
          operation == 'wheel' ? closeTo(980, .1) : greaterThan(3000));
      expect(pages, [0]);
    });
  }

  testWidgets('effective CSS size and paragraph gap preserve the source line',
      (tester) async {
    await open(tester,
        extract: (_) async =>
            List.filled(150, 'A source paragraph with several words.')
                .join('\n\n'));
    reflowScroll(tester).jumpTo(900);
    await tester.pumpAndSettle();
    final before = visibleAnchor(tester);
    await Prefs().saveCustomCssProfile(
        0,
        const CustomCssProfile(
            css: 'p {font-size:32px;line-height:2.1;font-family:monospace;}',
            visual: CssVisualStyle({'paragraphGap': 2.5})));
    await Prefs().saveCustomCssSelection(
        const CustomCssSelection(index: 0, enabled: true, indices: [0]));
    await tester.pumpAndSettle();
    expect(anchorTop(tester, before.$1), closeTo(before.$2, .1));
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('reflow-text')))
            .style!
            .fontSize,
        32);
    expect(pages, [0]);
  });

  for (final percent in [80, 90, 100]) {
    testWidgets('reflow manual scroll respects $percent percent without align',
        (tester) async {
      Prefs().scrollPagePercent = percent;
      Prefs().scrollAutoAlign = false;
      await open(tester,
          extract: (_) async =>
              List.filled(100, 'A line of readable source text.').join('\n\n'));
      final scroll = reflowScroll(tester);
      final distance = scroll.position.viewportDimension * percent / 100;
      final forward = key.currentState!.turn(1);
      await tester.pumpAndSettle();
      await forward;
      expect(scroll.offset, closeTo(distance, .01));
      final backward = key.currentState!.turn(-1);
      await tester.pumpAndSettle();
      await backward;
      expect(scroll.offset, closeTo(0, .01));
      expect(pages, [0]);
    });
  }

  testWidgets('aligned manual scroll retains a real visible text line',
      (tester) async {
    Prefs().scrollPagePercent = 100;
    Prefs().scrollAutoAlign = true;
    await open(tester,
        extract: (_) async =>
            List.filled(100, 'A line of readable source text.').join('\n'));
    final scroll = reflowScroll(tester);
    final render = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final lastVisible = render.getPositionForPoint(
        tester.getBottomLeft(reflowViewport()) + const Offset(2, -1));
    final forward = key.currentState!.turn(1);
    await tester.pumpAndSettle();
    await forward;
    expect(scroll.offset, greaterThan(0));
    expect(scroll.offset, lessThan(scroll.position.viewportDimension));
    expect(visibleAnchor(tester).$1, lessThanOrEqualTo(lastVisible.offset));
    expect(pages, [0]);
  });

  testWidgets(
      'eink auto scroll waits then steps without scheduling frame ticks',
      (tester) async {
    Prefs().eInkMode = true;
    Prefs().scrollAutoAlign = false;
    Prefs().scrollPagePercent = 80;
    var stopped = 0;
    await open(tester,
        extract: (_) async => List.filled(100, '甲乙丙').join('\n\n'));
    final scroll = reflowScroll(tester);
    final distance = scroll.position.viewportDimension * .8;
    final rate =
        (scroll.position.maxScrollExtent + scroll.position.viewportDimension) /
            60;
    final interval = (distance / rate * 1000).round();
    expect(key.currentState!.startAutoScroll(1, () => stopped++), isTrue);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(Duration(milliseconds: interval - 1));
    expect(scroll.offset, 0);
    await tester.pump(const Duration(milliseconds: 2));
    expect(scroll.offset, closeTo(distance, .01));
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    expect(stopped, 0);
    expect(pages, [0]);
    key.currentState!.stopAutoScroll();
    final offset = scroll.offset;
    await tester.pump(Duration(milliseconds: interval * 2));
    expect(scroll.offset, offset);
    expect(stopped, 1);
  });

  testWidgets('eink speed updates reschedule the step and page end stops once',
      (tester) async {
    Prefs().eInkMode = true;
    Prefs().scrollAutoAlign = false;
    var reads = 0, stopped = 0;
    await open(tester, extract: (_) async {
      reads++;
      return List.filled(100, '甲乙丙').join('\n\n');
    });
    final scroll = reflowScroll(tester);
    final distance = scroll.position.viewportDimension * .8;
    final rate =
        (scroll.position.maxScrollExtent + scroll.position.viewportDimension) /
            60;
    final interval = (distance / rate * 1000).round();
    final reader = key.currentState!;
    expect(reader.startAutoScroll(1, () => stopped++), isTrue);
    await tester.pump(Duration(milliseconds: interval ~/ 2));
    expect(scroll.offset, 0);
    expect(reader.startAutoScroll(2, () => stopped++), isTrue);
    await tester.pump(Duration(milliseconds: interval ~/ 2 - 1));
    expect(scroll.offset, 0);
    await tester.pump(const Duration(milliseconds: 3));
    expect(scroll.offset, closeTo(distance, .01));
    expect(stopped, 0);
    scroll.jumpTo(scroll.position.maxScrollExtent - 2);
    expect(reader.startAutoScroll(4, () => stopped++), isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.offset, scroll.position.maxScrollExtent);
    expect(stopped, 1);
    expect(reads, 1);
    expect(pages, [0]);
    reader.stopAutoScroll();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
    expect(stopped, 1);
    expect(tester.takeException(), isNull);
  });

  for (final initialEink in [false, true]) {
    testWidgets('eink mode change stops an active session ($initialEink)',
        (tester) async {
      Prefs().eInkMode = initialEink;
      await open(tester,
          extract: (_) async =>
              List.filled(100, 'A line of readable source text.').join('\n\n'));
      var stopped = 0;
      expect(key.currentState!.startAutoScroll(1, () => stopped++), isTrue);
      await tester.pump();
      Prefs().eInkMode = !initialEink;
      await tester.pumpAndSettle();
      expect(stopped, 1);
      final offset = reflowScroll(tester).offset;
      await tester.pump(const Duration(seconds: 30));
      expect(reflowScroll(tester).offset, offset);
      expect(stopped, 1);
      expect(tester.binding.transientCallbackCount, 0);
    });
  }

  testWidgets(
      'continuous narration uses edited cache then extracts the next page',
      (tester) async {
    store.latest['1'] = DocumentReflowPage(
        page: 1, ocr: false, rawText: '旧识别文字。', editedText: '已校对的下一页。');
    final extracted = <int>[], invalidated = <TtsPageSource>[];
    await open(tester, extract: (page) async {
      extracted.add(page);
      return '第$page页。';
    }, narrationInvalidated: invalidated.add);
    final source = key.currentState!.narrationSource!;
    expect(source.currentText(), '第0页。');
    source.collect(100);
    expect(pages, [0]);
    final next = source.nextTextContinuous();
    expect(source.nextTextContinuous(), same(next));
    await tester.pumpAndSettle();
    expect(await next, '已校对的下一页。');
    expect(key.currentState!.narrationSource, same(source));
    expect(source.chapter, contains('2'));
    expect(extracted, [0]);
    final last = source.nextTextContinuous();
    await tester.pumpAndSettle();
    expect(await last, '第2页。');
    expect(extracted, [0, 2]);
    expect(pages, [0, 1, 2]);
    expect(await source.nextTextContinuous(), isEmpty);
    expect(invalidated, isEmpty);
  });

  testWidgets(
      'stop while next page loads prevents late navigation and can retry',
      (tester) async {
    final gate = Completer<String>();
    await open(tester,
        extract: (page) async => page == 0 ? '当前页。' : gate.future);
    final source = key.currentState!.narrationSource!;
    final next = source.nextTextContinuous();
    await tester.pump();
    source.cancelAdvance();
    gate.complete('下一页。');
    await tester.pumpAndSettle();
    expect(await next, isEmpty);
    expect(pages, [0]);
    expect(text(tester), '当前页。');
    final retry = source.nextTextContinuous();
    await tester.pumpAndSettle();
    expect(await retry, '下一页。');
    expect(pages, [0, 1]);
  });

  testWidgets(
      'missing OCR model preserves the current page and reports failure',
      (tester) async {
    await open(tester, extract: (page) async => page == 0 ? '当前页。' : '');
    model.ready = false;
    final source = key.currentState!.narrationSource!;
    final result = expectLater(source.nextTextContinuous(), throwsStateError);
    await tester.pumpAndSettle();
    await result;
    expect(pages, [0]);
    expect(source.currentText(), '当前页。');
  });

  testWidgets(
      'switching to forced OCR replaces embedded cache and stays active across pages',
      (tester) async {
    var extractions = 0, recognitions = 0;
    await open(tester, extract: (_) async {
      extractions++;
      return 'Embedded page';
    }, recognize: () async {
      recognitions++;
      return 'OCR page';
    });
    expect(extractions, 1);
    expect(recognitions, 0);
    final changed = key.currentState!.setMode(true);
    await tester.pumpAndSettle();
    await changed;
    expect(recognitions, 1);
    expect(extractions, 1);
    expect(store.latest['0']!.ocr, isTrue);
    final next = key.currentState!.goToPage(1);
    await tester.pumpAndSettle();
    await next;
    expect(recognitions, 2);
    expect(extractions, 1);
    final normal = key.currentState!.setMode(false);
    await tester.pumpAndSettle();
    await normal;
    final third = key.currentState!.goToPage(2);
    await tester.pumpAndSettle();
    await third;
    expect(extractions, 2);
    expect(recognitions, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('removing an active reflow font preserves size and spacing',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('modu-reflow-font-');
    addTearDown(() => directory.delete(recursive: true));
    File('${directory.path}/removed.ttf').writeAsStringSync('fixture');
    await open(tester,
        initialStyle: const DocumentTextStyle(
          font: 'removed.ttf',
          size: 28,
          spacing: 2,
        ));
    TextStyle style() => tester
        .widget<EditableText>(find.descendant(
          of: find.byKey(const ValueKey('reflow-text')),
          matching: find.byType(EditableText),
        ))
        .style;
    expect(style().fontFamily, 'removed.ttf');
    await tester.runAsync(
        () => removeInstalledFont('removed.ttf', directory: directory));
    await tester.pumpAndSettle();
    expect(
        style().fontFamily,
        Theme.of(tester.element(find.byKey(const ValueKey('reflow-text'))))
            .textTheme
            .bodyLarge!
            .fontFamily);
    expect(style().fontSize, 28);
    expect(style().letterSpacing, 2);
  });

  testWidgets(
      'reflow translation only submits visible paragraphs and loads on scroll',
      (tester) async {
    final paragraphs = List.generate(
        30,
        (i) =>
            'Paragraph $i. ${List.filled(15, 'Source text for testing.').join(' ')}');
    await open(tester, extract: (_) async => paragraphs.join('\n\n'));
    final provider = PageTranslator();
    final task = key.currentState!.translateCurrentPage(
        TranslationModeEnum.translationOnly,
        provider: provider);
    await tester.pumpAndSettle();
    await task;
    expect(provider.requests, isNotEmpty);
    expect(provider.requests.length, lessThan(paragraphs.length));
    expect(provider.requests, isNot(contains(paragraphs.last)));
    final scroll = tester
        .widget<SingleChildScrollView>(find
            .ancestor(
                of: find.byKey(const ValueKey('reflow-translated-text')),
                matching: find.byType(SingleChildScrollView))
            .first)
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(provider.requests, contains(paragraphs.last));
    key.currentState!.stopTranslation();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('current-page translation uses saved edits without modifying OCR',
      (tester) async {
    Prefs().languageTranslationTextStyle =
        '{"font":"monospace","size":24,"bold":true,"italic":true,"color":"#287D75"}';
    await open(tester);
    final reader = key.currentState!;
    final original = store.latest['0']!;
    final edited = await store.saveEdit(original, 'Corrected paragraph.');
    final translator = PageTranslator();
    final task = reader.translateCurrentPage(TranslationModeEnum.bilingual,
        provider: translator);
    await tester.pumpAndSettle();
    await task;
    String translated() => tester
        .widget<TextField>(find.byKey(const ValueKey('reflow-translated-text')))
        .controller!
        .text;
    expect(translator.requests, ['Corrected paragraph.']);
    expect(translated(),
        'Corrected paragraph.\n\nTranslated Corrected paragraph.');
    List<TextSpan> spans() {
      final field = find.byKey(const ValueKey('reflow-translated-text'));
      return tester
          .widget<TextField>(field)
          .controller!
          .buildTextSpan(
              context: tester.element(field),
              style: const TextStyle(fontSize: 20),
              withComposing: false)
          .children!
          .cast<TextSpan>();
    }

    var output = spans().last.style!;
    expect(output.fontFamily, 'monospace');
    expect(output.fontSize, 24);
    expect(output.fontWeight, FontWeight.bold);
    expect(output.fontStyle, FontStyle.italic);
    expect(output.color, const Color(0xFF287D75));
    expect(spans().first.style?.color, isNull);
    expect(spans().first.style?.fontFamily, isNull);
    expect(spans().first.style?.fontSize, isNull);
    Prefs().classicalTranslationTextStyle =
        '{"font":"serif","size":36,"bold":false,"italic":false}';
    await tester.pumpAndSettle();
    expect(spans().last.style, output);
    Prefs().languageTranslationTextStyle =
        '{"font":"sans-serif","size":18,"bold":false,"italic":false}';
    await tester.pumpAndSettle();
    output = spans().last.style!;
    expect(output.fontFamily, 'sans-serif');
    expect(output.fontSize, 18);
    expect(output.fontWeight, FontWeight.normal);
    expect(output.fontStyle, FontStyle.normal);
    expect(output.color, isNull);
    expect(translator.requests.length, 1);
    expect(reader.narrationSource!.currentText(), 'Corrected paragraph.');
    expect(reader.narrationSourceFor(original.anchor(0, 2)), isNull);
    final switchTask = reader.translateCurrentPage(
        TranslationModeEnum.translationOnly,
        provider: translator);
    await tester.pumpAndSettle();
    await switchTask;
    expect(translated(), 'Translated Corrected paragraph.');
    expect(translator.requests.length, 1);
    expect(store.latest['0'], same(edited));
    reader.stopTranslation();
    await tester.pumpAndSettle();
    expect(text(tester), original.text);
    expect(reader.narrationSourceFor(original.anchor(0, 2)), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'turning original page clears translation without translating next page',
      (tester) async {
    await open(tester);
    final translator = PageTranslator();
    final task = key.currentState!.translateCurrentPage(
        TranslationModeEnum.translationOnly,
        provider: translator);
    await tester.pumpAndSettle();
    await task;
    final count = translator.requests.length;
    await tester.tap(find.byKey(const ValueKey('reflow-next')));
    await tester.pumpAndSettle();
    expect(key.currentState!.translationMode.value, TranslationModeEnum.off);
    expect(find.byKey(const ValueKey('reflow-translated-text')), findsNothing);
    expect(text(tester), contains('第1页'));
    expect(translator.requests.length, count);
    expect(tester.takeException(), isNull);
  });

  testWidgets('translation transport cancels on source-page navigation',
      (tester) async {
    await open(tester);
    var cancelled = false;
    final stream = StreamController<String>(onCancel: () => cancelled = true);
    final translator = PageTranslator(stream: stream.stream);
    final task = key.currentState!.translateCurrentPage(
        TranslationModeEnum.translationOnly,
        provider: translator);
    await tester.pump();
    expect(key.currentState!.narrationSource, isNull);
    await tester.tap(find.byKey(const ValueKey('reflow-next')));
    await tester.pumpAndSettle();
    expect(key.currentState!.translationMode.value, TranslationModeEnum.off);
    await task;
    stream.add('Late translation');
    unawaited(stream.close());
    await tester.pumpAndSettle();
    expect(cancelled, isTrue);
    expect(translator.requests.length, 1);
    expect(key.currentState!.translationMode.value, TranslationModeEnum.off);
    expect(text(tester), contains('第1页'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'translated selection never produces original OCR anchors and search stays in translation',
      (tester) async {
    var selections = 0;
    await open(tester,
        selection: (_, __, ___, ____, _____) async => selections++);
    final task = key.currentState!.translateCurrentPage(
        TranslationModeEnum.translationOnly,
        provider: PageTranslator());
    await tester.pumpAndSettle();
    await task;
    final field = find.byKey(const ValueKey('reflow-translated-text'));
    final controller = tester.widget<TextField>(field).controller!;
    final translated = controller.text;
    await tester.longPressAt(tester.getTopLeft(field) + const Offset(35, 12));
    await tester.pumpAndSettle();
    expect(controller.text, translated);
    expect(selections, 0);
    key.currentState!.clearSelection();
    await key.currentState!.readerAction('search');
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('reflow-search')), 'Translated');
    await tester.tap(find.byKey(const ValueKey('reflow-find-next')));
    await tester.pumpAndSettle();
    expect(controller.selection.textInside(controller.text), 'Translated');
    expect(controller.text, translated);
    key.currentState!.stopTranslation();
    await tester.pumpAndSettle();
    expect(text(tester), store.latest['0']!.text);
    expect(selections, 0);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [
    TranslationModeEnum.translationOnly,
    TranslationModeEnum.bilingual,
  ]) {
    for (final ocr in [false, true]) {
      testWidgets(
          'translated $mode OCR=$ocr uses shared selection and exact handle range',
          (tester) async {
        var originalSelections = 0;
        final selected = <String>[];
        final contexts = <String>[];
        final offsets = <int>[];
        await open(tester,
            ocr: ocr,
            selection: (_, __, ___, ____, _____) async => originalSelections++,
            translatedSelection: (value, context, rect, start) async {
              selected.add(value);
              contexts.add(context);
              offsets.add(start);
              expect(rect.isFinite, true);
            });
        final task = key.currentState!
            .translateCurrentPage(mode, provider: PageTranslator());
        await tester.pumpAndSettle();
        await task;
        final field = find.byKey(const ValueKey('reflow-translated-text'));
        final controller = tester.widget<TextField>(field).controller!;
        await tester
            .longPressAt(tester.getTopLeft(field) + const Offset(35, 12));
        await tester.pumpAndSettle();
        expect(selected, isNotEmpty);
        expect(selected.last, controller.selection.textInside(controller.text));
        expect(contexts.last, contains(selected.last));
        expect(offsets.last, controller.selection.start);
        expect(originalSelections, 0);
        expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
        final state =
            tester.state<EditableTextState>(find.byType(EditableText));
        expect(state.selectionOverlay?.handlesAreVisible, true);
        final start = controller.text.indexOf('Translated');
        final range =
            TextSelection(baseOffset: start + 1, extentOffset: start + 4);
        state.userUpdateTextEditingValue(
            controller.value.copyWith(selection: range),
            SelectionChangedCause.drag);
        await tester.pumpAndSettle();
        expect(controller.selection, range);
        expect(selected.last, 'ran');
        final source = key.currentState!.narrationSource!;
        source.seekToOffset(range.start);
        expect(source.currentText(), contains('Translated'));
        while (!source.atEnd) {
          source.nextText();
        }
        expect(pages, [0]); // Narration must not advance the original page.
        key.currentState!.stopTranslation();
        await tester.pumpAndSettle();
        expect(source.valid, false);
        expect(originalSelections, 0);
        expect(text(tester), store.latest['0']!.text);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'reflow keys precede text navigation but preserve selection and editor focus',
      (tester) async {
    final handled = <LogicalKeyboardKey>[];
    var eligibilityChanges = 0;
    await open(tester,
        comparison: true,
        keyboardEligibilityChanged: () => eligibilityChanges++,
        readerKeyEvent: (_, event) {
          if (event is! KeyDownEvent ||
              HardwareKeyboard.instance.isShiftPressed) {
            return KeyEventResult.ignored;
          }
          handled.add(event.logicalKey);
          return KeyEventResult.handled;
        });
    key.currentState!.requestKeyboardFocus();
    await tester.pump();
    expect(key.currentState!.canUseReadingKeys, true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(handled, [LogicalKeyboardKey.arrowRight]);
    final controller = tester
        .widget<TextField>(find.byKey(const ValueKey('reflow-text')))
        .controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(controller.selection.isCollapsed, false);
    expect(key.currentState!.canUseReadingKeys, false);
    expect(eligibilityChanges, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(handled, [LogicalKeyboardKey.arrowRight]);
    key.currentState!.clearSelection();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    expect(handled.last, LogicalKeyboardKey.pageDown);
    final context = tester.element(find.byType(DocumentReflowReader));
    unawaited(showDialog<void>(
        context: context,
        builder: (_) =>
            const AlertDialog(content: TextField(autofocus: true))));
    await tester.pumpAndSettle();
    expect(key.currentState!.canUseReadingKeys, false);
    await tester.enterText(find.byType(TextField).last, 'editing');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(
        handled, [LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.pageDown]);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
  });

  testWidgets('comparison toggle keeps loaded text, selection and reader state',
      (tester) async {
    var extracts = 0;
    bool? selected;
    Future<String> extract(int page) async {
      extracts++;
      return 'Comparison text for page $page';
    }

    await open(tester,
        extract: extract, onComparisonChanged: (value) => selected = value);
    final state = key.currentState;
    final controller = tester
        .widget<TextField>(find.byKey(const ValueKey('reflow-text')))
        .controller!;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 10);
    await tester.tap(find.byKey(const ValueKey('reflow-comparison')));
    expect(selected, true);
    await open(tester,
        comparison: true,
        extract: extract,
        onComparisonChanged: (value) => selected = value);
    expect(key.currentState, same(state));
    expect(extracts, 1);
    expect(controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 10));
    await tester.tap(find.byKey(const ValueKey('document-tools-menu')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SwitchListTile>(
                find.byKey(const ValueKey('reflow-comparison-switch')))
            .value,
        true);
  });

  testWidgets(
      'source page follows cached corrections without OCR or PDF navigation',
      (tester) async {
    await store.save(
        DocumentReflowPage(
            page: 1,
            ocr: true,
            rawText: 'old OCR',
            editedText: 'saved correction'),
        '');
    await open(tester);
    pages.clear();
    model.ready = false;
    await key.currentState!.followOriginalPage(1);
    await tester.pumpAndSettle();
    expect(text(tester), 'saved correction');
    expect(pages, isEmpty);
    await tester.tap(find.byKey(const ValueKey('reflow-next')));
    await tester.pumpAndSettle();
    expect(pages, [2]);
    expect(text(tester), contains('第2页'));
  });

  testWidgets(
      'rapid source turns discard stale results and never turn PDF back',
      (tester) async {
    final slow = Completer<String>();
    await open(tester,
        extract: (page) async => page == 1 ? slow.future : 'page $page');
    pages.clear();
    final first = key.currentState!.followOriginalPage(1);
    await tester.pump();
    expect(find.byKey(const ValueKey('reflow-text')), findsNothing);
    final last = key.currentState!.followOriginalPage(2);
    await tester.pump();
    slow.complete('stale page 1');
    await first;
    await last;
    await tester.pumpAndSettle();
    expect(text(tester), 'page 2');
    expect(pages, isEmpty);
  });

  testWidgets('failed source OCR does not retry on every relocation',
      (tester) async {
    var extracts = 0;
    await open(tester, extract: (page) async {
      extracts++;
      return page == 0 ? 'page zero' : '';
    });
    model.ready = false;
    await key.currentState!.followOriginalPage(1);
    await tester.pumpAndSettle();
    await key.currentState!.followOriginalPage(1);
    await tester.pumpAndSettle();
    expect(extracts, 2);
    expect(find.byKey(const ValueKey('reflow-text')), findsNothing);
    expect(pages, [0]);
  });

  testWidgets('rapid source backtracking keeps the last requested page',
      (tester) async {
    final slow = Completer<String>();
    await open(tester,
        extract: (page) async => page == 1 ? slow.future : 'page $page');
    pages.clear();
    final first = key.currentState!.followOriginalPage(1);
    await tester.pump();
    final second = key.currentState!.followOriginalPage(2);
    final back = key.currentState!.followOriginalPage(1);
    final home = key.currentState!.followOriginalPage(0);
    slow.complete('stale page');
    await Future.wait([first, second, back, home]);
    await tester.pumpAndSettle();
    expect(text(tester), 'page 0');
    expect(pages, isEmpty);
  });

  testWidgets('opening extraction cancels queued comparison loads as well',
      (tester) async {
    final slow = Completer<String>();
    final extracted = <int>[];
    await open(tester, extract: (page) async {
      extracted.add(page);
      return page == 1 ? slow.future : 'page $page';
    });
    final first = key.currentState!.followOriginalPage(1);
    await tester.pump();
    final queued = key.currentState!.followOriginalPage(2);
    final stop = key.currentState!.stopLoading();
    slow.complete('cancelled');
    await Future.wait([first, queued, stop]);
    await tester.pumpAndSettle();
    expect(extracted, [0, 1]);
    expect(pages, [0]);
  });

  testWidgets('returning from extraction resumes a cancelled comparison page',
      (tester) async {
    final slow = Completer<String>();
    var secondPageCalls = 0;
    await open(tester, extract: (page) async {
      if (page != 1) return 'page zero';
      return ++secondPageCalls == 1 ? slow.future : 'resumed page';
    });
    final load = key.currentState!.followOriginalPage(1);
    await tester.pump();
    final stop = key.currentState!.stopLoading();
    slow.complete('cancelled');
    await load;
    await stop;
    await key.currentState!.followOriginalPage(1);
    await tester.pumpAndSettle();
    expect(text(tester), 'resumed page');
    expect(secondPageCalls, 2);
    expect(pages, [0]);
  });

  testWidgets(
      'reflow keeps prefetch alive by original page and reuses in-flight OCR',
      (tester) async {
    final first = DocumentReflowPage(
        page: 0,
        ocr: true,
        rawText: List.filled(160, '很长的原书第一页正文。').join('\n\n'));
    await store.save(first, '');
    final finish = Completer<void>();
    final loaded = <int>[];
    var extracted = 0, cancelled = 0;
    final cache = DocumentOcrPrecache(
        canRun: () => true,
        cachedPages: (start, count) async => {
              for (var p = start; p < start + count; p++)
                if (store.latest.containsKey('$p')) p
            },
        load: (page, cancel) async {
          loaded.add(page);
          if (page == 1) await finish.future;
          cancel.check();
          await store.save(
              DocumentReflowPage(
                  page: page, ocr: true, rawText: '后台识别第${page + 1}页'),
              '',
              onlyIfAbsent: true);
        });
    cache.update(0, 3, totalPages: 3);
    await tester.pump(const Duration(milliseconds: 300));
    expect(loaded, [1]);
    await open(tester,
        precache: cache,
        cancelRender: () => cancelled++,
        extract: (_) async {
          extracted++;
          return '不应重复识别';
        },
        sourcePageChanged: (page, total) =>
            cache.update(page, 3, totalPages: total));
    expect(text(tester), first.text);
    expect(cache.running, isTrue);
    final scroll = key.currentState!.turn(1);
    await tester.pumpAndSettle();
    await scroll;
    expect(cache.startPage, 0); // One reflow screen is not one source page.
    final next = key.currentState!.turnOriginalPage(1);
    await tester.pump();
    expect(loaded, [1]);
    expect(extracted, 0);
    finish.complete();
    await tester.pumpAndSettle();
    await next;
    expect(text(tester), '后台识别第2页');
    expect(cache.startPage, 1);
    expect(cache.total, 2);
    expect(extracted, 0);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(loaded, [1, 2]);
    expect(cache.completed, 2);
    await tester.pumpWidget(const SizedBox());
    expect(cancelled,
        0); // Leaving cached text must not cancel background rendering.
    cache.dispose();
  });

  test('reflow defaults to justification and preserves explicit left alignment',
      () {
    expect(const DocumentTextStyle().alignment, TextAlign.justify);
    expect(DocumentTextStyle.fromJson({}).alignment, TextAlign.justify);
    expect(
        DocumentTextStyle.fromJson({'size': 30}).alignment, TextAlign.justify);
    expect(DocumentTextStyle.fromJson({'justify': false}).alignment,
        TextAlign.start);
  });

  for (final (width, size, margin) in [
    (360.0, 20.0, 20.0),
    (360.0, 32.0, 20.0),
    (800.0, 32.0, 20.0),
    (390.0, 28.0, 0.0),
    (600.0, 24.0, 40.0),
  ]) {
    testWidgets(
        'Chinese reflow justification fills available width: $width/$size',
        (tester) async {
      final loader = FontLoader('SourceHanSerif')
        ..addFont(rootBundle.load('assets/fonts/SourceHanSerifSC-Regular.otf'));
      await loader.load();
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await open(tester,
          ocr: true,
          recognize: () async =>
              '${List.filled(8, '有机结合起来，坚持把国家层面民主制度同基层民主制度有机结合起来。').join()}\n\n　　段末自然收尾。',
          initialStyle:
              DocumentTextStyle(size: size, serif: true, margin: margin));
      final editable = tester
          .state<EditableTextState>(find.descendant(
              of: find.byKey(const ValueKey('reflow-text')),
              matching: find.byType(EditableText)))
          .renderEditable;
      final boxes = editable.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text(tester).length));
      final left = editable.localToGlobal(Offset(boxes.first.left, 0)).dx;
      final right = editable.localToGlobal(Offset(boxes.first.right, 0)).dx;
      expect(left, closeTo(margin, 1));
      expect(width - right, closeTo(margin, 3));
      expect(editable.size.width - boxes.first.right, lessThanOrEqualTo(3));
    });
    testWidgets(
        'reflow uses symmetric margins and fills wrapped lines: $width/$size',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final content =
          '${List.filled(12, '有机结合起来，坚持把国家层面民主制度同基层民主制度有机结合起来。').join()}\n\n　　段末自然收尾。';
      await open(tester,
          extract: (_) async => content,
          initialStyle: DocumentTextStyle(size: size, margin: margin));
      final field = find.byKey(const ValueKey('reflow-text'));
      final bounds = tester.getRect(field);
      expect(bounds.left, closeTo(margin, .01));
      expect(width - bounds.right, closeTo(margin, .01));
      final editable = tester
          .state<EditableTextState>(
              find.descendant(of: field, matching: find.byType(EditableText)))
          .renderEditable;
      final boxes = editable.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text(tester).length));
      expect(boxes.length, greaterThan(2));
      expect(boxes.first.left, closeTo(0, .01));
      // EditableText reserves a small cursor gap even for read-only text.
      expect(editable.size.width - boxes.first.right, lessThanOrEqualTo(3));
      expect(text(tester), endsWith('　　段末自然收尾。'));
    });
  }

  for (final ocr in [false, true]) {
    testWidgets(
        'selection narration rejects stale and original anchors: OCR=$ocr',
        (tester) async {
      await open(tester, ocr: ocr);
      final page = store.latest['0']!;
      final anchor = page.anchor(0, 2);
      final source = key.currentState!.narrationSourceFor(anchor);
      expect(source, same(key.currentState!.narrationSource));
      expect(
          key.currentState!.narrationSourceFor(
              DocumentReflowAnchor.parse(anchor.originalReference)!),
          isNull);
      final stale = DocumentReflowPage(page: 0, ocr: ocr, rawText: '旧识别结果');
      expect(key.currentState!.narrationSourceFor(stale.anchor(0, 2)), isNull);
      await key.currentState!.turnOriginalPage(1);
      await tester.pumpAndSettle();
      expect(source!.valid, isFalse);
      expect(key.currentState!.narrationSourceFor(anchor), isNull);
    });

    testWidgets(
        'speech highlight preserves reflow text and selection: OCR=$ocr',
        (tester) async {
      await open(tester, ocr: ocr);
      final field =
          tester.widget<TextField>(find.byKey(const ValueKey('reflow-text')));
      final controller = field.controller!;
      final original = controller.text;
      const selection = TextSelection(baseOffset: 0, extentOffset: 2);
      controller.selection = selection;
      final source = key.currentState!.narrationSource!;
      String highlightedText() => controller
          .buildTextSpan(
              context: tester.element(find.byType(EditableText)),
              style: const TextStyle(),
              withComposing: false)
          .children!
          .whereType<TextSpan>()
          .where(
              (span) => span.style?.backgroundColor == const Color(0x8339c5bc))
          .map((span) => span.text)
          .join();
      final first = source.currentText();
      await tester.pump();
      expect(highlightedText(), first);
      final second = source.nextText();
      await tester.pump();
      expect(highlightedText(), second);
      expect(controller.selection, selection);
      expect(controller.text, original);
      source.clearHighlight();
      await tester.pump();
      expect(highlightedText(), isEmpty);
      source.showCurrent();
      expect(highlightedText(), second);
      while (source.nextText().isNotEmpty) {}
      expect(highlightedText(), isEmpty);
      expect(pages, [0]);
      source.currentText();
      await key.currentState!.turnOriginalPage(1);
      await tester.pumpAndSettle();
      expect(highlightedText(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'reflow exposes a bounded page source to the shared host: OCR=$ocr',
        (tester) async {
      final invalidated = <TtsPageSource>[];
      await open(tester, ocr: ocr, narrationInvalidated: invalidated.add);
      final source = key.currentState!.narrationSource!;
      expect(source.collect(100).map((s) => s.text).join(),
          text(tester).replaceAll(RegExp(r'\s+'), ''));
      expect(key.currentState!.narrationSource, same(source));
      // The standalone fixture does not add a second narration menu.
      expect(
          tester
              .widget<DocumentReaderSurface>(find.byType(DocumentReaderSurface))
              .narration,
          isNull);
      expect(find.byTooltip('Read aloud'), findsNothing);
      expect(find.byKey(const ValueKey('document-style-menu')), findsOneWidget);
      expect(text(tester), isNotEmpty);
      while (source.nextText().isNotEmpty) {}
      expect(pages, [0]);
      await key.currentState!.turnOriginalPage(1);
      await tester.pumpAndSettle();
      expect(source.valid, isFalse);
      expect(invalidated, [source]);
      final next = key.currentState!.narrationSource!;
      expect(next, isNot(same(source)));
      await tester.pumpWidget(const SizedBox());
      expect(next.valid, isFalse);
      expect(invalidated, [source, next]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'embedded reflow delegates menus to ebook host without duplicate chrome',
      (tester) async {
    Prefs().pageTurnMode = 'custom';
    Prefs().customPageTurnConfig = List.filled(9, 3);
    var opened = 0, closed = 0;
    final panels = <Widget>[];
    await open(tester,
        openReaderMenu: () => opened++,
        openReaderPanel: panels.add,
        closeReaderMenu: () => closed++);
    expect(find.byKey(const ValueKey('reflow-original')), findsOneWidget);
    expect(find.byKey(const ValueKey('reflow-mode')), findsOneWidget);
    expect(find.byKey(const ValueKey('reflow-more')), findsNothing);
    expect(find.byKey(const ValueKey('document-reader-toolbar')), findsNothing);
    expect(find.byIcon(Icons.settings), findsNothing);
    key.currentState!.openStyleMenu();
    key.currentState!.openToolsMenu();
    await key.currentState!.readerAction('search');
    await tester.pumpAndSettle();
    expect(panels.length, 3);
    expect(find.byType(BottomSheet), findsNothing);
    key.currentState!.closeMenu();
    expect(closed, 1);
    await tester.tapAt(
        tester.getBottomRight(find.byKey(const ValueKey('reflow-text'))) +
            const Offset(-8, 80));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  for (final ocr in [false, true]) {
    testWidgets(
        'embedded original-page arrows automatically reflow and reuse cache ($ocr)',
        (tester) async {
      var extracted = 0, recognized = 0;
      final rendered = <int>[];
      await open(tester,
          ocr: ocr,
          openReaderMenu: () {},
          extract: (page) async {
            extracted++;
            return 'Text page $page';
          },
          renderRequest: (request) => rendered.add(request['page'] as int),
          recognize: () async => 'OCR page ${recognized++}');
      final first = text(tester);
      await tester.tap(find.byKey(const ValueKey('reflow-next')));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(text(tester), isNot(first));
      await tester.tap(find.byKey(const ValueKey('reflow-previous')));
      await tester.pumpAndSettle();
      expect(text(tester), first);
      expect(find.text('1 / 3'), findsOneWidget);
      expect(extracted, ocr ? 0 : 2);
      expect(recognized, ocr ? 2 : 0);
      expect(rendered, ocr ? [0, 1] : isEmpty);
      expect(pages, [0, 1, 0]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ebook progress arrows also navigate original PDF pages',
      (tester) async {
    var extractions = 0;
    await open(tester, openReaderMenu: () {}, extract: (page) async {
      extractions++;
      return List.filled(80, 'Page $page has many reflow lines.').join('\n\n');
    });
    final entry = OverlayEntry(
        builder: (_) => Align(
            alignment: Alignment.bottomCenter,
            child: Material(
                child: SizedBox(
                    width: 500, child: key.currentState!.progressPanel()))));
    Overlay.of(key.currentContext!).insert(entry);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reader-next-page')));
    await tester.pumpAndSettle();
    expect(pages, [0, 1],
        reason: 'Advance the source page, not a screen of reflow text');
    expect(text(tester), startsWith('Page 1'));
    await tester.tap(find.byKey(const ValueKey('reader-previous-page')));
    await tester.pumpAndSettle();
    expect(pages, [0, 1, 0]);
    expect(extractions, 2);
    entry.remove();
    entry.dispose();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('more tools stay in the header, outside ebook bottom buttons',
      (tester) async {
    await open(tester);
    final more = find.byKey(const ValueKey('reflow-more'));
    final original = find.byKey(const ValueKey('reflow-original'));
    final toolbar = find.byKey(const ValueKey('document-reader-toolbar'));
    expect(tester.getCenter(more).dy, tester.getCenter(original).dy);
    expect(find.descendant(of: toolbar, matching: more), findsNothing);
    expect(
        tester.getCenter(more).dx, greaterThan(tester.getCenter(original).dx));
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('Search this page'), findsOneWidget);
    expect(find.text('Copy selection / page'), findsOneWidget);
  });

  testWidgets('reflow menu queries, drafts and bookmarks visible text',
      (tester) async {
    final queried = <String>[], drafts = <String>[];
    DocumentReflowAnchor? saved;
    await open(tester,
        query: (text, context, translation) async {
          queried.add('$translation:$text');
          expect(context, contains(text));
        },
        draft: (text) async => drafts.add(text),
        bookmark: (anchor, text) async => saved = anchor);
    Future<void> choose(String label) async {
      await tester.tap(find.byTooltip('More reading tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await choose('Translate');
    expect(queried, ['true:${text(tester)}']);
    await choose('AI chat');
    expect(drafts, [text(tester)]);
    await choose('Add bookmark');
    expect(saved!.page, 0);
    expect(saved!.matches(store.revisions.values.single), true);
    expect(pages, [0], reason: 'Actions never navigate the hidden PDF');
  });

  testWidgets('explicit recognition keeps the older annotated revision',
      (tester) async {
    var calls = 0;
    await open(tester,
        ocr: true, recognize: () async => ++calls == 1 ? '原识别朱熹' : '新识别朱喜');
    final original = store.revisions.values.single;
    final anchor = original.anchor(0, 3);
    await tester.tap(find.byKey(const ValueKey('document-tools-menu')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Recognize this page again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recognize this page again'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.byKey(const ValueKey('confirm-page-recognition')));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(text(tester), '新识别朱喜');
    expect((await store.readAnchor(anchor))!.text, '原识别朱熹');
    expect(store.revisions.length, 2);
  });

  testWidgets(
      'editing saves literal paragraphs and survives reopening and mode changes',
      (tester) async {
    var calls = 0;
    await open(tester, ocr: true, recognize: () async {
      calls++;
      return '原文';
    });
    await tester.tap(find.byKey(const ValueKey('document-tools-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-saved-page')));
    await tester.pumpAndSettle();
    const correction = '校对异体字𠀀\n\n保留手动分段';
    await tester.enterText(
        find.byKey(const ValueKey('saved-page-editor')), correction);
    await tester.tap(find.byKey(const ValueKey('save-page-edit')));
    await tester.pumpAndSettle();
    expect(text(tester), correction);
    expect(calls, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    model.ready = false;
    await open(tester,
        extract: (_) async => throw StateError('must use saved text'));
    expect(text(tester), correction);
    expect(store.revisions.length, 2);
  });

  testWidgets('cancel and failed re-recognition preserve the edited page',
      (tester) async {
    final original = DocumentReflowPage(page: 0, ocr: true, rawText: '原文');
    await store.save(original, '');
    final edited = await store.saveEdit(original, '校对稿');
    var calls = 0;
    await open(tester, ocr: true, recognize: () async {
      calls++;
      throw StateError('recognition failed');
    });
    Future<void> confirm() async {
      if (find.text('Recognize this page again').evaluate().isEmpty) {
        await tester.tap(find.byKey(const ValueKey('document-tools-menu')));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Recognize this page again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recognize this page again'));
      await tester.pumpAndSettle();
    }

    await confirm();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(text(tester), '校对稿');
    await confirm();
    await tester.tap(find.byKey(const ValueKey('confirm-page-recognition')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(store.latest['0']!.revision, edited.revision);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await open(tester, ocr: true);
    expect(text(tester), '校对稿');
  });

  testWidgets('empty edits remain in the editor without replacing saved text',
      (tester) async {
    await open(tester);
    final original = text(tester);
    await tester.tap(find.byKey(const ValueKey('document-tools-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-saved-page')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('saved-page-editor')), '  ');
    await tester.tap(find.byKey(const ValueKey('save-page-edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('saved-page-editor')), findsOneWidget);
    expect(store.latest['0']!.text, original);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(text(tester), original);
  });

  testWidgets('jump and page search operate within reflow', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Go to original page'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        '3');
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(text(tester), startsWith('第2页'));
    await tester.tap(find.byTooltip('More reading tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search this page'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('reflow-search')), '下一段');
    await tester.tap(find.byKey(const ValueKey('reflow-find-next')));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<TextField>(find.byKey(const ValueKey('reflow-text')))
        .controller!;
    expect(controller.selection.textInside(controller.text), '下一段');
    expect(pages, [0, 2]);
  });

  for (final chinese in [false, true]) {
    testWidgets(
        'auto scroll uses reading-rate multipliers without reflow (Chinese=$chinese)',
        (tester) async {
      var reads = 0, stopped = 0;
      await open(tester, extract: (_) async {
        reads++;
        return List.generate(100, (i) => chinese ? '甲乙丙' : 'Paragraph $i.')
            .join('\n\n');
      });
      final field = find.byKey(const ValueKey('reflow-text'));
      final initial = tester.widget<TextField>(field);
      final scroll = tester
          .widget<SingleChildScrollView>(find
              .ancestor(of: field, matching: find.byType(SingleChildScrollView))
              .first)
          .controller!;
      final reader = key.currentState!;
      Prefs().pageTurnStyle = PageTurn.slide;
      expect(reader.startAutoScroll(2, () => stopped++), isTrue);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final base = (scroll.position.maxScrollExtent +
              scroll.position.viewportDimension) /
          60;
      expect(scroll.offset, closeTo(base, .01));
      final fasterOffset = scroll.offset;
      expect(reader.startAutoScroll(1, () => stopped++), isTrue);
      await tester.pump(const Duration(milliseconds: 100));
      expect(scroll.offset - fasterOffset, closeTo(base * .1, .01));
      expect(
          tester.widget<TextField>(field).controller, same(initial.controller));
      expect(tester.widget<TextField>(field).style, initial.style);
      expect(reads, 1);
      expect(pages, [0]);
      expect(Prefs().pageTurnStyle, PageTurn.slide);
      reader.stopAutoScroll();
      reader.stopAutoScroll();
      expect(stopped, 1);
      final offset = scroll.offset;
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, offset);
    });
  }

  testWidgets('a reader tap reveals controls while reflow keeps scrolling',
      (tester) async {
    Prefs().pageTurnStyle = PageTurn.scroll;
    var stopped = 0, taps = 0, menus = 0;
    await open(tester,
        readerTap: () {
          taps++;
          return true;
        },
        openReaderMenu: () => menus++,
        extract: (_) async =>
            List.generate(100, (i) => 'Paragraph $i.').join('\n\n'));
    final field = find.byKey(const ValueKey('reflow-text'));
    final viewport = find
        .ancestor(of: field, matching: find.byType(SingleChildScrollView))
        .first;
    final scroll = tester.widget<SingleChildScrollView>(viewport).controller!;
    expect(key.currentState!.startAutoScroll(1, () => stopped++), isTrue);
    await tester.pump();
    await tester.tapAt(tester.getCenter(viewport));
    await tester.pump(const Duration(milliseconds: 350));
    expect(taps, 1);
    expect(menus, 0);
    expect(stopped, 0);
    final offset = scroll.offset;
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.offset, greaterThan(offset));
    key.currentState!.stopAutoScroll();
    expect(stopped, 1);
  });

  testWidgets('auto scroll reestimates the reading rate after width changes',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Prefs().pageTurnStyle = PageTurn.scroll;
    var reads = 0, stopped = 0;
    await open(tester, extract: (_) async {
      reads++;
      return List.filled(600, 'word').join(' ');
    });
    final field = find.byKey(const ValueKey('reflow-text'));
    final original = tester.widget<TextField>(field);
    final scroll = tester
        .widget<SingleChildScrollView>(find
            .ancestor(of: field, matching: find.byType(SingleChildScrollView))
            .first)
        .controller!;
    final wideRate =
        (scroll.position.maxScrollExtent + scroll.position.viewportDimension) /
            180;
    expect(key.currentState!.startAutoScroll(1, () => stopped++), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.offset, closeTo(wideRate * .1, .01));
    tester.view.physicalSize = const Size(400, 600);
    await tester.pump();
    final narrowRate =
        (scroll.position.maxScrollExtent + scroll.position.viewportDimension) /
            180;
    expect(narrowRate, greaterThan(wideRate));
    final offset = scroll.offset;
    await tester.pump(const Duration(milliseconds: 100));
    expect(scroll.offset - offset, closeTo(narrowRate * .1, .01));
    expect(
        tester.widget<TextField>(field).controller, same(original.controller));
    expect(reads, 1);
    expect(pages, [0]);
    expect(stopped, 0);
    key.currentState!.stopAutoScroll();
  });

  testWidgets('auto scroll loads newly visible translations without repeats',
      (tester) async {
    Prefs().pageTurnStyle = PageTurn.scroll;
    var stopped = 0, reads = 0;
    await open(tester, extract: (_) async {
      reads++;
      return List.generate(
              30,
              (i) =>
                  'Paragraph $i. ${List.filled(15, 'Source text for testing.').join(' ')}')
          .join('\n\n');
    });
    final provider = PageTranslator();
    final task = key.currentState!.translateCurrentPage(
        TranslationModeEnum.translationOnly,
        provider: provider);
    await tester.pumpAndSettle();
    await task;
    final requests = provider.requests.length;
    expect(key.currentState!.startAutoScroll(4, () => stopped++), isTrue);
    await tester.pump();
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(provider.requests.length, greaterThan(requests));
    expect(provider.requests.toSet().length, provider.requests.length);
    expect(stopped, 0);
    expect(reads, 1);
    expect(pages, [0]);
    key.currentState!.stopAutoScroll();
    key.currentState!.stopTranslation();
    await tester.pumpAndSettle();
  });

  for (final operation in ['drag', 'wheel', 'selection', 'menu', 'navigate']) {
    testWidgets('manual $operation stops reflow auto scroll once',
        (tester) async {
      Prefs().pageTurnStyle = PageTurn.scroll;
      await open(tester,
          extract: (_) async =>
              List.generate(100, (i) => 'Paragraph $i.').join('\n\n'));
      final field = find.byKey(const ValueKey('reflow-text'));
      final viewport = find
          .ancestor(of: field, matching: find.byType(SingleChildScrollView))
          .first;
      final scroll = tester.widget<SingleChildScrollView>(viewport).controller!;
      var stopped = 0;
      expect(key.currentState!.startAutoScroll(1, () => stopped++), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      switch (operation) {
        case 'drag':
          final gesture = await tester.startGesture(tester.getCenter(viewport));
          await gesture.moveBy(const Offset(0, -40));
          await gesture.cancel();
        case 'wheel':
          await tester.sendEventToBinding(PointerScrollEvent(
              position: tester.getCenter(viewport),
              scrollDelta: const Offset(0, 20)));
        case 'selection':
          tester.widget<TextField>(field).controller!.selection =
              const TextSelection(baseOffset: 0, extentOffset: 4);
        case 'menu':
          key.currentState!.openStyleMenu();
        case 'navigate':
          await key.currentState!.goToPage(1);
      }
      await tester.pumpAndSettle();
      expect(stopped, 1);
      final offset = scroll.offset;
      await tester.pump(const Duration(milliseconds: 300));
      expect(scroll.offset, offset);
      key.currentState!.stopAutoScroll();
      expect(stopped, 1);
    });
  }

  testWidgets(
      'auto scroll stops at reflow page end without loading another page',
      (tester) async {
    Prefs().pageTurnStyle = PageTurn.scroll;
    var reads = 0, stopped = 0;
    await open(tester, extract: (_) async {
      reads++;
      return List.generate(100, (i) => 'Paragraph $i.').join('\n\n');
    });
    final field = find.byKey(const ValueKey('reflow-text'));
    final scroll = tester
        .widget<SingleChildScrollView>(find
            .ancestor(of: field, matching: find.byType(SingleChildScrollView))
            .first)
        .controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent - 2);
    expect(key.currentState!.startAutoScroll(1, () => stopped++), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(stopped, 1);
    expect(scroll.offset, scroll.position.maxScrollExtent);
    expect(pages, [0]);
    expect(reads, 1);
    expect(key.currentState!.startAutoScroll(1, () => stopped++), isFalse);
    expect(stopped, 1);
  });

  testWidgets('ebook mode changes preserve reflow scrolling until disposal',
      (tester) async {
    Prefs().pageTurnStyle = PageTurn.scroll;
    await open(tester,
        extract: (_) async =>
            List.generate(100, (i) => 'Paragraph $i.').join('\n\n'));
    var stopped = 0;
    expect(key.currentState!.startAutoScroll(1, () => stopped++), isTrue);
    await tester.pump();
    Prefs().pageTurnStyle = PageTurn.noAnimation;
    await tester.pump(const Duration(milliseconds: 20));
    expect(stopped, 0);
    expect(Prefs().pageTurnStyle, PageTurn.noAnimation);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(stopped, 1);
    expect(tester.takeException(), isNull);
  });

  for (final comparison in [false, true]) {
    testWidgets(
        'comparison=$comparison relays PDF wheel without resizing reflow',
        (tester) async {
      final zooms = <int>[];
      var allowed = true;
      await open(tester,
          comparison: comparison,
          pdfWheelZoom: zooms.add,
          wheelZoomAllowed: () => allowed,
          extract: (_) async =>
              List.generate(80, (i) => 'Paragraph $i.').join('\n\n'));
      final field = find.byKey(const ValueKey('reflow-text'));
      final viewport = find
          .ancestor(of: field, matching: find.byType(SingleChildScrollView))
          .first;
      final scroll = tester.widget<SingleChildScrollView>(viewport).controller!;
      scroll.jumpTo(200);
      await tester.pumpAndSettle();
      final before = scroll.offset;
      final textField = tester.widget<TextField>(field);
      final modifier = Platform.isMacOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      Future<void> wheel(double delta) async {
        await tester.sendEventToBinding(PointerScrollEvent(
            position: tester.getCenter(viewport),
            scrollDelta: Offset(0, delta)));
        await tester.pumpAndSettle();
      }

      await tester.sendKeyDownEvent(modifier);
      try {
        await wheel(-100);
        await wheel(100);
        expect(zooms, comparison ? [1, -1] : isEmpty);
        if (comparison) expect(scroll.offset, before);
        allowed = false;
        await wheel(100);
        expect(zooms, comparison ? [1, -1] : isEmpty);
      } finally {
        await tester.sendKeyUpEvent(modifier);
      }
      expect(tester.widget<TextField>(field).style!.fontSize,
          textField.style!.fontSize);
      expect(tester.widget<TextField>(field).controller,
          same(textField.controller));
      expect(pages, [0]);
    });
  }

  testWidgets('comparison PDF wheel burst keeps one trailing zoom',
      (tester) async {
    final zooms = <int>[];
    var allowed = true;
    await open(tester,
        comparison: true,
        pdfWheelZoom: zooms.add,
        wheelZoomAllowed: () => allowed,
        extract: (_) async =>
            List.generate(80, (i) => 'Paragraph $i.').join('\n\n'));
    final field = find.byKey(const ValueKey('reflow-text'));
    final viewport = find
        .ancestor(of: field, matching: find.byType(SingleChildScrollView))
        .first;
    final scroll = tester.widget<SingleChildScrollView>(viewport).controller!;
    scroll.jumpTo(200);
    await tester.pumpAndSettle();
    final before = scroll.offset;
    final fontSize = tester.widget<TextField>(field).style!.fontSize;
    final modifier = Platform.isMacOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    Future<void> wheel(double delta) =>
        tester.sendEventToBinding(PointerScrollEvent(
            position: tester.getCenter(viewport),
            scrollDelta: Offset(0, delta)));

    await tester.sendKeyDownEvent(modifier);
    try {
      await wheel(-100);
      for (var i = 0; i < 10; i++) {
        await wheel(100);
      }
      expect(zooms, [1]);
      await tester.pump(const Duration(milliseconds: 79));
      expect(zooms, [1]);
      await tester.pump(const Duration(milliseconds: 1));
      expect(zooms, [1, -1]);
      expect(scroll.offset, before);
      expect(tester.widget<TextField>(field).style!.fontSize, fontSize);
      expect(pages, [0]);

      await wheel(-100);
      allowed = false;
      await tester.pump(const Duration(milliseconds: 80));
      expect(zooms, [1, -1]);

      allowed = true;
      await wheel(-100);
      await wheel(-100);
      expect(zooms, [1, -1, 1]);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 160));
      expect(zooms, [1, -1, 1]);
    } finally {
      await tester.sendKeyUpEvent(modifier);
    }
  });

  testWidgets(
      'bottom style updates reflow without rereading or changing source page',
      (tester) async {
    var reads = 0;
    await open(tester, extract: (_) async {
      reads++;
      return 'Reflow text';
    });
    final field = find.byKey(const ValueKey('reflow-text'));
    final before = tester.widget<TextField>(field).controller;
    await tester.tap(find.byKey(const ValueKey('document-style-menu')));
    await tester.pumpAndSettle();
    expect(find.byType(StyleWidget), findsOneWidget);
    expect(find.byKey(const ValueKey('ocr-style-preview')), findsNothing);
    tester
        .widget<Slider>(find.byKey(const ValueKey('ocr-style-size')))
        .onChanged!(28);
    await tester.pump();
    tester
        .widget<Slider>(find.byKey(const ValueKey('ocr-style-size')))
        .onChangeEnd!(28);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).style!.fontSize, 28);
    expect(tester.widget<TextField>(field).controller, same(before));
    expect(reads, 1);
    expect(pages, [0]);
    await tester.tap(find.byTooltip('Hide menu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reflow-original')).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('OCR style gear uses ebook settings and updates only reflow',
      (tester) async {
    var reads = 0;
    await open(tester, ocr: true, recognize: () async {
      reads++;
      return '第一段正文。\n\n　　第二段正文。';
    });
    final field = find.byKey(const ValueKey('reflow-text'));
    final controller = tester.widget<TextField>(field).controller;
    final original = controller!.text;
    final ebookMargin = Prefs().bookStyle.sideMargin;
    await tester.tap(find.byKey(const ValueKey('document-style-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderMoreSettings), findsOneWidget);
    expect(find.byType(Tab), findsNWidgets(4));
    expect(find.byKey(const ValueKey('ocr-style-preview')), findsNothing);
    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    final sliders = find.descendant(
        of: find.byType(StyleSettings), matching: find.byType(Slider));
    expect(tester.widget<Slider>(sliders.at(0)).onChanged, isNull);
    expect(tester.widget<Slider>(sliders.at(5)).onChanged, isNull);
    for (final change in {1: 10.0, 2: 40.0, 3: 80.0, 4: -2.0}.entries) {
      tester.widget<Slider>(sliders.at(change.key)).onChanged!(change.value);
      await tester.pump();
      tester.widget<Slider>(sliders.at(change.key)).onChangeEnd!(change.value);
      await tester.pumpAndSettle();
    }
    final scroll = tester.widget<SingleChildScrollView>(find
        .ancestor(of: field, matching: find.byType(SingleChildScrollView))
        .first);
    final width = MediaQuery.sizeOf(tester.element(field)).width;
    expect(scroll.padding, EdgeInsets.fromLTRB(width * .1, 40, width * .1, 80));
    expect(tester.widget<TextField>(field).style!.letterSpacing, -2);
    for (final alignment in [
      TextAlignmentEnum.right,
      TextAlignmentEnum.center,
      TextAlignmentEnum.left,
      TextAlignmentEnum.justify
    ]) {
      final dropdown = find.byType(DropdownMenu<TextAlignmentEnum>);
      final label = tester
          .widget<DropdownMenu<TextAlignmentEnum>>(dropdown)
          .dropdownMenuEntries
          .firstWhere((entry) => entry.value == alignment)
          .label;
      await tester.ensureVisible(dropdown);
      await tester
          .tap(find.descendant(of: dropdown, matching: find.byType(TextField)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field).textAlign,
          DocumentTextStyle(textAlignment: alignment.code).alignment);
      final editable = tester
          .state<EditableTextState>(
              find.descendant(of: field, matching: find.byType(EditableText)))
          .renderEditable;
      final box = editable
          .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 1))
          .first;
      expect(
          box.left,
          alignment == TextAlignmentEnum.left ||
                  alignment == TextAlignmentEnum.justify
              ? closeTo(-1, .01)
              : greaterThan(50));
    }
    expect(Prefs().bookStyle.sideMargin, ebookMargin);
    await tester.tap(find.byType(CloseButton).last);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller, same(controller));
    expect(controller.text, original);
    expect(reads, 1);
    expect(pages, [0]);
    expect(tester.takeException(), isNull);
  });

  Offset textPoint(WidgetTester tester, int offset) {
    final render = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
    return render.localToGlobal(caret.center + const Offset(2, 0));
  }

  bool quickMarkPreview(WidgetTester tester) {
    final field = find.byKey(const ValueKey('reflow-text'));
    final controller = tester.widget<TextField>(field).controller!;
    return controller
        .buildTextSpan(context: tester.element(field), withComposing: false)
        .children!
        .cast<TextSpan>()
        .any((span) => span.style?.backgroundColor != null);
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
        'quick mark previews a touch drag and submits on release ($platform)',
        (tester) async {
      var selected = 0, submitted = 0;
      DocumentReflowAnchor? saved;
      String? content;
      final pending = Completer<void>();
      await open(tester,
          quickMarkEnabled: true,
          extract: (_) async =>
              List.generate(80, (i) => '第$i段，快速标记测试文字。').join('\n\n'),
          selection: (a, t, c, r, ids) async => selected++,
          quickMark: (anchor, text, context, rect) async {
            submitted++;
            saved = anchor;
            content = text;
            expect(context, contains(text));
            expect(rect.width, greaterThan(0));
            expect(rect.height, greaterThan(0));
            await pending.future;
          });
      final field = find.byKey(const ValueKey('reflow-text'));
      final controller = tester.widget<TextField>(field).controller!;
      final viewport = find
          .ancestor(of: field, matching: find.byType(SingleChildScrollView))
          .first;
      final scroll = tester.widget<SingleChildScrollView>(viewport).controller!;
      final page = key.currentState!.quickMarkPage!;
      final end = controller.text.indexOf('第2段') + 3;
      final source = key.currentState!.narrationSource!;
      expect(key.currentState!.canQuickMark, isTrue);
      final drag = await tester.startGesture(textPoint(tester, 2));
      await drag.moveTo(textPoint(tester, end));
      await tester.pump();
      expect(quickMarkPreview(tester), isTrue);
      expect(controller.selection.isCollapsed, isTrue);
      expect(scroll.offset, 0);
      expect(submitted, 0);
      await drag.up();
      await tester.pump();
      expect(submitted, 1);
      expect(saved!.matches(page), isTrue);
      expect(saved!.start, 2);
      expect(saved!.end, end);
      expect(content, controller.text.substring(2, end));
      expect(selected, 0);
      expect(pages, [0]);
      expect(source.valid, isTrue);
      expect(quickMarkPreview(tester), isTrue);
      pending.complete();
      await tester.pump();
      expect(quickMarkPreview(tester), isFalse);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({platform}));
  }

  testWidgets(
      'quick mark taps open the menu without notes, selection or paging',
      (tester) async {
    var submitted = 0, selected = 0, menus = 0;
    await open(tester,
        quickMarkEnabled: true,
        openReaderMenu: () => menus++,
        quickMark: (a, t, c, r) async => submitted++,
        selection: (a, t, c, r, ids) async => selected++);
    await tester.tapAt(textPoint(tester, 1));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.longPressAt(textPoint(tester, 1));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byKey(const ValueKey('reflow-mode')));
    await tester.pump();
    expect(submitted, 0);
    expect(selected, 0);
    expect(menus, 2);
    expect(pages, [0]);
    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('reflow-text')));
    expect(field.controller!.selection.isCollapsed, isTrue);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  for (final interruption in [
    'cancel',
    'disable',
    'navigate',
    'translation',
    'dispose'
  ]) {
    testWidgets('quick mark discards a stroke after $interruption',
        (tester) async {
      var submitted = 0, unavailable = 0;
      Future<void> submit(
          DocumentReflowAnchor a, String t, String c, Rect r) async {
        submitted++;
      }

      await open(tester,
          quickMarkEnabled: true,
          quickMark: submit,
          quickMarkUnavailable: () => unavailable++,
          extract: (_) async => '快速标记测试文字，下一段继续。');
      final drag = await tester.startGesture(textPoint(tester, 1));
      await drag.moveTo(textPoint(tester, 8));
      await tester.pump();
      expect(quickMarkPreview(tester), isTrue);
      switch (interruption) {
        case 'cancel':
          await drag.cancel();
        case 'disable':
          await drag.up();
          await open(tester, quickMarkEnabled: false, quickMark: submit);
        case 'navigate':
          await key.currentState!.goToPage(1);
          await drag.up();
        case 'translation':
          await key.currentState!.translateCurrentPage(
              TranslationModeEnum.translationOnly,
              provider: PageTranslator());
          await drag.up();
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
          await drag.up();
      }
      await tester.pumpAndSettle();
      expect(submitted, 0);
      expect(tester.takeException(), isNull);
      if (interruption == 'translation') {
        expect(unavailable, 1);
        expect(key.currentState!.canQuickMark, isFalse);
        expect(key.currentState!.quickMarkPage, isNull);
        expect(find.byKey(const ValueKey('reflow-quick-mark')), findsNothing);
      } else if (interruption != 'dispose') {
        expect(quickMarkPreview(tester), isFalse);
      }
      if (interruption == 'navigate') {
        expect(
            tester
                .widget<DocumentReflowReader>(find.byType(DocumentReflowReader))
                .quickMarkEnabled,
            isTrue);
        final next = await tester.startGesture(textPoint(tester, 1));
        await next.moveTo(textPoint(tester, 8));
        await next.up();
        await tester.pumpAndSettle();
        expect(submitted, 1);
        expect(pages, [0, 1]);
      }
    }, variant: TargetPlatformVariant({TargetPlatform.android}));
  }

  testWidgets('quick mark preserves source offsets when text is filtered',
      (tester) async {
    await Prefs().saveCustomCssProfile(
        0, const CustomCssProfile(pattern: '广告', filterMode: 'text'));
    await Prefs().saveCustomCssSelection(
        const CustomCssSelection(index: 0, enabled: true, indices: [0]));
    DocumentReflowAnchor? saved;
    await open(tester,
        quickMarkEnabled: true,
        extract: (_) async => '广告正文快速标记测试文字。',
        quickMark: (a, t, c, r) async => saved = a);
    final drag = await tester.startGesture(textPoint(tester, 2));
    await drag.moveTo(textPoint(tester, 8));
    await drag.up();
    await tester.pumpAndSettle();
    expect(saved!.start, 2);
    expect(saved!.end, 8);
    expect(saved!.matches(key.currentState!.quickMarkPage!), isTrue);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('speech follows its cursor after releasing a quick mark stroke',
      (tester) async {
    var submitted = 0;
    await open(tester,
        quickMarkEnabled: true,
        extract: (_) async =>
            List.generate(80, (i) => '第$i段，朗读和快速标记测试。').join('\n\n'),
        quickMark: (a, t, c, r) async => submitted++);
    final field = find.byKey(const ValueKey('reflow-text'));
    final controller = tester.widget<TextField>(field).controller!;
    final scroll = tester
        .widget<SingleChildScrollView>(find
            .ancestor(of: field, matching: find.byType(SingleChildScrollView))
            .first)
        .controller!;
    final source = key.currentState!.narrationSource!;
    final drag = await tester.startGesture(textPoint(tester, 1));
    await drag.moveTo(textPoint(tester, 8));
    source.seekToOffset(controller.text.indexOf('第60段'));
    final speaking = source.currentText();
    await tester.pumpAndSettle();
    expect(speaking, contains('第60段'));
    expect(source.valid, isTrue);
    expect(controller.selection.isCollapsed, isTrue);
    expect(scroll.offset, 0);
    await drag.up();
    await tester.pumpAndSettle();
    expect(submitted, 1);
    source.showCurrent();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(source.currentText(), speaking);
    expect(pages, [0]);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets(
      'multi-touch cannot restart quick marking until every finger lifts',
      (tester) async {
    var submitted = 0;
    await open(tester,
        quickMarkEnabled: true,
        extract: (_) async => '快速标记手指测试文字，禁止多指产生标记。',
        quickMark: (a, t, c, r) async => submitted++);
    final first = await tester.startGesture(textPoint(tester, 1), pointer: 41);
    await first.moveTo(textPoint(tester, 7));
    await tester.pump();
    expect(quickMarkPreview(tester), isTrue);
    final second = await tester.startGesture(textPoint(tester, 3), pointer: 42);
    final third = await tester.startGesture(textPoint(tester, 5), pointer: 43);
    await third.moveTo(textPoint(tester, 12));
    await third.up();
    await second.moveTo(textPoint(tester, 10));
    await second.up();
    await first.up();
    await tester.pumpAndSettle();
    expect(submitted, 0);
    expect(quickMarkPreview(tester), isFalse);
    final single = await tester.startGesture(textPoint(tester, 1));
    await single.moveTo(textPoint(tester, 8));
    await single.up();
    await tester.pumpAndSettle();
    expect(submitted, 1);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('consecutive quick strokes both commit before the next frame',
      (tester) async {
    final saved = <DocumentReflowAnchor>[];
    await open(tester,
        quickMarkEnabled: true,
        extract: (_) async => '连续快速标记测试文字，两笔都应该保存。',
        quickMark: (a, t, c, r) async => saved.add(a));
    final first = await tester.startGesture(textPoint(tester, 1));
    await first.moveTo(textPoint(tester, 6));
    await first.up();
    final second = await tester.startGesture(textPoint(tester, 9));
    await second.moveTo(textPoint(tester, 15));
    await second.up();
    expect(saved, isEmpty);
    await tester.pumpAndSettle();
    expect(saved.map((a) => (a.start, a.end)), [(1, 6), (9, 15)]);
    expect(quickMarkPreview(tester), isFalse);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets(
      'returning a quick stroke to its start does not save or open menus',
      (tester) async {
    var submitted = 0, menus = 0;
    await open(tester,
        quickMarkEnabled: true,
        quickMark: (a, t, c, r) async => submitted++,
        openReaderMenu: () => menus++);
    final drag = await tester.startGesture(textPoint(tester, 1));
    await drag.moveTo(textPoint(tester, 6));
    await drag.moveTo(textPoint(tester, 1));
    await drag.up();
    await tester.pumpAndSettle();
    expect(submitted, 0);
    expect(menus, 0);
    expect(quickMarkPreview(tester), isFalse);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets(
      'quick mark failure clears its preview without an unhandled error',
      (tester) async {
    await open(tester,
        quickMarkEnabled: true,
        quickMark: (a, t, c, r) async =>
            throw StateError('host reported failure'));
    final drag = await tester.startGesture(textPoint(tester, 0));
    await drag.moveTo(textPoint(tester, 7));
    await drag.up();
    await tester.pumpAndSettle();
    expect(quickMarkPreview(tester), isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('disabling quick mark restores ordinary text tapping',
      (tester) async {
    var submitted = 0;
    await open(tester,
        quickMarkEnabled: true, quickMark: (a, t, c, r) async => submitted++);
    Prefs().pageTurnMode = 'custom';
    Prefs().customPageTurnConfig = List.filled(9, 1);
    await open(tester,
        quickMarkEnabled: false, quickMark: (a, t, c, r) async => submitted++);
    await tester.tapAt(textPoint(tester, 1));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(submitted, 0);
    expect(pages, [0, 1]);
  }, variant: TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('desktop reflow does not activate the touch quick mark overlay',
      (tester) async {
    await open(tester,
        quickMarkEnabled: true, quickMark: (a, t, c, r) async {});
    expect(key.currentState!.canQuickMark, isFalse);
    expect(find.byKey(const ValueKey('reflow-quick-mark')), findsNothing);
  }, variant: TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets(
      'reflow templates apply CSS and skip filtered speech without changing stored text',
      (tester) async {
    await Prefs().saveCustomCssProfile(
        0, const CustomCssProfile(pattern: '正文', filterMode: 'text'));
    await Prefs().saveCustomCssProfile(1,
        const CustomCssProfile(css: 'p { font-size: 28px; color: #123456; }'));
    await Prefs().saveCustomCssSelection(
        const CustomCssSelection(index: 0, enabled: true, indices: [0, 1]));
    await open(tester);
    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('reflow-text')));
    expect(field.style!.fontSize, 28);
    expect(field.style!.color, const Color(0xff123456));
    expect(field.controller!.text, contains('正文'));
    expect(key.currentState!.narrationSource!.currentText(),
        isNot(contains('正文')));
    await Prefs().saveCustomCssSelection(
        const CustomCssSelection(index: 0, enabled: false, indices: [0, 1]));
    await tester.pumpAndSettle();
    expect(key.currentState!.narrationSource!.currentText(), contains('正文'));
  });

  testWidgets('reflow taps turn pages using configured previous and next zones',
      (tester) async {
    await open(tester);
    Prefs().pageTurnMode = 'custom';
    Prefs().customPageTurnConfig = List.filled(9, 1);
    await tester.tapAt(textPoint(tester, 1));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(store.latest.containsKey('1'), true);
    Prefs().customPageTurnConfig = List.filled(9, 2);
    await tester.tapAt(textPoint(tester, 1));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    final field =
        tester.widget<TextField>(find.byKey(const ValueKey('reflow-text')));
    expect(field.controller!.text, contains('第0页'));
  });

  testWidgets('single text tap respects a custom menu zone once',
      (tester) async {
    Prefs().pageTurnMode = 'custom';
    Prefs().customPageTurnConfig = List.filled(9, 3);
    var opened = 0;
    await open(tester, openReaderMenu: () => opened++);
    await tester.tapAt(textPoint(tester, 1));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(opened, 1);
  },
      variant: TargetPlatformVariant(
          {TargetPlatform.android, TargetPlatform.macOS}));

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

  for (final mode in [
    TranslationModeEnum.translationOnly,
    TranslationModeEnum.bilingual,
  ]) {
    testWidgets('macOS translated $mode drag publishes exact display selection',
        (tester) async {
      final selected = <String>[];
      var wordCalls = 0, cleared = 0;
      messenger.setMockMethodCallHandler(wordChannel, (_) async {
        wordCalls++;
        return [0, 5];
      });
      await open(tester,
          comparison: true,
          clearMenu: () => cleared++,
          translatedSelection: (value, context, rect, start) async =>
              selected.add(value));
      final task = key.currentState!
          .translateCurrentPage(mode, provider: PageTranslator());
      await tester.pumpAndSettle();
      await task;
      final controller = tester
          .widget<TextField>(
              find.byKey(const ValueKey('reflow-translated-text')))
          .controller!;
      final start = controller.text.indexOf('Translated');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.down(textPoint(tester, start + 1));
      await mouse.moveTo(textPoint(tester, start + 8));
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(controller.selection.isCollapsed, false);
      expect(selected.last, controller.selection.textInside(controller.text));
      expect(wordCalls, 0);
      final before = cleared, count = selected.length;
      await tester.tap(find.byKey(const ValueKey('reflow-next')));
      await tester.pumpAndSettle();
      expect(cleared, greaterThan(before));
      expect(selected.length, count);
      expect(
          find.byKey(const ValueKey('reflow-translated-text')), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({TargetPlatform.macOS}));
  }

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
    var calls = 0, readerMenus = 0;
    messenger.setMockMethodCallHandler(wordChannel, (_) async {
      calls++;
      return [0, 2];
    });
    await open(tester,
        ocr: true,
        openReaderMenu: () => readerMenus++,
        recognize: () async => '中国文化源远流长。',
        selection: (_, value, context, rect, ids) async => selected.add(value));
    final point = textPoint(tester, 0);
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(selected.last, '中国');
    expect(calls, 1);
    expect(readerMenus, 0,
        reason: 'Selecting text must not also open the bottom menu');
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
      'force OCR replaces embedded cache once; crop changes reuse the recognized page',
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
    expect(store.latest['0']!.ocr, isTrue);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Selected area'), findsNothing);
    await key.currentState!.setMode(false);
    expect(extracted.length, 1);
    crop = {'x': 0, 'y': 0, 'width': 1, 'height': 1};
    await key.currentState!.turnOriginalPage(1);
    await key.currentState!.turnOriginalPage(-1);
    await tester.pumpAndSettle();
    expect(extracted.length, 2);
    expect(extracted.last['region'], crop);
  });
  for (final width in [320.0, 800.0]) {
    for (final ocr in [false, true]) {
      testWidgets('larger reflow page buttons remain usable ($width, OCR=$ocr)',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await open(tester, ocr: ocr, textScale: 1.5);
        final previous = find.byKey(const ValueKey('reflow-previous'));
        final next = find.byKey(const ValueKey('reflow-next'));
        for (final button in [previous, next]) {
          expect(tester.getSize(button), const Size(56, 56));
          expect(tester.widget<IconButton>(button).iconSize, 36);
        }
        expect(tester.widget<IconButton>(previous).onPressed, isNull);
        // The enlarged outer hit area must work, not just the arrow itself.
        await tester.tapAt(tester.getCenter(next) + const Offset(24, 0));
        await tester.pumpAndSettle();
        expect(find.text('2 / 3'), findsOneWidget);
        await tester.tapAt(tester.getCenter(previous) - const Offset(24, 0));
        await tester.pumpAndSettle();
        expect(find.text('1 / 3'), findsOneWidget);
        expect(pages, [0, 1, 0]);
        expect(tester.takeException(), isNull);
      });
    }
  }
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
      'OCR mode bypasses embedded text and mode switches reuse saved OCR',
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
    expect(text(tester), 'OCR words');
    expect(extracted, 0);
    await key.currentState!.setMode(true);
    await tester.pumpAndSettle();
    expect(text(tester), 'OCR words');
    expect(ocr, 1);
  });
  for (final ocr in [false, true]) {
    testWidgets('initial reflow failure still allows source-page arrows ($ocr)',
        (tester) async {
      var source = 1;
      final requested = <int>[];
      Future<String> content() async {
        requested.add(source);
        if (source == 1) throw StateError('Page extraction failed');
        return 'Page $source text';
      }

      await open(tester,
          ocr: ocr,
          info: (page) async {
            source = page ?? 1;
            return {'page': source, 'total': 3};
          },
          extract: (_) => content(),
          recognize: content);
      expect(pages, isEmpty);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.textContaining('Reflow failed'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(requested, [1, 1]);
      await tester.tap(find.byKey(const ValueKey('reflow-next')));
      await tester.pumpAndSettle();
      expect(text(tester), 'Page 2 text');
      expect(pages, [2]);
      expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('reflow-next')))
              .onPressed,
          isNull);
      await tester.tap(find.byKey(const ValueKey('reflow-previous')));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(text(tester), 'Page 2 text');
      expect(pages, [2]);
      await tester.tap(find.byKey(const ValueKey('reflow-previous')));
      await tester.pumpAndSettle();
      expect(text(tester), 'Page 0 text');
      expect(pages, [2, 0]);
      expect(requested, [1, 1, 2, 1, 0]);
      expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('reflow-previous')))
              .onPressed,
          isNull);
    });
  }

  testWidgets(
      'failed source metadata can be retried or skipped without committing progress',
      (tester) async {
    final requests = <int>[];
    await open(tester,
        info: (page) async {
          final target = page ?? 0;
          requests.add(target);
          if (target == 1) throw StateError('Page metadata unavailable');
          return {'page': target, 'total': 3};
        },
        extract: (page) async => 'Page $page text');
    await tester.tap(find.byKey(const ValueKey('reflow-next')));
    await tester.pumpAndSettle();
    expect(text(tester), 'Page 0 text');
    expect(pages, [0]);
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(requests, [0, 1, 1]);
    await key.currentState!.turn(1);
    await tester.pumpAndSettle();
    expect(requests, [0, 1, 1, 2]);
    expect(text(tester), 'Page 2 text');
    expect(pages, [0, 2]);
  });

  testWidgets(
      'switching to OCR after failure retries the requested source page',
      (tester) async {
    final rendered = <int>[];
    await open(tester,
        extract: (page) async {
          if (page == 1) throw StateError('Text extraction failed');
          return 'First page';
        },
        renderRequest: (request) => rendered.add(request['page'] as int),
        recognize: () async => 'Recovered with OCR');
    await tester.tap(find.byKey(const ValueKey('reflow-next')));
    await tester.pumpAndSettle();
    expect(pages, [0]);
    expect(find.byType(DropdownButton<bool>), findsNothing);
    await key.currentState!.setMode(true);
    await tester.pumpAndSettle();
    expect(rendered, [1]);
    expect(pages, [0, 1]);
    expect(text(tester), 'Recovered with OCR');
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
    final span = field.controller!.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: const TextStyle(),
        withComposing: false);
    final source = key.currentState!.narrationSource!;
    source.currentText();
    source.clearHighlight();
    final afterSpeech = field.controller!.buildTextSpan(
        context: tester.element(find.byType(EditableText)),
        style: const TextStyle(),
        withComposing: false);
    expect(
        afterSpeech, span); // Temporary speech colour never overwrites notes.
    expect(field.controller!.selection,
        const TextSelection(baseOffset: 2, extentOffset: 8));
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
  for (final ocr in [true, false]) {
    testWidgets(
        'selection saves source geometry and ignores older revision marks (OCR=$ocr)',
        (tester) async {
      final old = DocumentReflowPage(page: 0, ocr: ocr, rawText: '旧文字。');
      notes = [
        BookNote(
            id: 9,
            bookId: 1,
            content: '旧文字',
            cfi: old.anchor(0, 3).encode(),
            chapter: '1',
            type: 'highlight',
            color: 'ffff00',
            updateTime: DateTime.now())
      ];
      DocumentReflowAnchor? selected;
      await open(tester,
          ocr: ocr,
          sourceGeometry: DocumentTextResult('朱熹異體。', const [
            DocumentTextRegion(0, 5, DocumentImageRect(.1, .2, .3, .05))
          ]),
          info: (_) async => {
                'page': 0,
                'total': 3,
                'region': {'x': .5, 'y': .1, 'width': .4, 'height': .8}
              },
          selection: (a, t, c, r, ids) async {
            selected = a;
            expect(ids, isEmpty);
          });
      final field =
          tester.widget<TextField>(find.byKey(const ValueKey('reflow-text')));
      field.controller!.selection =
          const TextSelection(baseOffset: 0, extentOffset: 2);
      field.contextMenuBuilder!(tester.element(find.byType(EditableText)),
          tester.state<EditableTextState>(find.byType(EditableText)));
      await tester.pump();
      expect(selected, isNotNull);
      final rect = selected!.rects.single;
      expect(rect.x, closeTo(ocr ? .54 : .1, 1e-9));
      expect(rect.y, closeTo(ocr ? .26 : .2, 1e-9));
      expect(notes.single.cfi, old.anchor(0, 3).encode());
      expect(notes.single.content, '旧文字');
    });
  }

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
