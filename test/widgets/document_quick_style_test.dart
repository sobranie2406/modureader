import 'dart:io';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/service/ocr/document_reflow_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:file_picker/file_picker.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/document_reading_mode.dart';
import 'package:anx_reader/models/pdf_reading_view.dart';
import 'package:anx_reader/models/document_page_layout.dart';
import 'package:anx_reader/widgets/reading_page/document_layout_editor.dart';
import 'package:anx_reader/widgets/reading_page/pdf_region_preview.dart';
import 'pdf_region_preview_test.dart' as fixture;
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/widgets/reading_page/document_style_widget.dart';
import 'package:anx_reader/widgets/reading_page/eink_refresh_controls.dart';
import 'package:anx_reader/widgets/reading_page/pdf_reading_controls.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:anx_reader/widgets/reading_page/document_panel_widgets.dart';
import 'package:anx_reader/widgets/reading_page/document_enhancement_panel.dart';
import 'package:anx_reader/widgets/common/app_scroll_behavior.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends EpubPlayerState {
  _Player(DocumentReadingMode mode) {
    documentReadingMode.value = mode;
  }
  bool enabled = true;
  bool forceOcr = false;
  @override
  bool get documentForceOcr => forceOcr;
  @override
  Future<void> setDocumentForceOcr(bool enabled) async {
    forceOcr = enabled;
  }

  int closes = 0;
  final renderSources = <Object?>[];
  final layouts = <DocumentLayoutConfig>[];
  @override
  bool get isPdfDocument =>
      documentReadingMode.value == DocumentReadingMode.pdf;
  @override
  String get cssBookKey => 'quick-document-test';
  @override
  bool get pdfPanelReading => enabled;
  @override
  PdfReadingView get pdfReadingView => const PdfReadingView();
  @override
  Future<Map<String, dynamic>> pdfRegionInfo(int? page) async =>
      fixture.info(page);
  @override
  Future<Map<String, dynamic>> epubImageInfo(int? page) async =>
      {...fixture.info(page), 'imageOnly': true};
  @override
  Future<Map<String, dynamic>> renderPdfRegion(
          Map<String, dynamic> request) async =>
      recordRender(request);
  Map<String, dynamic> recordRender(Map<String, dynamic> request) {
    renderSources.add(request['source']);
    return {'dataUrl': fixture.pixel};
  }

  @override
  void cancelPdfRegionRender({bool close = false}) {
    if (close) closes++;
  }

  @override
  void cancelEpubImageRender({bool close = false}) {
    if (close) closes++;
  }

  @override
  Future<void> savePdfLayout(DocumentLayoutConfig config) async =>
      layouts.add(config);
  @override
  Future<void> setPdfPanelReading(bool value) async {
    enabled = value;
  }
}

class _PlayerKey extends GlobalObjectKey<EpubPlayerState> {
  const _PlayerKey(this.player) : super(player);
  final EpubPlayerState player;
  @override
  EpubPlayerState get currentState => player;
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getDownloadsPath() async => path;
}

class _Picker extends FilePicker {
  _Picker(this.path);
  final String path;
  @override
  Future<String?> saveFile(
          {String? dialogTitle,
          String? fileName,
          String? initialDirectory,
          FileType type = FileType.any,
          List<String>? allowedExtensions,
          Uint8List? bytes,
          bool lockParentWindow = false}) async =>
      path;
}

class _LineHeightWidget extends StyleWidget {
  _LineHeightWidget()
      : super(
          themes: const [],
          setCurrentPage: (_) {},
          hideAppBarAndBottomBar: (_) {},
        );
  @override
  StyleWidgetState createState() => _LineHeightState();
}

class _LineHeightState extends StyleWidgetState {
  @override
  Widget build(BuildContext context) => lineHeightAndParagraphSpacingSlider();
}

void main() {
  setUpAll(() async {
    FilePicker.platform = _Picker('');
    await L10n.delegate.load(const Locale('en'));
    await L10n.delegate.load(const Locale('zh'));
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  testWidgets('legacy zero line-height opens at the compact slider minimum',
      (tester) async {
    Prefs().saveBookStyleToPrefs(BookStyle(lineHeight: 0));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: _LineHeightWidget()),
    ));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('reading-line-height-slider')));
    expect(slider.min, 1);
    expect(slider.value, 1);
    expect(slider.label, '0');
    slider.onChanged!(1.2);
    await tester.pumpAndSettle();
    expect(Prefs().bookStyle.lineHeight, 1.2);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [DocumentReadingMode.pdf, DocumentReadingMode.imageEpub]) {
    testWidgets('original Text menu exposes comparison switch: $mode',
        (tester) async {
      bool? comparison;
      await tester.pumpWidget(MaterialApp(
          localizationsDelegates: const [L10n.delegate],
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
              body: DocumentStyleWidget(
                  player: _Player(mode),
                  textOnly: true,
                  onComparisonChanged: (value) => comparison = value))));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('document-comparison-switch'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      expect(comparison, true);
      expect(find.text('Reflow text'), findsOneWidget);
      expect(find.text('Region extraction and continuous OCR'), findsOneWidget);
    });
    testWidgets(
        'Text menu exports saved corrections without a page editing entry: $mode',
        (tester) async {
      final directory = Directory.systemTemp.createTempSync('modu-text-menu-');
      final oldPaths = PathProviderPlatform.instance;
      final oldPicker = FilePicker.platform;
      PathProviderPlatform.instance = _Paths(directory.path);
      FilePicker.platform = _Picker('${directory.path}/export.txt');
      addTearDown(() {
        PathProviderPlatform.instance = oldPaths;
        FilePicker.platform = oldPicker;
        directory.deleteSync(recursive: true);
      });
      final player = _Player(mode);
      final store = DocumentReflowStore(player.cssBookKey);
      await tester.runAsync(() async {
        final page =
            DocumentReflowPage(page: 2, ocr: true, rawText: 'Saved OCR');
        await store.save(page, '');
        await store.saveEdit(page, 'Corrected text');
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DocumentStyleWidget(player: player, textOnly: true))));
      await tester.pumpAndSettle();
      final textHeading = tester.widget<Text>(find.text('Text'));
      expect(textHeading.style?.fontFamily, 'SourceHanSerif');
      expect(textHeading.style?.fontSize, 28);
      expect(textHeading.style?.fontWeight, FontWeight.bold);
      expect(find.text('Edit, cache and export'), findsNothing);
      expect(find.byKey(const ValueKey('edit-saved-page')), findsNothing);
      expect(find.text('Edit saved page'), findsNothing);
      final export = find.byKey(const ValueKey('export-saved-txt'));
      expect(export, findsOneWidget);
      await tester.ensureVisible(export);
      await tester.runAsync(() => tester.tap(export));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('export-format-txt')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      final output =
          directory.listSync().whereType<File>().single.readAsStringSync();
      expect(output, contains('Corrected text'));
      expect(output, isNot(contains('Saved OCR')));
      expect(find.text('TXT exported'), findsOneWidget);
      expect(player.renderSources, isEmpty,
          reason: 'Export must never start OCR');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      player.documentReadingMode.dispose();
    });
  }
  testWidgets(
      'PDF phone style uses aligned sections and a single enhancement entry',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final player = _Player(DocumentReadingMode.pdf);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      scrollBehavior: const AppScrollBehavior(),
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
          body: Align(
              alignment: Alignment.bottomCenter,
              child: ReaderQuickStylePanel(
                content:
                    DocumentStyleWidget(player: player, openReflow: (_) {}),
                toolbar: const SizedBox(height: 48),
              ))),
    ));
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byType(DocumentStyleWidget));
    final row = tester.getRect(find.byType(DocumentControlRow).first);
    expect(row.left - panel.left, closeTo(panel.right - row.right, .01));
    final rows = tester
        .widgetList<DocumentControlRow>(find.byType(DocumentControlRow))
        .take(8);
    for (final item in rows) {
      expect(tester.getRect(find.byWidget(item)).left, closeTo(row.left, .01));
    }
    expect(find.text('调整图像效果'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '文字加黑 0'), findsNothing);
    await tester.ensureVisible(find.text('调整图像效果'));
    await tester.tap(find.text('调整图像效果'));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentEnhancementPanel), findsOneWidget);
    await tester.tap(find.byTooltip('返回版式'));
    await tester.pumpAndSettle();
    expect(find.byType(DocumentEnhancementPanel), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    player.documentReadingMode.dispose();
  });
  for (final mode in [DocumentReadingMode.pdf, DocumentReadingMode.imageEpub]) {
    testWidgets(
        '$mode crop button goes straight to the same editor; cancel and confirm return to menu',
        (tester) async {
      final player = _Player(mode);
      final label = mode == DocumentReadingMode.pdf
          ? 'PDF crop and panels'
          : 'Scanned image crop and panels';
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: DocumentStyleWidget(player: player)))));
      await tester.pumpAndSettle();
      for (final action in ['Cancel', 'Confirm']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(DocumentLayoutEditor), findsOneWidget);
        expect(find.text('Original preview page 3 / 6'), findsOneWidget);
        expect(find.text('PDF region preview'), findsNothing);
        expect(find.byKey(const ValueKey('pdf-region-viewport')), findsNothing);
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        expect(find.byType(DocumentLayoutEditor), findsNothing);
        expect(find.byType(PdfRegionPreview), findsNothing);
        expect(player.layouts.length, action == 'Confirm' ? 1 : 0);
        expect(tester.takeException(), isNull);
      }
      expect(player.closes, 2);
      expect(player.renderSources,
          everyElement(mode == DocumentReadingMode.imageEpub ? 'epub' : null));
      await tester.pumpWidget(const SizedBox());
      player.documentReadingMode.dispose();
    });
  }
  testWidgets(
      'refresh group appears only with E-Ink on and hides immediately when off',
      (tester) async {
    const channel = MethodChannel('com.modu.reader/eink_refresh');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final player = _Player(DocumentReadingMode.pdf);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DocumentStyleWidget(player: player))));
    await tester.pumpAndSettle();
    expect(find.byType(EinkRefreshControls), findsNothing);
    Prefs().eInkMode = true;
    await tester.pumpAndSettle();
    expect(find.byType(EinkRefreshControls), findsOneWidget);
    expect(find.text('Refresh now'), findsOneWidget);
    Prefs().eInkMode = false;
    await tester.pumpAndSettle();
    expect(find.byType(EinkRefreshControls), findsNothing);
    expect(find.text('Refresh now'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    player.documentReadingMode.dispose();
  });
  for (final mode in [DocumentReadingMode.pdf, DocumentReadingMode.imageEpub]) {
    testWidgets('$mode has direct quick controls instead of font sliders',
        (tester) async {
      final player = _Player(mode);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
            body: StyleWidget(
          themes: const [],
          epubPlayerKey: _PlayerKey(player),
          setCurrentPage: (_) {},
          hideAppBarAndBottomBar: (_) {},
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentStyleWidget), findsOneWidget);
      expect(find.text('Page'), findsOneWidget);
      final heading = tester.widget<Text>(find.text('Page'));
      expect(heading.style?.fontFamily, 'SourceHanSerif');
      expect(heading.style?.fontSize, 28);
      expect(heading.style?.fontWeight, FontWeight.bold);
      expect(find.byType(PdfReadingControls), findsOneWidget);
      await tester.tap(find.text('Page fit').first);
      await tester.pumpAndSettle();
      expect(find.text('Fit width'), findsOneWidget);
      expect(find.text('Image enhancement'), findsOneWidget);
      expect(find.byIcon(Icons.format_size), findsNothing);
      expect(find.byTooltip('OCR text style'), findsNothing);
      final crop = find.text(mode == DocumentReadingMode.pdf
          ? 'PDF crop and panels'
          : 'Scanned image crop and panels');
      await tester.ensureVisible(crop);
      await tester.tap(crop);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Read cropped panels'));
      await tester.tap(find.text('Read cropped panels'));
      await tester.pumpAndSettle();
      expect(player.enabled, isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfReadingControls), findsOneWidget);
      expect(
          find.text(mode == DocumentReadingMode.pdf
              ? 'PDF crop and panels'
              : 'Scanned image crop and panels'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      player.documentReadingMode.dispose();
    });
  }
  for (final size in [
    const Size(320, 740),
    const Size(844, 390),
    const Size(1024, 1366),
    const Size(1440, 900),
  ]) {
    testWidgets('document panel fits $size and large accessibility text',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final player = _Player(DocumentReadingMode.imageEpub);
      final reflowModes = <bool>[];
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!),
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                    height: size.height * .65,
                    child: DocumentStyleWidget(
                        player: player, openReflow: reflowModes.add)))),
      ));
      await tester.pumpAndSettle();
      final rows = tester
          .widgetList<DocumentControlRow>(find.byType(DocumentControlRow))
          .map((row) => row.label)
          .toList();
      expect(rows, ['Image enhancement']);
      for (final title in [
        'Page fit',
        'Rotation',
        'Page turning and options'
      ]) {
        expect(find.text(title), findsOneWidget);
        await tester.ensureVisible(find.text(title));
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: title);
      }
      final chip = tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Single page'));
      expect(chip.selected, isTrue);
      final theme = Theme.of(tester.element(find.byType(PdfReadingControls)));
      final appTheme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.colorScheme, appTheme.colorScheme);
      expect(chip.selectedColor, appTheme.colorScheme.primary);
      expect((chip.label as Text).style?.color, appTheme.colorScheme.onPrimary);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DocumentStyleWidget(
                  player: player,
                  textOnly: true,
                  openReflow: reflowModes.add))));
      await tester.pumpAndSettle();
      expect(find.text('Region extraction and continuous OCR'), findsOneWidget);
      await tester.ensureVisible(find.text('Reflow text'));
      await tester.tap(find.text('Reflow text'));
      expect(reflowModes, [false]);
      expect(find.text('OCR reflow'), findsNothing);
      expect(find.text('Text style'), findsNothing);
      expect(find.text('Background OCR cache'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      player.documentReadingMode.dispose();
    });
  }
}
