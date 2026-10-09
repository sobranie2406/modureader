import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/service/book_player/document_type_store.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/service/ocr/document_reflow_store.dart';
import 'dart:async';
import 'package:anx_reader/service/eink_refresh.dart';
import 'package:anx_reader/widgets/reading_page/reading_info_line.dart';
import 'package:anx_reader/widgets/reading_page/vertical_page_chrome.dart';
import 'package:anx_reader/service/translate/ai.dart';
import 'package:anx_reader/service/translate/deepl.dart';
import 'package:anx_reader/service/translate/microsoft_free.dart';
import 'package:anx_reader/service/translate/reader_translation_session.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/document_reading_mode.dart';
import 'package:anx_reader/service/book_player/document_reading_mode_store.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/enums/page_turn_mode.dart';
import 'package:anx_reader/enums/reading_info.dart';
import 'package:anx_reader/enums/translation_mode.dart';
import 'package:anx_reader/enums/writing_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/models/bookmark.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/models/reading_rules.dart';
import 'package:anx_reader/models/search_result_model.dart';
import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/models/reader_progress.dart';
import 'package:anx_reader/page/book_player/image_viewer.dart';
import 'package:anx_reader/page/home_page.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/book_toc.dart';
import 'package:anx_reader/providers/bookmark.dart';
import 'package:anx_reader/providers/chapter_content_bridge.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/providers/sync_database_revision.dart';
import 'package:anx_reader/service/book_player/reader_progress_session.dart';
import 'package:anx_reader/service/book_player/document_layout_store.dart';
import 'package:anx_reader/service/book_player/pdf_reading_state_store.dart';
import 'package:anx_reader/models/pdf_reading_view.dart';
import 'package:anx_reader/models/document_page_layout.dart';
import 'package:anx_reader/service/book_player/reading_appearance.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/book_player/quick_mark_service.dart';
import 'package:anx_reader/service/book_player/reader_word_selection.dart';
import 'package:anx_reader/service/book_player/tts_text_result.dart';
import 'package:anx_reader/service/battery_level.dart';
import 'package:anx_reader/widgets/reading_page/reading_battery_indicator.dart';
import 'package:anx_reader/service/tts/tts_reader_wait.dart';
import 'package:anx_reader/providers/toc_search.dart';
import 'package:anx_reader/widgets/reading_page/search_navigation_bar.dart';
import 'package:anx_reader/widgets/reading_page/reader_loading_status.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/utils/coordinates_to_part.dart';
import 'package:anx_reader/utils/js/convert_dart_color_to_js.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/webView/gererate_url.dart';
import 'package:anx_reader/utils/webView/webview_console_message.dart';
import 'package:anx_reader/widgets/context_menu/context_menu.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/page_turning/diagram.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/page_turning/types_and_icons.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';

import 'minute_clock.dart';

class EpubPlayer extends ConsumerStatefulWidget {
  final Book book;
  final String? cfi;
  final Function showOrHideAppBarAndBottomBar;
  final Function onLoadEnd;
  final List<ReadTheme> initialThemes;
  final Function updateParent;

  const EpubPlayer(
      {super.key,
      required this.showOrHideAppBarAndBottomBar,
      required this.book,
      this.cfi,
      required this.onLoadEnd,
      required this.initialThemes,
      required this.updateParent});

  @override
  ConsumerState<EpubPlayer> createState() => EpubPlayerState();
}

class EpubPlayerState extends ConsumerState<EpubPlayer> {
  String get cssBookKey => customCssBookKey(widget.book);
  late InAppWebViewController webViewController;
  late ContextMenu contextMenu;
  String cfi = '';
  double percentage = 0.0;
  String chapterTitle = '';
  String chapterHref = '';
  int chapterCurrentPage = 0;
  int chapterTotalPages = 0;
  int currentChapter = 0;
  int totalChapters = 0;
  final readingProgress = ValueNotifier<ReaderProgress>(const ReaderProgress());
  int bookCurrentPage = 0;
  int bookTotalPages = 0;
  Map<String, double>? _lastVerticalInsets;
  bool _verticalInsetsPending = false;

  bool get _verticalPage =>
      Prefs().writingMode.isVertical ||
      (Prefs().writingMode == WritingModeEnum.auto && writingMode.isVertical);

  VerticalPageGeometry get _verticalGeometry {
    final info = Prefs().readingInfo;
    final textScaler = MediaQuery.textScalerOf(context);
    return VerticalPageGeometry(
        MediaQuery.viewPaddingOf(context),
        textScaler.scale(info.header.fontSize.clamp(8, 24)),
        textScaler.scale(info.footer.fontSize.clamp(8, 24)));
  }

  VerticalPageChrome get _verticalChrome => VerticalPageChrome(
        geometry: _verticalGeometry,
        chapterTitle: chapterTitle.isEmpty ? widget.book.title : chapterTitle,
        remainingPages:
            (chapterTotalPages - chapterCurrentPage).clamp(0, 100000000),
        currentPage: bookCurrentPage + 1,
        totalPages: bookTotalPages,
        color: Color(int.parse('0x${textColor ?? Prefs().readTheme.textColor}'))
            .withAlpha(180),
        redFrame: Prefs().verticalRedFrame,
      );

  Map<String, dynamic>? get _webVerticalChrome => AnxPlatform.isMacOS
      ? _verticalChrome.toWebStyle(Localizations.localeOf(context))
      : null;

  OverlayEntry? contextMenuEntry;
  bool showHistory = false;
  bool canGoBack = false;
  bool canGoForward = false;
  late Book book;
  String? backgroundColor;
  String? textColor;
  Timer? styleTimer;
  String bookmarkCfi = '';
  bool bookmarkExists = false;
  WritingModeEnum writingMode = WritingModeEnum.horizontalTb;
  String? _lastSelectionContextText;
  bool _selectionClearLocked = false;
  bool _selectionClearPending = false;
  bool _readerReady = false;
  bool _readerLoadFailed = false;
  bool _chapterLoading = false;
  bool _chapterLoadFailed = false;
  bool _chapterFontFailed = false;
  final translationMode = ValueNotifier(TranslationModeEnum.off);
  final _translationSession = ReaderTranslationSession();
  bool quickMarkEnabled = false;
  final _quickMarks = QuickMarkService(bookNoteDao);
  late final ReaderProgressSession _progress;
  Future<void>? _syncRefresh;
  bool _refreshRequested = false;
  bool _remotePositionPending = false;
  Timer? _syncRefreshRetry;
  int _syncRestoreAttempts = 0;

  Future<bool> setQuickMarkEnabled(bool enabled) async {
    if (!AnxPlatform.isMobile || !_readerReady) return false;
    removeOverlay();
    final result = await webViewController.evaluateJavascript(
        source: 'window.setQuickMarkEnabled?.($enabled, '
            '${jsonEncode('#${Prefs().annotationColor}')}, ${Prefs().quickMarkShowMenu})');
    if (!mounted) return false;
    quickMarkEnabled = result == true;
    return quickMarkEnabled;
  }

  void _quickMarkError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ModuStrings.text(context, '快速标记保存失败，请重试。',
            'Could not save the highlight. Please retry.'))));
  }

  // Scroll wheel debounce
  Timer? _scrollDebounceTimer;
  double _accumulatedScrollDelta = 0;
  static const double _scrollThreshold = 50.0;

  // to know anytime if we are on top of navigation stack
  bool get _isTopOfNavigationStack =>
      ModalRoute.of(context)?.isCurrent ?? false;

  Future<bool?> requestNativeFocus() async {
    if (!mounted || !_readerReady || !_isTopOfNavigationStack) return false;
    return webViewController.requestFocus();
  }

  void prevPage() {
    if (readingPageKey.currentState?.isReflowReading == true) {
      unawaited(readingPageKey.currentState!.reflowReader?.turn(-1));
      return;
    }
    webViewController.evaluateJavascript(source: 'prevPage(); void 0;');
  }

  Future<Map<String, dynamic>> analyzeDocument() async {
    if (!_readerReady) throw StateError('Reader is not ready');
    final result = await webViewController.callAsyncJavaScript(
      functionBody: 'return await window.analyzeReaderDocument();',
    );
    if (result?.error != null || result?.value is! Map) {
      throw StateError('Document inspection failed');
    }
    final analysis = Map<String, dynamic>.from(result!.value as Map);
    final kind = analysis['kind'];
    if (kind is String) {
      // This shelf hint must never block document tools if cache storage fails.
      try {
        await DocumentTypeStore(Prefs().prefs).saveDetected(cssBookKey, kind);
        Prefs().notifyExternalChange();
      } catch (_) {}
    }
    return analysis;
  }

  void cancelDocumentAnalysis() {
    if (!_readerReady || !mounted) return;
    unawaited(webViewController
        .evaluateJavascript(
            source: 'window.cancelDocumentAnalysis?.(); void 0;')
        .catchError((_) => null));
  }

  Future<Map<String, dynamic>> pdfRegionInfo(int? page) => _pdfPreviewCall(
      'return await window.getPdfRegionInfo(page);', {'page': page});

  Future<Map<String, dynamic>> epubImageInfo(int? page) => _pdfPreviewCall(
      'return await window.getEpubImageInfo(page);', {'page': page});

  void cancelEpubImageRender({bool close = false}) {
    if (!_readerReady || !mounted) return;
    unawaited(webViewController
        .evaluateJavascript(
            source: close
                ? 'window.closeEpubImagePreview?.(); void 0;'
                : 'window.cancelEpubImageRender?.(); void 0;')
        .catchError((_) => null));
  }

  bool get isPdfDocument => widget.book.filePath.toLowerCase().endsWith('.pdf');
  final documentReadingMode = ValueNotifier(DocumentReadingMode.standard);
  bool get isImageEpub =>
      documentReadingMode.value == DocumentReadingMode.imageEpub;
  bool get supportsDocumentImages => documentReadingMode.value.hasDocumentMenu;
  final einkRefresh = EinkRefresh();
  bool _einkReaderActive = false;
  late final _einkPageRefresh = EinkPageRefreshScheduler(() async {
    await WidgetsBinding.instance.endOfFrame;
    return einkRefresh.refresh(
        canRefresh: () =>
            mounted &&
            _einkReaderActive &&
            Prefs().eInkMode &&
            Prefs().eInkRefreshPages > 0 &&
            supportsDocumentImages);
  });

  void _configureEinkRefresh() {
    _einkPageRefresh.configure(
        active: mounted &&
            _einkReaderActive &&
            Prefs().eInkMode &&
            supportsDocumentImages,
        interval: Prefs().eInkRefreshPages);
  }

  Future<bool> refreshEinkScreen() async {
    if (!mounted || !Prefs().eInkMode || !supportsDocumentImages) return false;
    final success = await einkRefresh.refresh(
        canRefresh: () =>
            mounted && Prefs().eInkMode && supportsDocumentImages);
    if (success) _einkPageRefresh.reset();
    return success;
  }

  void _observeEinkPage(Map<String, dynamic> location) {
    if (!supportsDocumentImages) return;
    final region = location['pdfRegion'];
    final raw = region is Map ? region['page'] : null;
    final chapter = location['currentChapter'];
    final page = raw is int ? raw : (chapter is int ? chapter - 1 : -1);
    _configureEinkRefresh();
    _einkPageRefresh.observe(page,
        readingAction: location['readingAction'] == true);
  }

  void setDocumentReaderActive(bool active) {
    active = active && readingPageKey.currentState?.isReflowReading != true;
    _einkReaderActive = active;
    _configureEinkRefresh();
    if (!_readerReady || !mounted) return;
    unawaited(webViewController
        .evaluateJavascript(
            source:
                'window.setDocumentReaderActive?.(${active ? 'true' : 'false'}); void 0;')
        .catchError((_) => null));
  }

  bool get pdfPanelReading {
    if (!supportsDocumentImages) return false;
    final store = PdfReadingStateStore(Prefs().prefs);
    return !store.hasSavedMode(cssBookKey) ||
        store.read(cssBookKey)['enabled'] == true;
  }

  PdfReadingView get pdfReadingView =>
      PdfReadingStateStore(Prefs().prefs).readView(cssBookKey);

  Future<void> setPdfReadingView(PdfReadingView view) async {
    if (!_readerReady || !mounted) throw StateError('Reader is not ready');
    final previous = pdfReadingView;
    Future<void> apply(PdfReadingView value) async {
      if (isImageEpub && !pdfPanelReading) return;
      final result = await webViewController.callAsyncJavaScript(
          functionBody: 'return await window.setPdfReadingView(value);',
          arguments: {'value': value.toJson()});
      if (result?.error != null || result?.value != true) {
        throw StateError('PDF viewport could not be applied');
      }
    }

    await apply(view);
    try {
      await PdfReadingStateStore(Prefs().prefs)
          .saveView(cssBookKey, view, enabled: pdfPanelReading);
    } catch (_) {
      await apply(previous);
      rethrow;
    }
  }

  Future<void> panPdfReadingView(double dx, double dy) async {
    if (!_readerReady || !mounted) throw StateError('Reader is not ready');
    final result = await webViewController.callAsyncJavaScript(
        functionBody: 'return window.panPdfReadingView(dx, dy);',
        arguments: {'dx': dx, 'dy': dy});
    if (result?.error != null || result?.value != true) {
      throw StateError('PDF viewport could not be moved');
    }
  }

  Future<void> setPdfPanelReading(bool enabled) async {
    if (!_readerReady || !mounted) throw StateError('Reader is not ready');
    if (!supportsDocumentImages)
      throw StateError('Original-page mode is unavailable');
    final previous = pdfPanelReading;
    final config = DocumentLayoutStore(Prefs().prefs).read(cssBookKey);
    await _applyPdfLayout(config, enabled);
    try {
      await PdfReadingStateStore(Prefs().prefs).setEnabled(cssBookKey, enabled);
    } catch (_) {
      await _applyPdfLayout(config, previous);
      rethrow;
    }
  }

  Future<void> savePdfLayout(DocumentLayoutConfig config) async {
    final store = DocumentLayoutStore(Prefs().prefs);
    final previous = store.read(cssBookKey);
    await store.save(cssBookKey, config);
    try {
      if (pdfPanelReading && mounted) await _applyPdfLayout(config, true);
    } catch (_) {
      await store.save(cssBookKey, previous);
      rethrow;
    }
  }

  Future<void> _applyPdfLayout(
      DocumentLayoutConfig config, bool enabled) async {
    final result = await webViewController.callAsyncJavaScript(
        functionBody:
            'return await window.setPdfReadingLayout(config, enabled, view);',
        arguments: {
          'config': config.toJson(),
          'enabled': enabled,
          'view': pdfReadingView.toJson()
        });
    if (result?.error != null || result?.value != true) {
      throw StateError('PDF reading layout could not be applied');
    }
  }

  Future<Map<String, dynamic>> renderPdfRegion(Map<String, dynamic> request) =>
      _pdfPreviewCall('return await window.renderPdfRegion(request);',
          {'request': request});

  Future<Map<String, dynamic>> extractDocumentText(
          Map<String, dynamic> request) =>
      _pdfPreviewCall('return await window.extractDocumentText(request);',
          {'request': request});

  Future<Map<String, dynamic>> documentReflowInfo(int? page) => _pdfPreviewCall(
          'return await window.getDocumentReflowInfo(page, config, enabled, imageEpub, hideWatermarks);',
          {
            'page': page,
            'config':
                DocumentLayoutStore(Prefs().prefs).read(cssBookKey).toJson(),
            'enabled': pdfPanelReading,
            'imageEpub': isImageEpub,
            'hideWatermarks': pdfReadingView.display.hideWatermarks,
          });

  Future<Map<String, dynamic>> _pdfPreviewCall(
      String body, Map<String, dynamic> arguments) async {
    if (!_readerReady || !mounted) throw StateError('Reader is not ready');
    final result = await webViewController.callAsyncJavaScript(
        functionBody: body, arguments: arguments);
    if (result?.error != null || result?.value is! Map) {
      throw StateError('PDF preview failed');
    }
    return Map<String, dynamic>.from(result!.value as Map);
  }

  void cancelPdfRegionRender({bool close = false}) {
    if (!_readerReady || !mounted) return;
    unawaited(webViewController
        .evaluateJavascript(
            source: close
                ? 'window.closePdfRegionPreview?.(); void 0;'
                : 'window.cancelPdfRegionRender?.(); void 0;')
        .catchError((_) => null));
  }

  void nextPage() {
    if (readingPageKey.currentState?.isReflowReading == true) {
      unawaited(readingPageKey.currentState!.reflowReader?.turn(1));
      return;
    }
    webViewController.evaluateJavascript(source: 'nextPage(); void 0;');
  }

  void prevChapter() {
    if (readingPageKey.currentState?.isReflowReading == true) {
      unawaited(
          readingPageKey.currentState!.reflowReader?.turnOriginalPage(-1));
      return;
    }
    webViewController.evaluateJavascript(source: '''
      prevSection(); void 0;
      ''');
  }

  void nextChapter() {
    if (readingPageKey.currentState?.isReflowReading == true) {
      unawaited(readingPageKey.currentState!.reflowReader?.turnOriginalPage(1));
      return;
    }
    webViewController.evaluateJavascript(source: '''
      nextSection(); void 0;
      ''');
  }

  Future<void> setTranslationMode(TranslationModeEnum mode) async {
    await translateCurrentChapter(mode);
  }

  Future<void> translateCurrentChapter(
    TranslationModeEnum mode, {
    bool force = false,
  }) async {
    final generation = mode == TranslationModeEnum.off
        ? (_translationSession..stop()).generation
        : _translationSession.start();
    translationMode.value = mode;
    // A persisted display preference is not permission to resume API requests.
    Prefs().setBookTranslationMode(widget.book.id, TranslationModeEnum.off);
    try {
      final result = await webViewController.callAsyncJavaScript(
        functionBody: '''
        if (typeof reader === 'undefined' ||
            typeof reader.view === 'undefined' ||
            !reader.view.setTranslationMode) {
          return false;
        }
        await reader.view.setTranslationMode('off');
        if (${force ? 'true' : 'false'}) {
          if (reader.view.clearTranslations) {
            reader.view.clearTranslations();
          }
        }
        await reader.view.setTranslationMode(${jsonEncode(mode.code)}, $generation);
        return true;
      ''',
      );
      if (result?.value != true) {
        throw StateError('Translation is not available for this book');
      }
    } catch (_) {
      if (_translationSession.generation == generation) {
        _translationSession.stop();
        translationMode.value = TranslationModeEnum.off;
      }
      rethrow;
    }
  }

  Future<void> goToPercentage(double value) async {
    await readingPageKey.currentState?.closeDocumentReflow();
    await webViewController.evaluateJavascript(source: '''
      goToPercent($value); 
      ''');
  }

  void setSelectionClearLocked(bool locked, {bool preserveOverlay = false}) {
    _selectionClearLocked = locked;
    // Opening a Flutter confirmation may clear the WebView's native selection.
    // The toolbar still owns a valid snapshot, including after cancellation.
    if (!locked && preserveOverlay) _selectionClearPending = false;
    if (!locked && _selectionClearPending) {
      _selectionClearPending = false;
      _lastSelectionContextText = null;
      removeOverlay();
    }
  }

  void reflowSelectionInvalidated() {
    if (_selectionClearLocked) {
      _selectionClearPending = true;
      return;
    }
    removeOverlay();
  }

  void changeTheme(ReadTheme readTheme) {
    if (!mounted) return;
    setState(() {
      textColor = readTheme.textColor;
      backgroundColor = readTheme.backgroundColor;
    });

    String bc = convertDartColorToJs(readTheme.backgroundColor);
    String tc = convertDartColorToJs(readTheme.textColor);

    webViewController.evaluateJavascript(source: '''
      changeStyle({
        backgroundColor: '#$bc',
        fontColor: '#$tc',
        verticalPageChrome: ${jsonEncode(_webVerticalChrome)},
      })
      ''');
  }

  void changeStyle(BookStyle? bookStyle) {
    if (mounted) setState(() {});
    styleTimer?.cancel();
    styleTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final bgimgUrl =
          readingBackgroundForDisplay(Prefs(), isDarkMode: isDarkMode);
      BookStyle style = bookStyle ?? Prefs().bookStyle;
      webViewController.evaluateJavascript(source: '''
      changeStyle({
        fontSize: ${style.fontSize},
        mobileImageFit: ${AnxPlatform.isMobile},
        mobileTouchPaging: ${AnxPlatform.isMobile},
        desktopPageInput: ${AnxPlatform.isDesktop},
        keyboardShortcutTurnPage: ${Prefs().keyboardShortcutTurnPage},
        tapOnlyPageTurn: ${Prefs().tapOnlyPageTurn},
        longPressSelectParagraph: ${Prefs().longPressSelectParagraph},
        selectionLocale: ${jsonEncode(Prefs().effectiveLocale.toLanguageTag())},
        scrollPagePercent: ${Prefs().scrollPagePercent},
        spacing: ${style.lineHeight},
        fontWeight: ${style.fontWeight},
        simulateBold: ${style.simulateBold},
        paragraphSpacing: ${style.paragraphSpacing},
        topMargin: ${style.topMargin},
        bottomMargin: ${style.bottomMargin},
        sideMargin: ${style.sideMargin},
        letterSpacing: ${style.letterSpacing},
        textIndent: ${style.indent},
        maxColumnCount: ${style.maxColumnCount},
        columnThreshold: ${style.columnThreshold},
        writingMode: '${Prefs().writingMode.code}',
        verticalPageInsets: ${jsonEncode(_verticalGeometry.toJson())},
        verticalPageChrome: ${jsonEncode(_webVerticalChrome)},
        verticalRedFrame: ${Prefs().verticalRedFrame},
        textAlign: '${Prefs().textAlignment.code}',
        backgroundImage: ${jsonEncode(bgimgUrl)},
        bgimgBlur: ${Prefs().bgimg.blur},
        bgimgOpacity: ${Prefs().bgimg.opacity},
        bgimgFit: '${Prefs().bgimgFit.code}',
        customCSS: ${jsonEncode(Prefs().customCssForBook(cssBookKey))},
        customHighlightRules: ${jsonEncode(Prefs().customHighlightRulesForBook(cssBookKey))},
        customCSSEnabled: ${Prefs().customCssSelection(cssBookKey).enabled},
        useBookStyles: ${Prefs().useBookStyles},
        headingFontSize: ${style.headingFontSize},
        codeHighlightTheme: '${Prefs().codeHighlightTheme.code}',
      })
      ''');
    });
  }

  void changeBgimgEffect() {
    if (!mounted) return;
    final bgimg = Prefs().bgimg;
    final bgimgUrl =
        readingBackgroundForDisplay(Prefs(), isDarkMode: isDarkMode);
    webViewController.evaluateJavascript(source: '''
      changeStyle({
        backgroundImage: ${jsonEncode(bgimgUrl)},
        bgimgBlur: ${bgimg.blur},
        bgimgOpacity: ${bgimg.opacity},
        bgimgFit: '${Prefs().bgimgFit.code}',
      })
    ''');
  }

  void changeReadingRules(ReadingRules readingRules) {
    webViewController.evaluateJavascript(source: '''
      readingFeatures({
        convertChineseMode: '${readingRules.convertChineseMode.name}',
        bionicReadingMode: ${readingRules.bionicReading},
      })
    ''');
  }

  void changeFont(FontModel font) {
    webViewController.evaluateJavascript(source: '''
      changeStyle({
        fontName: ${jsonEncode(font.name)},
        fontPath: ${jsonEncode(font.path)},
      })
    ''');
  }

  void changeEnglishFont(FontModel? font) {
    webViewController.evaluateJavascript(source: '''
      changeStyle({
        englishFontName: ${jsonEncode(font?.name)},
        englishFontPath: ${jsonEncode(font?.path)},
      })
    ''');
  }

  void changePageTurnStyle(PageTurn pageTurnStyle) {
    webViewController.evaluateJavascript(source: '''
      changeStyle({
        pageTurnStyle: '${pageTurnStyle.name}',
        eInkMode: ${Prefs().eInkMode},
      })
    ''');
  }

  void changeScrollPagePercent(int percent) {
    // Input distance only: do not restyle/reflow the chapter or move its CFI.
    webViewController.evaluateJavascript(
        source: 'window.setScrollPagePercent(${percent.clamp(80, 100)});');
  }

  void goToHref(String href) {
    unawaited(() async {
      await readingPageKey.currentState?.closeDocumentReflow();
      if (mounted)
        await webViewController.evaluateJavascript(
            source: 'goToHref(${jsonEncode(href)})');
    }());
  }

  void turnPageFromKeyboard(int direction) {
    if (direction != 1 && direction != -1) return;
    if (readingPageKey.currentState?.isReflowReading == true) {
      unawaited(readingPageKey.currentState!.reflowReader?.turn(direction));
      return;
    }
    webViewController.evaluateJavascript(
        source: 'window.turnPageFromKeyboard($direction)');
  }

  String? _pendingLinkedCfi;

  void goToLinkedCfi(String cfi) {
    if (!_readerReady) {
      _pendingLinkedCfi = cfi;
      return;
    }
    goToCfi(cfi);
  }

  void goToCfi(String cfi) {
    final anchor = DocumentReflowAnchor.parse(cfi);
    if (anchor != null) {
      unawaited(readingPageKey.currentState?.openReflowAnchor(anchor));
      return;
    }
    if (cfi.startsWith(DocumentReflowAnchor.prefix)) return;
    unawaited(() async {
      if (readingPageKey.currentState?.isReflowReading == true) {
        await readingPageKey.currentState?.closeDocumentReflow();
      }
      if (mounted)
        await webViewController.evaluateJavascript(
            source: 'goToCfi(${jsonEncode(cfi)});');
    }());
  }

  Future<void> goToDocumentPage(int page) async {
    final current =
        await (isImageEpub ? epubImageInfo(null) : pdfRegionInfo(null));
    if (current['page'] == page) return;
    final result = await webViewController.callAsyncJavaScript(
        functionBody: 'return await window.goToDocumentOriginalPage(page);',
        arguments: {'page': page});
    if (result?.error != null || result?.value != true)
      throw StateError('Original page navigation failed');
  }

  String get selectionChapterTitle =>
      readingPageKey.currentState?.reflowReader?.chapter ?? chapterTitle;

  void clearReaderSelection() {
    if (readingPageKey.currentState?.isReflowReading == true) {
      readingPageKey.currentState?.reflowReader?.clearSelection();
    } else {
      webViewController.evaluateJavascript(source: 'clearSelection()');
    }
  }

  Future<void> addAnnotation(BookNote bookNote) async {
    if (bookNote.cfi.startsWith(DocumentReflowAnchor.prefix)) {
      await readingPageKey.currentState?.reflowReader?.refreshNotes();
      return;
    }
    // JSON also safely handles quotes, backslashes and multiline excerpts.
    final result = await webViewController.callAsyncJavaScript(
        functionBody:
            'await window.addAnnotation(${jsonEncode(bookNote.toJson())});');
    if (result?.error != null) {
      throw StateError('Annotation rendering failed: ${result!.error}');
    }
  }

  void addBookmark(BookmarkModel bookmark) {
    webViewController.evaluateJavascript(source: '''
      addAnnotation({
        id: ${bookmark.id},
        type: 'bookmark',
        value: '${bookmark.cfi}',
        color: '#000000',
        note: 'None',
      })
      ''');
  }

  void addBookmarkHere() {
    webViewController.evaluateJavascript(source: '''
      addBookmarkHere()
      ''');
  }

  Future<void> removeAnnotation(String cfi) async {
    if (cfi.startsWith(DocumentReflowAnchor.prefix)) {
      await readingPageKey.currentState?.reflowReader?.refreshNotes();
      return;
    }
    final result = await webViewController.callAsyncJavaScript(
        functionBody: 'await window.removeAnnotation(${jsonEncode(cfi)});');
    if (result?.error != null) {
      throw StateError('Annotation removal failed: ${result!.error}');
    }
  }

  void clearSearch() {
    ref.read(tocSearchProvider.notifier).clear();
    _clearSearchHighlights();
  }

  Future<void>? _searchNavigation;

  Future<void> navigateSearch(String target) async {
    if (_searchNavigation != null) return;
    final state = ref.read(tocSearchProvider);
    if (!state.isActive) return;
    final notifier = ref.read(tocSearchProvider.notifier);
    notifier.setNavigating(true);
    try {
      _searchNavigation = _goToSearchCfi(target);
      await _searchNavigation;
      if (mounted && ref.read(tocSearchProvider).requestId == state.requestId) {
        notifier.selectMatch(target);
      }
    } catch (_) {
      if (mounted)
        AnxToast.show(ModuStrings.text(
            context, '无法跳转到搜索结果，请重试', 'Could not open this search result'));
    } finally {
      _searchNavigation = null;
      if (mounted) {
        notifier.setNavigating(false);
      }
    }
  }

  Future<void> _goToSearchCfi(String target) async {
    await readingPageKey.currentState?.closeDocumentReflow();
    final result = await webViewController.callAsyncJavaScript(
        functionBody:
            'return await window.goToSearchResult(${jsonEncode(target)})');
    if (result?.error != null || result?.value != true) {
      throw StateError('Search navigation failed');
    }
  }

  void moveSearch(int direction) {
    final state = ref.read(tocSearchProvider);
    final index = state.activeIndex + direction;
    final matches = state.matches;
    if (index >= 0 && index < matches.length) {
      unawaited(navigateSearch(matches[index].cfi));
    }
  }

  Future<void> closeBookSearch({bool returnToOrigin = false}) async {
    final origin = ref.read(tocSearchProvider).originCfi;
    final pending = _searchNavigation;
    clearSearch();
    try {
      await pending;
    } catch (_) {
      // A failed hit navigation must not prevent returning to the saved page.
      // navigateSearch already reports that navigation failure.
    }
    try {
      if (mounted && returnToOrigin && origin?.isNotEmpty == true) {
        await _goToSearchCfi(origin!);
      }
    } catch (_) {
      if (mounted)
        AnxToast.show(ModuStrings.text(
            context, '无法返回原阅读位置', 'Could not return to the original position'));
    }
  }

  void search(String text) {
    final sanitized = text.trim();
    if (sanitized.isEmpty) {
      clearSearch();
      return;
    }
    _clearSearchHighlights();
    ref.read(tocSearchProvider.notifier).start(sanitized, originCfi: cfi);
    final requestId = ref.read(tocSearchProvider).requestId;
    webViewController.evaluateJavascript(source: '''
      search(${jsonEncode(sanitized)}, {
        'requestId': $requestId,
        'scope': 'book',
        'matchCase': false,
        'matchDiacritics': false,
        'matchWholeWords': false,
      })
    ''');
  }

  void _clearSearchHighlights() {
    webViewController.evaluateJavascript(source: "clearSearch()");
  }

  Future<String> initTts({String? fromCfi}) async {
    _ttsMaxCharacters = Prefs().ttsBufferSettings.maxCharacters;
    final reflow = readingPageKey.currentState?.reflowReader;
    if (reflow != null) return reflow.speechText(fromCfi);
    final result = await waitForTtsReader(
        'start',
        () => webViewController.callAsyncJavaScript(
              functionBody: _ttsModeScript +
                  (fromCfi != null && fromCfi.isNotEmpty
                      ? 'return await window.ttsFromCfi(${jsonEncode(fromCfi)})'
                      : 'return await window.ttsHere()'),
            ));
    if (result?.error != null) {
      throw StateError('TTS initialization failed: ${result!.error}');
    }
    return ttsTextResult(result?.value, error: result?.error);
  }

  Future<void> ttsStop() async {
    if (readingPageKey.currentState?.isReflowReading == true) return;
    await webViewController.callAsyncJavaScript(
        functionBody: 'return ttsStop()');
  }

  Future<void> returnToTtsPosition() async {
    if (readingPageKey.currentState?.isReflowReading == true) return;
    final result = await webViewController.callAsyncJavaScript(
        functionBody: 'return await window.ttsReturnToPosition()');
    if (result?.error != null) {
      throw StateError('TTS position navigation failed: ${result!.error}');
    }
  }

  Future<void> setTtsBackground(bool background) async {
    try {
      await webViewController.evaluateJavascript(
          source: 'window.ttsSetBackground?.($background)');
    } catch (_) {
      // A lifecycle event may precede WebView creation or follow disposal.
    }
  }

  int _ttsMaxCharacters = 240;
  String get _ttsModeScript =>
      'window.ttsSetParagraphMode(${getTtsService(Prefs().ttsService).isOnline}, $_ttsMaxCharacters);\n';

  Future<String> _ttsTextCall(String function) async {
    if (readingPageKey.currentState?.isReflowReading == true) return '';
    final result = await waitForTtsReader(
        function,
        () => webViewController.callAsyncJavaScript(
            functionBody: '${_ttsModeScript}return await $function()'));
    if (result?.error != null) {
      throw StateError('TTS navigation failed: ${result!.error}');
    }
    return ttsTextResult(result?.value, error: result?.error);
  }

  Future<String> ttsNext() => _ttsTextCall('ttsNext');
  Future<String> ttsPrev() => _ttsTextCall('ttsPrev');
  Future<String> ttsPrevSection() => _ttsTextCall('ttsPrevSection');
  Future<String> ttsNextSection() => _ttsTextCall('ttsNextSection');

  Future<String> ttsPrepare() async {
    final reflow = readingPageKey.currentState?.reflowReader;
    if (reflow != null) return reflow.speechText(null);
    return await webViewController.evaluateJavascript(source: "ttsPrepare()");
  }

  TtsSentence? _parseTtsSentence(dynamic value) {
    if (value is Map<dynamic, dynamic>) {
      try {
        return TtsSentence.fromMap(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  List<TtsSentence> _parseTtsSentences(dynamic value) {
    if (value is! List) return const [];

    final sentences = <TtsSentence>[];
    for (final item in value) {
      final sentence = _parseTtsSentence(item);
      if (sentence != null) {
        sentences.add(sentence);
      }
    }
    return sentences;
  }

  Future<TtsSentence?> ttsCurrentDetail() async {
    final result = await webViewController.callAsyncJavaScript(
      functionBody: 'return ttsCurrentDetail()',
    );
    if (result?.error != null) {
      throw StateError('TTS cursor failed: ${result!.error}');
    }
    return _parseTtsSentence(result?.value);
  }

  Future<List<TtsSentence>> ttsCollectDetails({
    required int count,
    bool includeCurrent = false,
    int offset = 1,
  }) async {
    final result = await waitForTtsReader(
        'collect',
        () => webViewController.callAsyncJavaScript(
              functionBody:
                  'return ttsCollectDetails($count, ${includeCurrent ? 'true' : 'false'}, $offset)',
            ));
    if (result?.error != null) {
      throw StateError('TTS collection failed: ${result!.error}');
    }
    return _parseTtsSentences(result?.value);
  }

  Future<void> ttsHighlightByCfi(String cfi) async {
    await webViewController.callAsyncJavaScript(
      functionBody: 'return ttsHighlightByCfi(${jsonEncode(cfi)})',
    );
  }

  Future<bool> isFootNoteOpen() async => (await webViewController
      .evaluateJavascript(source: "window.isFootNoteOpen()"));

  void backHistory() {
    webViewController.evaluateJavascript(source: "back()");
  }

  void forwardHistory() {
    webViewController.evaluateJavascript(source: "forward()");
  }

  void closeHistory() {
    setState(() {
      showHistory = false;
      canGoBack = false;
      canGoForward = false;
    });
    // End this jump trail as well as hiding it. Ordinary reading/sync must not
    // bring a dismissed return capsule back; a new deliberate jump still can.
    webViewController.evaluateJavascript(source: 'clearNavigationHistory()');
  }

  void refreshToc() {
    webViewController.evaluateJavascript(source: "refreshToc()");
  }

  Future<String> theChapterContent() async =>
      await webViewController.evaluateJavascript(
        source: "theChapterContent()",
      );

  Future<String> previousContent(int count) async =>
      await webViewController.evaluateJavascript(
        source: "previousContent($count)",
      );

  Future<String> _getCurrentChapterContent({int? maxCharacters}) async {
    final raw = await theChapterContent();
    return _normalizeChapterContent(raw, maxCharacters);
  }

  Future<String> _getChapterContentByHref(
    String href, {
    int? maxCharacters,
  }) async {
    if (href.isEmpty) {
      return '';
    }

    final result = await webViewController.callAsyncJavaScript(
      functionBody:
          'return await getChapterContentByHref("${href.replaceAll('"', '\\"')}")',
    );

    final value = result?.value;
    if (value is String) {
      return _normalizeChapterContent(value, maxCharacters);
    }
    return '';
  }

  String _normalizeChapterContent(String? content, int? maxCharacters) {
    if (content == null || content.isEmpty) {
      return '';
    }
    final trimmed = content.trim();
    if (maxCharacters != null &&
        maxCharacters > 0 &&
        trimmed.length > maxCharacters) {
      return trimmed.substring(0, maxCharacters);
    }
    return trimmed;
  }

  void _registerChapterContentBridge() {
    ref.read(chapterContentBridgeProvider.notifier).state =
        ChapterContentHandlers(
      fetchCurrentChapter: ({int? maxCharacters}) =>
          _getCurrentChapterContent(maxCharacters: maxCharacters),
      fetchChapterByHref: (href, {int? maxCharacters}) =>
          _getChapterContentByHref(href, maxCharacters: maxCharacters),
      fetchPreviousContent: ({int? maxCharacters}) async {
        final requestedCharacters = maxCharacters ?? 48000;
        final content = await previousContent(requestedCharacters);
        return _normalizeChapterContent(content, maxCharacters);
      },
    );
  }

  Future<void> _handleExternalLink(dynamic rawLink) async {
    String? normalizeExternalLink(dynamic raw) {
      if (raw == null) {
        return null;
      }
      if (raw is String && raw.trim().isNotEmpty) {
        return raw.trim();
      }
      if (raw is Map && raw['href'] is String) {
        final href = raw['href'].toString().trim();
        return href.isEmpty ? null : href;
      }
      return null;
    }

    final link = normalizeExternalLink(rawLink);
    if (!mounted || link == null) {
      return;
    }

    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme.isEmpty || uri.scheme == 'javascript') {
      AnxLog.warning('Ignored invalid external link: $link');
      return;
    }

    final shouldOpen = await showDialog<bool>(
      animationStyle: AppMotion.style,
      context: context,
      builder: (dialogContext) {
        final l10n = L10n.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.readingPageOpenExternalLinkTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.readingPageOpenExternalLinkMessage),
              const SizedBox(height: 8),
              SelectableText(link),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.readingPageOpenExternalLinkAction),
            ),
          ],
        );
      },
    );

    if (shouldOpen != true) {
      return;
    }

    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      AnxLog.warning('Failed to open external link: $link');
    }
  }

  void onClick(Map<String, dynamic> location) {
    readingPageKey.currentState?.resetAwakeTimer();
    if (contextMenuEntry != null) {
      removeOverlay();
      return;
    }
    // Native WebView clicks do not automatically release a Flutter AI text
    // field. This callback runs after JS has excluded text-selection clicks.
    readingPageKey.currentState?.focusReaderFromTap();
    final x = location['x'];
    final y = location['y'];
    final part = coordinatesToPart(x, y);

    PageTurningType action;
    final pageTurnMode = PageTurnMode.fromCode(Prefs().pageTurnMode);

    if (pageTurnMode == PageTurnMode.simple) {
      // Use predefined page turning types
      final currentPageTurningType = Prefs().pageTurningType;
      final pageTurningType = pageTurningTypes[currentPageTurningType];
      action = pageTurningType[part];

      // Apply swap if enabled
      if (Prefs().swapPageTurnArea) {
        if (action == PageTurningType.prev) {
          action = PageTurningType.next;
        } else if (action == PageTurningType.next) {
          action = PageTurningType.prev;
        }
      }
    } else {
      // Use custom configuration
      final customConfig = Prefs().customPageTurnConfig;
      action = PageTurningType.values[customConfig[part]];
    }

    // Disable mouse/touch page turning when keyboard shortcuts are enabled
    if (Prefs().keyboardShortcutTurnPage) {
      // Only allow menu action, disable prev/next page turning
      if (action == PageTurningType.prev || action == PageTurningType.next) {
        return;
      }
    }

    switch (action) {
      case PageTurningType.prev:
        prevPage();
        break;
      case PageTurningType.next:
        nextPage();
        break;
      case PageTurningType.menu:
        widget.showOrHideAppBarAndBottomBar(true);
        break;
      case PageTurningType.none:
        break;
    }
  }

  Future<void> renderAnnotations(InAppWebViewController controller) async {
    List<BookNote> annotationList =
        await bookNoteDao.selectBookNotesByBookId(widget.book.id);
    await controller.callAsyncJavaScript(
        functionBody: 'await window.replaceReadingAnnotations('
            '${jsonEncode(annotationList.where((e) => !e.cfi.startsWith(DocumentReflowAnchor.prefix)).map((e) => e.toJson()).toList())});');
    await readingPageKey.currentState?.reflowReader?.refreshNotes();
  }

  Future<void> refreshReadingAfterSync() {
    if (!mounted || !_readerReady || widget.cfi != null) return Future.value();
    _refreshRequested = true;
    return _syncRefresh ??= _refreshSyncedReader().whenComplete(() {
      _syncRefresh = null;
      if (_refreshRequested && mounted) unawaited(refreshReadingAfterSync());
    });
  }

  Future<void> _refreshSyncedReader() async {
    try {
      while (_refreshRequested && mounted) {
        _refreshRequested = false;
        final previous = _progress.current;
        final latest = await _progress.refresh();
        if (previous?.revision != latest.revision) _syncRestoreAttempts = 0;
        if (!mounted) return;
        if (latest.deleted) {
          _remotePositionPending = true;
          return;
        }
        if (latest.position.isNotEmpty &&
            (_remotePositionPending ||
                previous?.revision != latest.revision ||
                !_readerPositionInitialized)) {
          _remotePositionPending = true;
          final result = await webViewController.callAsyncJavaScript(
              functionBody: 'return await window.restoreSyncedReadingPosition('
                  '${jsonEncode(latest.position)}, ${!_readerPositionInitialized});');
          if (!mounted) return;
          if (result?.value != true) {
            _syncRefreshRetry?.cancel();
            if (++_syncRestoreAttempts >= 3) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ModuStrings.text(
                      context,
                      '同步后的阅读位置暂时无法打开，请重新打开书籍。未覆盖云端进度。',
                      'Could not open the synced position. Reopen the book; the synced progress was not overwritten.'))));
              return;
            }
            _syncRefreshRetry = Timer(const Duration(milliseconds: 400), () {
              if (mounted) unawaited(refreshReadingAfterSync());
            });
            return;
          }
          _remotePositionPending = false;
          _syncRestoreAttempts = 0;
          setState(() {
            percentage = latest.percentage;
          });
          ref
              .read(currentReadingProvider.notifier)
              .update(percentage: percentage);
        }
        _readerPositionInitialized = true;
        widget.book.lastReadPosition = latest.position;
        widget.book.readingPercentage = latest.percentage;
        await renderAnnotations(webViewController);
      }
    } catch (error) {
      // No private CFI, note content or server data in diagnostics.
      AnxLog.warning('Reader sync refresh failed: ${error.runtimeType}');
    }
  }

  bool _readerPositionInitialized = false;

  Future<void> _recordReadingAction(String position, double fraction,
      {dynamic pdfRegion}) async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null &&
        lifecycle != AppLifecycleState.resumed &&
        !TtsHandler().isPlaying) {
      return;
    }
    if (!_readerReady ||
        !_readerPositionInitialized ||
        _remotePositionPending ||
        widget.cfi != null ||
        position.isEmpty) {
      return;
    }
    try {
      final accepted = await _progress.record(position, fraction,
          generation: _progress.generation);
      if (!mounted) return;
      if (!accepted) {
        _remotePositionPending = true;
        await refreshReadingAfterSync();
        return;
      }
      widget.book.lastReadPosition = position;
      widget.book.readingPercentage = fraction;
      if (supportsDocumentImages) {
        await PdfReadingStateStore(Prefs().prefs).savePosition(
            cssBookKey, position, pdfRegion,
            enabled: pdfPanelReading);
      }
      ref.read(bookListProvider.notifier).refresh();
    } catch (error) {
      AnxLog.warning('Reading action save failed: ${error.runtimeType}');
    }
  }

  void getThemeColor() {
    final theme = readingThemeForDisplay(Prefs(),
        themes: widget.initialThemes, isDarkMode: isDarkMode);
    backgroundColor = theme.backgroundColor;
    textColor = theme.textColor;
  }

  void refreshReadingTheme() {
    if (!mounted) return;
    getThemeColor();
    changeTheme(ReadTheme(
      backgroundColor: backgroundColor!,
      textColor: textColor!,
      backgroundImagePath: '',
    ));
    changeBgimgEffect();
  }

  Future<void> setHandler(InAppWebViewController controller) async {
    controller.addJavaScriptHandler(
        handlerName: 'onPdfReadingSettings',
        callback: (_) {
          if (!mounted) return null;
          documentReadingMode.value =
              DocumentReadingModeStore(Prefs().prefs).read(widget.book);
          // Text EPUB/TXT/other formats must never restore a stale image mode.
          if (!supportsDocumentImages) return {'mode': 'standard'};
          final store = PdfReadingStateStore(Prefs().prefs);
          final state = store.read(cssBookKey);
          return {
            ...state,
            'mode': documentReadingMode.value.storageValue,
            'enabled': pdfPanelReading,
            // Explicit note/link navigation must not restore an unrelated panel.
            if (widget.cfi != null) 'position': null,
            'layout':
                DocumentLayoutStore(Prefs().prefs).read(cssBookKey).toJson(),
          };
        });
    controller.addJavaScriptHandler(
        handlerName: 'onReaderWordBounds',
        callback: (args) {
          if (!mounted || !AnxPlatform.isAndroid || args.isEmpty) return null;
          return ReaderWordSelection.bounds(args.first);
        });
    controller.addJavaScriptHandler(
        handlerName: 'onReaderChapterState',
        callback: (args) {
          if (!mounted || args.isEmpty || args.first is! Map) return;
          final data = args.first as Map;
          setState(() {
            _chapterLoading = data['state'] == 'loading';
            _chapterLoadFailed = data['state'] == 'failed';
            _chapterFontFailed = _chapterLoadFailed && data['reason'] == 'font';
            if (data['state'] == 'ready') _readerLoadFailed = false;
          });
        });
    controller.addJavaScriptHandler(
        handlerName: 'onReaderLoadError',
        callback: (_) => _showReaderLoadFailure());
    controller.addJavaScriptHandler(
        handlerName: 'onLoadEnd',
        callback: (args) async {
          if (!mounted) return;
          setState(() {
            _readerReady = true;
            _readerLoadFailed = false;
          });
          readingPageKey.currentState?.refreshDocumentReaderActivity();
          // Android can hide system bars while the chapter is still loading.
          // The Flutter frame already uses the new safe area; replay the DOM
          // gutters that could not be applied before the renderer was ready.
          if (_verticalInsetsPending) {
            _verticalInsetsPending = false;
            changeStyle(null);
          }
          await refreshReadingAfterSync();
          if (!mounted) return;
          if (quickMarkEnabled) await setQuickMarkEnabled(true);
          // Opening/reloading a reader always requires a new explicit start.
          _translationSession.stop();
          translationMode.value = TranslationModeEnum.off;
          Prefs()
              .setBookTranslationMode(widget.book.id, TranslationModeEnum.off);
          if (!mounted) return;
          widget.onLoadEnd();
          final linkedCfi = _pendingLinkedCfi;
          _pendingLinkedCfi = null;
          if (linkedCfi != null) goToCfi(linkedCfi);
        });

    controller.addJavaScriptHandler(
        handlerName: 'onRelocated',
        callback: (args) {
          Map<String, dynamic> location = args[0];
          if (!mounted) return;
          _observeEinkPage(location);
          if (cfi == location['cfi'] &&
              writingMode.code == location['writingMode'] &&
              chapterCurrentPage == location['chapterCurrentPage'] &&
              chapterTotalPages == location['chapterTotalPages'] &&
              currentChapter == location['currentChapter'] &&
              totalChapters == location['totalChapters'] &&
              bookCurrentPage == location['bookCurrentPage'] &&
              bookTotalPages == location['bookTotalPages']) {
            if (location['readingAction'] == true) {
              unawaited(_recordReadingAction(cfi, percentage,
                  pdfRegion: location['pdfRegion']));
            }
            return;
          }
          // if (chapterHref != location['chapterHref']) {
          //   refreshToc();
          // }
          setState(() {
            cfi = location['cfi'] ?? '';
            percentage =
                double.tryParse(location['percentage'].toString()) ?? 0.0;
            chapterTitle = location['chapterTitle'] ?? '';
            chapterHref = location['chapterHref'] ?? '';
            chapterCurrentPage = location['chapterCurrentPage'] ?? 0;
            chapterTotalPages = location['chapterTotalPages'] ?? 0;
            currentChapter = location['currentChapter'] ?? 0;
            totalChapters = location['totalChapters'] ?? 0;
            bookCurrentPage = location['bookCurrentPage'] ?? 0;
            bookTotalPages = location['bookTotalPages'] ?? 0;
            bookmarkExists = location['bookmark']['exists'] ?? false;
            bookmarkCfi = location['bookmark']['cfi'] ?? '';
            writingMode =
                WritingModeEnum.fromCode(location['writingMode'] ?? '');
          });
          readingProgress.value = ReaderProgress(
            percentage: percentage,
            chapterTitle: chapterTitle,
            currentChapter: currentChapter,
            totalChapters: totalChapters,
            currentPage: chapterCurrentPage,
            totalPages: chapterTotalPages,
            chapters: readingProgress.value.chapters,
          );
          if (AnxPlatform.isMacOS) {
            // Only update labels. changeStyle here would repaginate and emit
            // another relocation on every page turn.
            controller.evaluateJavascript(
                source: 'window.updateVerticalPageChrome?.('
                    '${jsonEncode(_webVerticalChrome)})');
          }
          ref.read(currentReadingProvider.notifier).update(
                cfi: cfi,
                percentage: percentage,
                chapterTitle: chapterTitle,
                chapterHref: chapterHref,
                chapterCurrentPage: chapterCurrentPage,
                chapterTotalPages: chapterTotalPages,
              );
          widget.updateParent();
          if (location['readingAction'] == true) {
            unawaited(_recordReadingAction(cfi, percentage,
                pdfRegion: location['pdfRegion']));
          }
          readingPageKey.currentState?.resetAwakeTimer();
        });
    controller.addJavaScriptHandler(
        handlerName: 'onTtsChapter',
        callback: (args) {
          if (!mounted || args.isEmpty || args.first is! Map) return;
          final title = (args.first as Map)['chapterTitle'];
          if (title is String) {
            TtsHandler().updateChapter(bookId: book.id, chapter: title);
          }
        });
    controller.addJavaScriptHandler(
        handlerName: 'onTtsProgress',
        callback: (args) {
          if (!mounted ||
              !TtsHandler().isPlaying ||
              args.isEmpty ||
              args.first is! Map) return;
          final value = args.first as Map;
          final position = value['cfi'];
          final progress = value['percentage'];
          if (position is! String ||
              progress is! num ||
              !progress.isFinite ||
              progress < 0 ||
              progress > 1) return;
          unawaited(_recordReadingAction(position, progress.toDouble()));
        });
    controller.addJavaScriptHandler(
        handlerName: 'onClick',
        callback: (args) {
          Map<String, dynamic> location = args[0];
          onClick(location);
        });
    controller.addJavaScriptHandler(
      handlerName: 'onExternalLink',
      callback: (args) async {
        final payload = args.isNotEmpty ? args.first : null;
        await _handleExternalLink(payload);
      },
    );
    controller.addJavaScriptHandler(
        handlerName: 'onSetToc',
        callback: (args) {
          List<dynamic> t = args[0];
          final toc = t.map((i) => TocItem.fromJson(i)).toList();
          ref.read(bookTocProvider.notifier).setToc(toc);
        });
    controller.addJavaScriptHandler(
        handlerName: 'onSetProgressChapters',
        callback: (args) {
          if (!mounted || args.isEmpty || args.first is! List) return;
          final chapters = (args.first as List)
              .map((raw) => ReaderProgressChapter.fromJson(
                  Map<String, dynamic>.from(raw as Map)))
              .toList();
          readingProgress.value =
              readingProgress.value.copyWithChapters(chapters);
        });
    controller.addJavaScriptHandler(
        handlerName: 'onQuickMark',
        callback: (args) async {
          if (!mounted ||
              !AnxPlatform.isMobile ||
              !quickMarkEnabled ||
              args.isEmpty ||
              args.first is! Map) return null;
          final data = args.first as Map;
          if (data['cfi'] is! String || data['text'] is! String) return null;
          try {
            final result = await _quickMarks.saveStroke(
                bookId: book.id,
                cfi: data['cfi'] as String,
                text: data['text'] as String,
                chapter: chapterTitle,
                color: Prefs().annotationColor,
                merge: data['merge'] is Map ? data['merge'] as Map : null);
            return result.toJson();
          } catch (_) {
            _quickMarkError();
            return null;
          }
        });
    controller.addJavaScriptHandler(
        handlerName: 'onCustomHighlightStatus',
        callback: (args) {
          if (!mounted || args.isEmpty) return;
          final messages = {
            'unsupported': ModuStrings.text(
                context,
                '当前阅读内核不支持正则高亮，请更新系统 WebView；普通 CSS 仍可使用。',
                'This web engine does not support regex highlights. Update WebView; layout CSS still works.'),
            'timeout': ModuStrings.text(context, '高亮规则匹配超时，已停止，请简化正则表达式。',
                'Highlight matching timed out. Please simplify the regex.'),
            'invalid': ModuStrings.text(context, '部分高亮正则有误，已跳过无效规则。',
                'Invalid highlight expressions were skipped.'),
            'limited': ModuStrings.text(context, '本章高亮达到安全上限，仅显示部分匹配。',
                'Chapter highlight limit reached; showing partial matches.'),
            'error': ModuStrings.text(context, '高亮规则暂时无法应用，正文阅读不受影响。',
                'Could not apply highlights; reading is unaffected.'),
          };
          final message = messages[args.first];
          if (message != null) AnxToast.show(message);
        });
    controller.addJavaScriptHandler(
        handlerName: 'onQuickMarkError',
        callback: (args) {
          if (AnxPlatform.isMobile) _quickMarkError();
        });
    controller.addJavaScriptHandler(
        handlerName: 'onSelectionEnd',
        callback: (args) {
          if (_selectionClearLocked) return;
          Map<String, dynamic> location = args[0];
          if (AnxPlatform.isMobile &&
              quickMarkEnabled &&
              location['footnote'] != true) return;
          removeOverlay();
          String cfi = location['cfi'];
          String text = location['text'];
          bool footnote = location['footnote'];
          final rawContextText = location['contextText']?.toString();
          _lastSelectionContextText =
              (rawContextText?.trim().isEmpty ?? true) ? null : rawContextText;
          double left = (location['pos']['left'] as num).toDouble();
          double top = (location['pos']['top'] as num).toDouble();
          double right = (location['pos']['right'] as num).toDouble();
          double bottom = (location['pos']['bottom'] as num).toDouble();
          showContextMenu(
            context,
            left,
            top,
            right,
            bottom,
            text,
            cfi,
            null,
            footnote,
            writingMode.isVertical ? Axis.vertical : Axis.horizontal,
            contextText: _lastSelectionContextText,
            annotationIds: footnote
                ? const []
                : (location['annotationIds'] as List? ?? const [])
                    .whereType<int>()
                    .where((id) => id > 0)
                    .toSet()
                    .toList(),
          );
        });
    controller.addJavaScriptHandler(
        handlerName: 'onSelectionCleared',
        callback: (args) {
          if (readingPageKey.currentState?.isReflowReading == true) return;
          if (_selectionClearLocked) {
            _selectionClearPending = true;
            return;
          }
          _lastSelectionContextText = null;
          removeOverlay();
        });
    controller.addJavaScriptHandler(
        handlerName: 'onAnnotationClick',
        callback: (args) {
          if (_selectionClearLocked) return;
          Map<String, dynamic> annotation = args[0];
          if (annotation['quickMark'] == true &&
              (!AnxPlatform.isMobile ||
                  !quickMarkEnabled ||
                  !Prefs().quickMarkShowMenu)) return;
          removeOverlay();

          if (annotation['annotation'] == null) {
            // Check if TTS is active and the click is on the currently read text
            final currentTtsState = TtsHandler().ttsStateNotifier.value;
            if (currentTtsState == TtsStateEnum.playing ||
                currentTtsState == TtsStateEnum.paused) {
              if (currentTtsState == TtsStateEnum.playing) {
                audioHandler.pause();
              } else {
                audioHandler.play();
              }
              return;
            }
          }

          int id = annotation['annotation']['id'];
          String cfi = annotation['annotation']['value'];
          String note = annotation['annotation']['note'];
          final rawContextText = annotation['contextText']?.toString();
          _lastSelectionContextText =
              (rawContextText?.trim().isEmpty ?? true) ? null : rawContextText;
          double left = (annotation['pos']['left'] as num).toDouble();
          double top = (annotation['pos']['top'] as num).toDouble();
          double right = (annotation['pos']['right'] as num).toDouble();
          double bottom = (annotation['pos']['bottom'] as num).toDouble();
          showContextMenu(
            context,
            left,
            top,
            right,
            bottom,
            note,
            cfi,
            id,
            false,
            writingMode.isVertical ? Axis.vertical : Axis.horizontal,
            contextText: _lastSelectionContextText,
          );
        });
    controller.addJavaScriptHandler(
      handlerName: 'onSearch',
      callback: (args) {
        Map<String, dynamic> search = args[0];
        final state = ref.read(tocSearchProvider);
        if (!state.isActive || search['requestId'] != state.requestId)
          return null;
        final tocSearch = ref.read(tocSearchProvider.notifier);
        if (search['error'] == true) {
          tocSearch.updateProgress(1);
          AnxToast.show(ModuStrings.text(
              context, '书内搜索失败，请重试', 'Book search failed; please retry'));
        } else if (search['process'] != null) {
          final progress = search['process'].toDouble();
          tocSearch.updateProgress(progress);
        } else {
          // Collect results without changing the reading position. Navigation
          // requires an explicit result tap or search-toolbar action.
          tocSearch.addResult(SearchResultModel.fromJson(search));
        }
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'renderAnnotations',
      callback: (args) {
        renderAnnotations(controller);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onPushState',
      callback: (args) {
        Map<String, dynamic> state = args[0];
        if (!mounted) return;
        setState(() {
          canGoBack = state['canGoBack'];
          canGoForward = state['canGoForward'];
          showHistory = canGoBack || canGoForward;
        });
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onImageClick',
      callback: (args) {
        if (!mounted || supportsDocumentImages) return;
        String image = args[0];
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => ImageViewer(
                      image: image,
                      bookName: widget.book.title,
                    )));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onFootnoteClose',
      callback: (args) {
        removeOverlay();
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'onPullUp',
      callback: (args) {
        widget.showOrHideAppBarAndBottomBar(true);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'handleBookmark',
      callback: (args) async {
        Map<String, dynamic> detail = args[0]['detail'];
        bool remove = args[0]['remove'];
        String cfi = detail['cfi'] ?? '';
        double percentage = double.parse(detail['percentage'].toString());
        String content = detail['content'];

        if (remove) {
          ref.read(bookmarkProvider(widget.book.id).notifier).removeBookmark(
                cfi: cfi,
              );
          bookmarkCfi = '';
          bookmarkExists = false;
        } else {
          BookmarkModel bookmark = await ref
              .read(BookmarkProvider(widget.book.id).notifier)
              .addBookmark(
                BookmarkModel(
                  bookId: widget.book.id,
                  cfi: cfi,
                  percentage: percentage,
                  content: content,
                  chapter: chapterTitle,
                  updateTime: DateTime.now(),
                  createTime: DateTime.now(),
                ),
              );
          bookmarkCfi = cfi;
          bookmarkExists = true;
          addBookmark(bookmark);
        }
        widget.updateParent();
        setState(() {});
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'translateText',
      callback: (args) async {
        try {
          if (!mounted || args.length < 2 || args[1] is! int) return null;
          String text = args[0];
          final service = Prefs().fullTextTranslateService;
          final from = Prefs().fullTextTranslateFrom;
          final to = Prefs().fullTextTranslateTo;

          final provider = service.provider;
          return await _translationSession.translate(
              args[1] as int,
              (runner) => provider is AiTranslateProvider
                  ? provider.translateStream(text, from, to,
                      isFullText: true, requestRunner: runner)
                  : provider is MicrosoftFreeTranslateProvider
                      ? provider.translateStream(text, from, to,
                          isFullText: true, whenCancelled: runner.whenCancelled)
                      : provider is DeepLTranslateProvider
                          ? provider.translateStream(text, from, to,
                              isFullText: true,
                              whenCancelled: runner.whenCancelled)
                          : provider.translateStream(text, from, to,
                              isFullText: true));
        } on TranslationCancelled {
          return null;
        } catch (e) {
          AnxLog.warning('Reader translation request failed: ${e.runtimeType}');
          if (mounted &&
              _translationSession.enabled &&
              args.length > 1 &&
              args[1] == _translationSession.generation) {
            unawaited(
                setTranslationMode(TranslationModeEnum.off).catchError((_) {}));
            AnxToast.show(ModuStrings.text(context, '翻译失败，已停止。请检查翻译服务后重试。',
                'Translation failed and stopped. Check the service and try again.'));
          }
          return null;
        }
      },
    );
  }

  Future<void> onWebViewCreated(InAppWebViewController controller) async {
    if (AnxPlatform.isAndroid) {
      await InAppWebViewController.setWebContentsDebuggingEnabled(kDebugMode);
    }
    webViewController = controller;
    setHandler(controller);
    _registerChapterContentBridge();

    // Translation starts only from an explicit action in this reader session.
  }

  void removeOverlay() {
    _selectionClearLocked = false;
    _selectionClearPending = false;
    if (contextMenuEntry == null || contextMenuEntry?.mounted == false) return;
    contextMenuEntry?.remove();
    contextMenuEntry = null;
  }

  Future<void> _handlePointerEvents(PointerEvent event) async {
    if (await isFootNoteOpen() || Prefs().pageTurnStyle == PageTurn.scroll) {
      return;
    }
    // Disable scroll wheel page turning when keyboard shortcuts are enabled
    if (Prefs().keyboardShortcutTurnPage) {
      return;
    }
    if (event is PointerScrollEvent) {
      _accumulatedScrollDelta += event.scrollDelta.dy;

      _scrollDebounceTimer?.cancel();
      _scrollDebounceTimer = Timer(const Duration(milliseconds: 80), () {
        if (_accumulatedScrollDelta.abs() >= _scrollThreshold) {
          if (_accumulatedScrollDelta > 0) {
            nextPage();
          } else {
            prevPage();
          }
        }
        _accumulatedScrollDelta = 0;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep the DOM gutters in sync with rotation/safe areas and UI text scaling.
    final insets = _verticalGeometry.toJson();
    if (!mapEquals(_lastVerticalInsets, insets)) {
      final hadInsets = _lastVerticalInsets != null;
      _lastVerticalInsets = insets;
      if (_readerReady) {
        changeStyle(null);
      } else if (hadInsets) {
        _verticalInsetsPending = true;
      }
    }
  }

  @override
  void initState() {
    if (widget.cfi?.startsWith(DocumentReflowAnchor.prefix) == true)
      _pendingLinkedCfi = widget.cfi;
    _progress = ReaderProgressSession(bookDao, widget.book.id);
    book = widget.book;
    // Read import-time evidence immediately; menu selection must not depend on
    // the asynchronous WebView bridge or re-inspect the book on opening.
    documentReadingMode.value =
        DocumentReadingModeStore(Prefs().prefs).read(widget.book);
    Prefs().addListener(_configureEinkRefresh);
    getThemeColor();

    contextMenu = ContextMenu(
      settings: ContextMenuSettings(hideDefaultSystemContextMenuItems: true),
      onCreateContextMenu: (hitTestResult) async {
        if (!mounted || !_readerReady || !AnxPlatform.isAndroid) {
          return;
        }
        try {
          await webViewController.evaluateJavascript(
            source: 'window.onNativeReaderLongPress?.(); void 0;',
          );
        } catch (_) {
          // A chapter may have closed while Android created its selection menu.
        }
      },
      onHideContextMenu: () {
        // removeOverlay();
      },
    );
    super.initState();
  }

  Future<void> saveReadingProgress() async {
    await _progress.flush();
  }

  void _showReaderLoadFailure() {
    if (!mounted || _readerReady || _readerLoadFailed) return;
    setState(() => _readerLoadFailed = true);
    AnxLog.warning('Reader initial load failed');
  }

  Future<void> _retryReaderChapter() async {
    setState(() {
      _readerLoadFailed = false;
      _chapterLoadFailed = false;
      _chapterFontFailed = false;
    });
    if (_readerReady || _chapterLoading) {
      await webViewController.evaluateJavascript(
          source: 'window.retryReaderChapter?.()');
    } else {
      await webViewController.reload();
    }
  }

  @override
  void dispose() {
    Prefs().removeListener(_configureEinkRefresh);
    _einkPageRefresh.dispose();
    _translationSession.stop();
    documentReadingMode.dispose();
    translationMode.dispose();
    readingProgress.dispose();
    _syncRefreshRetry?.cancel();
    _scrollDebounceTimer?.cancel();
    saveReadingProgress();
    removeOverlay();
    super.dispose();
  }

  InAppWebViewSettings initialSettings = InAppWebViewSettings(
    supportZoom: false,
    transparentBackground: true,
    isInspectable: kDebugMode,
    // Prefer Flutter's texture-layer composition for reader/UI overlays.
    // initSurfaceAndroidView retains the engine's platform fallback. The build
    // override allows device diagnostics without altering user preferences.
    useHybridComposition: const bool.fromEnvironment(
        'MODU_READER_HYBRID_COMPOSITION',
        defaultValue: false),
  );

  bool get isDarkMode =>
      Theme.of(navigatorKey.currentContext!).brightness == Brightness.dark;

  void changeReadingInfo() {
    changeStyle(null);
  }

  Widget _buildHistoryCapsule() {
    final l10n = L10n.of(context);
    final buttonColor = Color(int.parse('0x$textColor')).withAlpha(200);

    // Common button style for all history navigation buttons
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
      ),
    );

    // Helper method to create history navigation buttons
    Widget createHistoryButton(
        IconData icon, String label, VoidCallback onPressed) {
      return TextButton.icon(
        icon: Icon(icon, size: 18, color: buttonColor),
        label: Text(label, style: TextStyle(color: buttonColor, fontSize: 14)),
        onPressed: onPressed,
        style: buttonStyle,
      );
    }

    // Build buttons list
    final List<Widget> buttons = [];

    if (canGoBack) {
      buttons.add(createHistoryButton(
        Icons.arrow_back,
        l10n.historyBack,
        backHistory,
      ));
    }

    buttons.add(createHistoryButton(
      Icons.close,
      l10n.historyClose,
      closeHistory,
    ));

    if (canGoForward) {
      buttons.add(createHistoryButton(
        Icons.arrow_forward,
        l10n.historyForward,
        forwardHistory,
      ));
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainer
                    .withAlpha(123),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: buttons,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget readingInfoWidget() {
    if (_verticalPage) {
      return AnxPlatform.isMacOS ? const SizedBox.shrink() : _verticalChrome;
    }
    if (chapterCurrentPage == 0 && percentage == 0.0) {
      return const SizedBox();
    }

    final readingInfoColor = Color(int.parse('0x$textColor')).withAlpha(150);
    final iconColor = Color(int.parse('0x$textColor'));
    Future<int?>? batteryLevelFuture;

    Future<int?> loadBatteryLevel() {
      return batteryLevelFuture ??= readBatteryLevelSafely();
    }

    Widget getWidget(ReadingInfoEnum readingInfoEnum, TextStyle textStyle) {
      final chapterTitleWidget = Text(
        chapterTitle.isEmpty ? widget.book.title : chapterTitle,
        style: textStyle,
      );

      final chapterProgressWidget = Text(
        readingProgress.value.chapterProgress,
        style: textStyle,
      );
      final chapterPageProgressWidget = Text(
        readingProgress.value.chapterPageProgress,
        style: textStyle,
      );

      final bookProgressWidget =
          Text('${(percentage * 100).toStringAsFixed(2)}%', style: textStyle);

      final timeWidget = MinuteClock(textStyle: textStyle);

      Widget batteryWidget() => FutureBuilder<int?>(
          future: loadBatteryLevel(),
          builder: (context, snapshot) {
            final level = snapshot.data;
            if (level == null) return const SizedBox.shrink();
            return ReadingBatteryIndicator(
                level: level,
                color: iconColor,
                fontSize: textStyle.fontSize ?? 10);
          });

      Widget batteryAndTimeWidget() => Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              batteryWidget(),
              const SizedBox(width: 5),
              Flexible(child: timeWidget),
            ],
          );

      switch (readingInfoEnum) {
        case ReadingInfoEnum.chapterTitle:
          return chapterTitleWidget;
        case ReadingInfoEnum.chapterProgress:
          return chapterProgressWidget;
        case ReadingInfoEnum.chapterPageProgress:
          return chapterPageProgressWidget;
        case ReadingInfoEnum.bookProgress:
          return bookProgressWidget;
        case ReadingInfoEnum.battery:
          return batteryWidget();
        case ReadingInfoEnum.time:
          return timeWidget;
        case ReadingInfoEnum.batteryAndTime:
          return batteryAndTimeWidget();
        case ReadingInfoEnum.none:
          return const SizedBox(width: 30);
      }
    }

    final readingInfo = Prefs().readingInfo;

    final headerTextStyle = TextStyle(
      color: readingInfoColor,
      fontSize: readingInfo.header.fontSize,
      height: 1.2,
    );
    final footerTextStyle = TextStyle(
      color: readingInfoColor,
      fontSize: readingInfo.footer.fontSize,
      height: 1.2,
    );

    List<Widget> headerWidgets = [
      getWidget(readingInfo.header.left, headerTextStyle),
      getWidget(readingInfo.header.center, headerTextStyle),
      getWidget(readingInfo.header.right, headerTextStyle),
    ];

    List<Widget> footerWidgets = [
      getWidget(readingInfo.footer.left, footerTextStyle),
      getWidget(readingInfo.footer.center, footerTextStyle),
      getWidget(readingInfo.footer.right, footerTextStyle),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: readingInfo.header.verticalMargin,
            left: readingInfo.header.leftMargin,
            right: readingInfo.header.rightMargin,
          ),
          child: ReadingInfoLine(
            style: headerTextStyle,
            children: headerWidgets,
          ),
        ),
        const Spacer(),
        Padding(
          padding: EdgeInsets.only(
            bottom: readingInfo.footer.verticalMargin,
            left: readingInfo.footer.leftMargin,
            right: readingInfo.footer.rightMargin,
          ),
          child: ReadingInfoLine(
            style: footerTextStyle,
            children: footerWidgets,
          ),
        ),
      ],
    );
  }

  Widget buildWebviewWithIOSWorkaround(
      BuildContext context, String url, String initialCfi) {
    final webView = InAppWebView(
      webViewEnvironment: webViewEnvironment,
      initialUrlRequest: URLRequest(
        url: WebUri(
          generateUrl(
            url,
            initialCfi,
            cssBookKey: cssBookKey,
            backgroundColor: backgroundColor,
            textColor: textColor,
            isDarkMode: Theme.of(context).brightness == Brightness.dark,
            verticalPageInsets: _verticalGeometry.toJson(),
            verticalPageChrome: _webVerticalChrome,
          ),
        ),
      ),
      initialSettings: initialSettings,
      contextMenu: contextMenu,
      onLoadStop: (controller, uri) => onWebViewCreated(controller),
      onReceivedError: (_, request, __) {
        if (request.isForMainFrame == true) _showReaderLoadFailure();
      },
      onReceivedHttpError: (_, request, __) {
        if (request.isForMainFrame == true) _showReaderLoadFailure();
      },
      onConsoleMessage: webviewConsoleMessage,
    );

    if (!AnxPlatform.isIOS) {
      return SizedBox.expand(child: webView);
    }

    return SizedBox.expand(
      child: Stack(
        children: [
          webView,
          Positioned.fill(
            child: PointerInterceptor(
              intercepting: !_isTopOfNavigationStack,
              debug: false,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(syncDatabaseRevisionProvider, (_, __) {
      unawaited(refreshReadingAfterSync());
    });
    String url = Server().bookUrl(File(widget.book.fileFullPath));
    String initialCfi =
        widget.cfi?.startsWith(DocumentReflowAnchor.prefix) == true
            ? widget.book.lastReadPosition
            : widget.cfi ?? widget.book.lastReadPosition;

    return Listener(
      onPointerSignal: (event) {
        _handlePointerEvents(event);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            buildWebviewWithIOSWorkaround(context, url, initialCfi),
            readingInfoWidget(),
            Consumer(builder: (context, ref, _) {
              final state = ref.watch(tocSearchProvider);
              if (!state.isActive)
                return showHistory
                    ? _buildHistoryCapsule()
                    : const SizedBox.shrink();
              return Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 38),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: PointerInterceptor(
                              child: SearchNavigationBar(
                            state: state,
                            onSearch: () =>
                                readingPageKey.currentState?.searchHandler(),
                            onPrevious: () => moveSearch(-1),
                            onNext: () => moveSearch(1),
                            onReturn: () => unawaited(
                                closeBookSearch(returnToOrigin: true)),
                            onClose: () => unawaited(closeBookSearch()),
                          )),
                        ),
                      )));
            }),
            if (_readerLoadFailed || _chapterLoadFailed)
              ReaderLoadingStatus(
                failed: _readerLoadFailed || _chapterLoadFailed,
                fontFailed: _chapterFontFailed,
                onRetry: _retryReaderChapter,
              ),
          ],
        ),
      ),
    );
  }
}
