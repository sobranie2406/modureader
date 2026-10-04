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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Player extends EpubPlayerState {
  _Player(DocumentReadingMode mode) {
    documentReadingMode.value = mode;
  }
  bool enabled = true;
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

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
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
      expect(
          find.text(mode == DocumentReadingMode.pdf
              ? 'PDF reading'
              : 'Scanned image reading'),
          findsOneWidget);
      expect(find.byType(PdfReadingControls), findsOneWidget);
      expect(find.text('Fit width'), findsOneWidget);
      expect(find.text('Image enhancement'), findsOneWidget);
      expect(find.byIcon(Icons.format_size), findsNothing);
      expect(find.byTooltip('OCR text style'), findsOneWidget);
      await tester.tap(find.byTooltip('OCR text style'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ocr-style-size')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      expect(player.enabled, isFalse);
      expect(find.byType(PdfReadingControls), findsNothing);
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
      expect(rows.take(7), [
        'Text mode',
        'Original page zoom',
        'Mode',
        'Crop',
        'Layout',
        'Image enhancement',
        'Rotation'
      ]);
      final chip = tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Single page'));
      expect(chip.selected, isTrue);
      final theme = Theme.of(tester.element(find.byType(PdfReadingControls)));
      final appTheme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(theme.colorScheme, appTheme.colorScheme);
      expect(chip.selectedColor, appTheme.colorScheme.primary);
      expect((chip.label as Text).style?.color, appTheme.colorScheme.onPrimary);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Reflow text'));
      await tester.tap(find.text('Reflow text'));
      await tester.ensureVisible(find.text('OCR reflow'));
      await tester.tap(find.text('OCR reflow'));
      expect(reflowModes, [false, true]);
      await tester.pumpWidget(const SizedBox.shrink());
      player.documentReadingMode.dispose();
    });
  }
}
