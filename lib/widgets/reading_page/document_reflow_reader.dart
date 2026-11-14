import 'package:modu_reader/widgets/settings/setting_help_title.dart';
import 'package:modu_reader/service/reading/reflow_css.dart';
import 'package:modu_reader/service/reading/text_filter.dart';
import 'package:modu_reader/page/reading_page.dart' show epubPlayerKey;
import 'package:modu_reader/utils/coordinates_to_part.dart';
import 'package:modu_reader/utils/desktop_wheel_zoom.dart';
import 'more_settings/page_turning/types_and_icons.dart';
import 'more_settings/page_turning/diagram.dart';
import 'reader_menu_appearance.dart';
import 'package:modu_reader/service/translate/official_api.dart';
import 'ocr_precache_settings.dart';
import 'reader_menu_group.dart';
import 'package:modu_reader/enums/translation_mode.dart';
import 'package:modu_reader/service/translate/document_page_translation.dart';
import 'package:modu_reader/service/translate/index.dart';
import 'package:modu_reader/service/translate/ai.dart';
import 'package:modu_reader/service/translate/classical_translation.dart';
import 'package:modu_reader/models/translation_text_style.dart';
import 'package:modu_reader/service/translate/reader_translation_modes.dart';
import 'package:modu_reader/service/translate/deepl.dart';
import 'package:modu_reader/service/translate/microsoft_free.dart';
import 'package:modu_reader/service/ocr/document_ocr_precache.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'dart:async';
import 'dart:convert';
import 'package:modu_reader/service/tts/tts_page_source.dart';
import 'package:modu_reader/service/ocr/document_reflow_loader.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/models/book_note.dart';
import 'package:modu_reader/service/book_player/reader_word_selection.dart';
import 'package:modu_reader/page/settings_page/ocr_model.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:modu_reader/service/ocr/document_text_style.dart';
import 'package:modu_reader/service/installed_fonts.dart';
import 'package:modu_reader/service/ocr/document_text_geometry.dart';
import 'package:modu_reader/service/book_player/reading_appearance.dart';
import 'package:modu_reader/service/ocr/local_ocr_service.dart';
import 'package:modu_reader/service/ocr/ocr_model_store.dart';
import 'package:modu_reader/service/ocr/ocr_models.dart';
import 'widget_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'document_text_style_dialog.dart';
import 'document_saved_text_actions.dart';
import '../common/app_scroll_behavior.dart';
import 'document_reader_surface.dart';
import 'progress_widget.dart';
import 'reader_settings_scroll_view.dart';
import 'package:modu_reader/models/reader_progress.dart';

typedef ReflowSelection = Future<void> Function(DocumentReflowAnchor anchor,
    String text, String contextText, Rect globalRect, List<int> annotationIds);
typedef ReflowTranslatedSelection = Future<void> Function(
    String text, String contextText, Rect globalRect, int start);

/// A reading surface in the reader's body, not a dialog or another book.
/// The source WebView stays mounted underneath to retain original-page state.
class DocumentReflowReader extends StatefulWidget {
  const DocumentReflowReader(
      {super.key,
      required this.store,
      this.precache,
      this.onSourcePageChanged,
      required this.info,
      required this.extractText,
      required this.render,
      required this.cancelRender,
      required this.onClose,
      required this.onPageChanged,
      this.onNarrationPageChanged,
      required this.onSelection,
      this.onTranslatedSelection,
      required this.clearMenu,
      this.selectionInvalidated,
      required this.loadNotes,
      required this.initialStyle,
      required this.saveStyle,
      this.forceOcr = false,
      this.anchor,
      this.modelStore,
      this.recognize,
      this.recognizeWithRegions,
      this.brightness,
      this.onQuery,
      this.onAiDraft,
      this.onBookmark,
      this.onExtract,
      this.onOpenReaderMenu,
      this.onOpenTranslationSettings,
      this.onOpenReaderPanel,
      this.onCloseReaderMenu,
      this.onReaderKeyEvent,
      this.onReaderTap,
      this.onKeyboardEligibilityChanged,
      this.onPdfWheelZoom,
      this.wheelZoomAllowed,
      this.onNarrationInvalidated,
      this.readerMenuVisible = false,
      this.comparison = false,
      this.onComparisonChanged,
      this.readerActions = const []});
  final bool comparison;
  final FocusOnKeyEventCallback? onReaderKeyEvent;
  final bool Function()? onReaderTap;
  final VoidCallback? onKeyboardEligibilityChanged;
  final ValueChanged<int>? onPdfWheelZoom;
  final bool Function()? wheelZoomAllowed;
  final void Function(TtsPageSource)? onNarrationInvalidated;
  final ValueChanged<bool>? onComparisonChanged;
  final VoidCallback? onOpenReaderMenu, onCloseReaderMenu;
  final VoidCallback? onOpenTranslationSettings;
  final ValueChanged<Widget>? onOpenReaderPanel;
  final bool readerMenuVisible;
  final Future<void> Function(String, String, bool)? onQuery;
  final Future<void> Function(String)? onAiDraft;
  final Future<void> Function(DocumentReflowAnchor, String)? onBookmark;
  final VoidCallback? onExtract;
  final Widget? brightness;
  final List<Widget> readerActions;
  final DocumentReflowStore store;
  final DocumentOcrPrecache? precache;
  final void Function(int page, int total)? onSourcePageChanged;
  final Future<Map<String, dynamic>> Function(int?) info;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) extractText,
      render;
  final VoidCallback cancelRender, onClose, clearMenu;
  final VoidCallback? selectionInvalidated;
  final Future<void> Function(int) onPageChanged;
  final Future<void> Function(int)? onNarrationPageChanged;
  final ReflowSelection onSelection;
  final ReflowTranslatedSelection? onTranslatedSelection;
  final Future<List<BookNote>> Function() loadNotes;
  final DocumentTextStyle initialStyle;
  final Future<void> Function(DocumentTextStyle) saveStyle;
  final bool forceOcr;
  final DocumentReflowAnchor? anchor;
  final OcrModelStore? modelStore;
  final Future<String> Function(
      Uint8List, OcrCancellation, void Function(int, int))? recognize;
  final Future<DocumentTextResult> Function(
          Uint8List, OcrCancellation, void Function(int, int))?
      recognizeWithRegions;
  @override
  State<DocumentReflowReader> createState() => DocumentReflowReaderState();
}

class DocumentReflowReaderState extends State<DocumentReflowReader> {
  final _surfaceKey = GlobalKey<DocumentReaderSurfaceState>();
  final _panels = ValueNotifier<int>(0);
  void closeMenu() {
    if (widget.onCloseReaderMenu != null) {
      widget.onCloseReaderMenu!();
    } else {
      _surfaceKey.currentState?.closeMenu();
    }
  }

  void _openMenu(String menu) {
    stopAutoScroll();
    if (widget.onOpenReaderPanel != null) {
      widget.clearMenu();
      clearSelection();
      widget.onOpenReaderPanel!(ListenableBuilder(
          listenable: _panels,
          builder: (context, _) => Padding(
              padding:
                  menu == 'style' ? EdgeInsets.zero : const EdgeInsets.all(16),
              child: menu == 'style'
                  ? _readerPanel(menu)
                  : ReaderSettingsScrollView(child: _readerPanel(menu)))));
    } else {
      _surfaceKey.currentState?.openMenu(menu);
    }
  }

  void openStyleMenu() => _openMenu('style');
  void openToolsMenu() => _openMenu('tools');
  Future<void> readerAction(String action) => _action(action);
  Widget progressPanel() => ListenableBuilder(
      listenable: _panels,
      builder: (context, _) => ReadingProgressControls(
          progress: ReaderProgress(
              chapterTitle: chapter,
              currentChapter: 1,
              totalChapters: !_busy && _total > 0 ? 1 : 0,
              currentPage: (_navigationPage ?? 0) + 1,
              totalPages: _total,
              percentage:
                  _total > 1 ? (_navigationPage ?? 0) / (_total - 1) : 0),
          onSeek: (value) => goToPage((value * (_total - 1)).round()),
          onPreviousChapter: () => turnOriginalPage(-1),
          onPreviousPage: () => turnOriginalPage(-1),
          onNextPage: () => turnOriginalPage(1),
          onNextChapter: () => turnOriginalPage(1)));
  final _controller = _ReflowTextController();
  final _translatedController = _ReflowTextController();
  final _translation = DocumentPageTranslation();
  String? _translationStyleValue;
  void _configureTranslationStyle() {
    final value = classicalTranslation
        ? Prefs().classicalTranslationTextStyle
        : Prefs().languageTranslationTextStyle;
    if (_translationStyleValue == value) return;
    _translationStyleValue = value;
    final style = TranslationTextStyle.decode(value);
    _translatedController.translationStyle = style.textStyle;
    unawaited(style.loadFont().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {}));
    if (mounted && _showTranslation) setState(() {});
  }

  int _translationRequest = 0;
  final _translationModes = ReaderTranslationModes();
  ValueNotifier<TranslationModeEnum> get translationMode =>
      _translationModes.language;
  ValueNotifier<TranslationModeEnum> get classicalTranslationMode =>
      _translationModes.classical;
  bool get _showTranslation =>
      _translation.mode.value != TranslationModeEnum.off;
  _ReflowTextController get _readingController =>
      _showTranslation ? _translatedController : _controller;

  void stopTranslation() {
    stopAutoScroll();
    _translationRequest++;
    _translation.stop();
  }

  void _translationChanged() {
    _configureTranslationStyle();
    _translationModes.update(_translation.mode.value,
        isClassical: classicalTranslation);
    _invalidateNarration();
    clearSelection();
    (widget.selectionInvalidated ?? widget.clearMenu)();
    _translatedController.text = _translation.text;
    _translatedController.translatedRanges = _translation.translatedRanges;
    _translatedController.paragraphSpacing = _style.paragraphSpacing;
    if (mounted) setState(() {});
  }

  Future<void> translateCurrentPage(TranslationModeEnum mode,
      {bool force = false,
      TranslateServiceProvider? provider,
      bool classical = false}) async {
    stopAutoScroll();
    final page = _page;
    if (!mounted || _busy || page == null || page.page != _navigationPage) {
      return;
    }
    final request = ++_translationRequest;
    final generation = _generation;
    final saved = await widget.store.read(page.page, '');
    if (!mounted ||
        _busy ||
        request != _translationRequest ||
        generation != _generation ||
        page != _page) {
      return;
    }
    final service = Prefs().fullTextTranslateService;
    final from = Prefs().fullTextTranslateFrom;
    final to = Prefs().fullTextTranslateTo;
    final translator = provider ?? service.provider;
    final classicalTranslator =
        classical ? ClassicalTranslation.current() : null;
    classicalTranslation = classical;
    final visible = _visibleTranslationRange();
    await _translation.translate(saved ?? page, mode,
        visibleStart: visible.$1,
        visibleEnd: visible.$2,
        settings: classicalTranslator == null
            ? '${service.name}/${from.name}/${to.name}'
            : 'classical/${classicalTranslator.identity}',
        force: force,
        request: (session, generation, text) => session.translate(
            generation,
            (runner) => classicalTranslator != null
                ? classicalTranslator.translate(text, runner)
                : translator is AiTranslateProvider
                    ? translator.translateStream(text, from, to,
                        isFullText: true, requestRunner: runner)
                    : translator is MicrosoftFreeTranslateProvider
                        ? translator.translateStream(text, from, to,
                            isFullText: true,
                            whenCancelled: runner.whenCancelled)
                        : translator is OfficialApiTranslateProvider
                            ? translator.translateStream(text, from, to,
                                isFullText: true,
                                whenCancelled: runner.whenCancelled)
                            : translator is DeepLTranslateProvider
                                ? translator.translateStream(text, from, to,
                                    isFullText: true,
                                    whenCancelled: runner.whenCancelled)
                                : translator.translateStream(text, from, to,
                                    isFullText: true)));
    _queueVisibleTranslation();
  }

  final _search = TextEditingController();
  bool classicalTranslation = false;
  String? _searchStatus;
  final _scroll = ScrollController();
  Ticker? _autoScrollTicker;
  VoidCallback? _autoScrollStopped;
  Duration? _autoScrollElapsed;
  double _autoScrollSpeed = 1;
  double _autoScrollPixelsPerSecond = 0, _autoScrollExtent = -1;
  double _autoScrollViewport = -1;
  String? _autoScrollText;
  Offset? _autoScrollPointerOrigin;

  bool get _autoScrollReady =>
      mounted &&
      !_busy &&
      _page != null &&
      _page!.page == _navigationPage &&
      _scroll.hasClients &&
      _scroll.position.hasContentDimensions &&
      _readingController.selection.isCollapsed;

  bool startAutoScroll(double speed, VoidCallback onStopped) {
    if (_autoScrollTicker != null && _autoScrollReady) {
      _autoScrollSpeed = speed.isFinite ? speed.clamp(.1, 4).toDouble() : 1;
      _autoScrollStopped = onStopped;
      return true;
    }
    if (!_autoScrollReady ||
        _translation.busy ||
        _scroll.offset >= _scroll.position.maxScrollExtent - .5) {
      return false;
    }
    _autoScrollSpeed = speed.isFinite ? speed.clamp(.1, 4).toDouble() : 1;
    _autoScrollStopped = onStopped;
    _autoScrollText = null;
    _autoScrollElapsed = null;
    _autoScrollPointerOrigin = null;
    _autoScrollTicker = Ticker(_tickAutoScroll)..start();
    return true;
  }

  void stopAutoScroll() {
    final ticker = _autoScrollTicker;
    if (ticker == null) return;
    _autoScrollTicker = null;
    _autoScrollElapsed = null;
    ticker.dispose();
    final stopped = _autoScrollStopped;
    _autoScrollStopped = null;
    stopped?.call();
  }

  void _tickAutoScroll(Duration elapsed) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!_autoScrollReady ||
        widget.readerMenuVisible ||
        _surfaceKey.currentState?.menuIsOpen == true ||
        ModalRoute.of(context)?.isCurrent == false ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      stopAutoScroll();
      return;
    }
    final previous = _autoScrollElapsed;
    _autoScrollElapsed = elapsed;
    // Visible translation can extend the text; wait for its existing request.
    if (previous == null ||
        _translation.busy ||
        _autoScrollPointerOrigin != null) {
      return;
    }
    _estimateAutoScrollRate();
    final seconds =
        ((elapsed - previous).inMicroseconds / 1000000).clamp(0.0, .1);
    final end = _scroll.position.maxScrollExtent;
    final target = (_scroll.offset +
            _autoScrollPixelsPerSecond * _autoScrollSpeed * seconds)
        .clamp(_scroll.position.minScrollExtent, end)
        .toDouble();
    if (target != _scroll.offset) _scroll.jumpTo(target);
    if (target >= end - .5) stopAutoScroll();
  }

  void _estimateAutoScrollRate() {
    final text = _readingController.text;
    final position = _scroll.position;
    final extent = position.maxScrollExtent - position.minScrollExtent;
    final viewport = position.viewportDimension;
    if (_autoScrollText == text &&
        _autoScrollExtent == extent &&
        _autoScrollViewport == viewport) {
      return;
    }
    _autoScrollText = text;
    _autoScrollExtent = extent;
    _autoScrollViewport = viewport;
    final chinese = RegExp(r'[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]')
        .allMatches(text)
        .length;
    final words =
        RegExp(r"[A-Za-z\u00c0-\u024f0-9]+(?:['’-][A-Za-z\u00c0-\u024f0-9]+)*")
            .allMatches(text)
            .length;
    final minutes = chinese / 300 + words / 200;
    final seconds = minutes > 0
        ? minutes * 60
        : text.replaceAll(RegExp(r'\s'), '').length / 5;
    _autoScrollPixelsPerSecond =
        (extent + viewport) / (seconds < 1 ? 1 : seconds);
  }

  void _autoScrollPointerDown(PointerDownEvent event) {
    if (_autoScrollPointerOrigin != null) stopAutoScroll();
    _autoScrollPointerOrigin = event.position;
  }

  void _autoScrollPointerMove(PointerMoveEvent event) {
    final origin = _autoScrollPointerOrigin;
    if (origin != null &&
        (event.position - origin).distance >
            (event.kind == PointerDeviceKind.mouse ? 2 : kTouchSlop)) {
      stopAutoScroll();
    }
  }

  final _translationViewportKey = GlobalKey();
  Timer? _translationScrollTimer;
  (int, int) _visibleTranslationRange() {
    final editable = _textState?.renderEditable;
    final viewport = _translationViewportKey.currentContext?.findRenderObject();
    if (editable == null || viewport is! RenderBox || !viewport.hasSize) {
      return (0, 0);
    }
    final origin = viewport.localToGlobal(Offset.zero);
    final start =
        editable.getPositionForPoint(origin + const Offset(1, 1)).offset;
    final end = editable
        .getPositionForPoint(
            origin + Offset(viewport.size.width - 1, viewport.size.height - 1))
        .offset;
    return (start < end ? start : end, start > end ? start : end);
  }

  void _queueVisibleTranslation() {
    if (_autoScrollTicker != null &&
        _translationScrollTimer?.isActive == true) {
      return;
    }
    _translationScrollTimer?.cancel();
    if (!_showTranslation) return;
    _translationScrollTimer =
        Timer(const Duration(milliseconds: 180), () async {
      if (!mounted || !_showTranslation) return;
      if (_translation.busy) {
        _queueVisibleTranslation();
        return;
      }
      final visible = _visibleTranslationRange();
      try {
        await _translation.translateVisible(visible.$1, visible.$2);
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
    });
  }

  final _focus = FocusNode(debugLabel: 'document_reflow_text');
  final _textFieldKey = GlobalKey();
  EditableTextState? _editable;
  EditableTextState? get _textState {
    EditableTextState? result;
    void visit(Element element) {
      if (element is StatefulElement && element.state is EditableTextState) {
        result = element.state as EditableTextState;
      } else {
        element.visitChildren(visit);
      }
    }

    _textFieldKey.currentContext?.visitChildElements(visit);
    return result;
  }

  late DocumentTextStyle _style = widget.initialStyle;
  StreamSubscription<String>? _removedFontSubscription;
  late bool _forceOcr = widget.forceOcr || widget.anchor?.ocr == true;
  DocumentReflowPage? _page;
  TtsPageSource? _narrationSource;
  TtsPageSource? narrationSourceFor(DocumentReflowAnchor anchor) {
    final page = _page;
    if (_showTranslation ||
        page == null ||
        anchor.original ||
        !anchor.matches(page)) {
      return null;
    }
    return narrationSource;
  }

  TtsPageSource? get narrationSource {
    if (_busy ||
        _translation.busy ||
        _page == null ||
        _page!.page != _navigationPage ||
        _readingController.text.trim().isEmpty) {
      return null;
    }
    final controller = _readingController;
    return _narrationSource ??= TtsPageSource(controller.text,
        chapter: chapter,
        excludedRanges: (text) => filteredTextRanges(text,
            Prefs().textFiltersForBook(epubPlayerKey.currentState?.cssBookKey)),
        onNextPage: _showTranslation ? null : _continueNarration,
        onCancelAdvance: cancelLoading,
        onHighlight: (range) {
          if (mounted) controller.setNarrationRange(range);
        },
        onPosition: (offset) {
          if (!mounted ||
              _readingController.selection.isValid &&
                  !_readingController.selection.isCollapsed) {
            return;
          }
          _textState?.bringIntoView(TextPosition(offset: offset));
        });
  }

  Future<bool> _continueNarration(
      TtsPageSource source, bool Function() isCurrent) async {
    if (!mounted ||
        _busy ||
        _showTranslation ||
        !identical(source, _narrationSource) ||
        !isCurrent()) {
      return false;
    }
    final page = _page;
    if (page == null || page.page + 1 >= _total) return false;
    final target = page.page + 1;
    await _load(target, narrationCurrent: isCurrent);
    if (!mounted || !isCurrent() || !identical(source, _narrationSource)) {
      return false;
    }
    if (_error != null || _needsModel || _page?.page != target) {
      throw StateError('Next reflow page is unavailable');
    }
    source.replacePage(_controller.text, chapter: chapter);
    return true;
  }

  void _invalidateNarration() {
    final source = _narrationSource;
    _narrationSource = null;
    if (source == null) return;
    source.invalidate();
    widget.onNarrationInvalidated?.call(source);
  }

  int _total = 0, _generation = 0, _loadRequest = 0;
  int? _requestedPage;
  int? get _navigationPage => _requestedPage ?? _page?.page;
  Future<void>? _pendingLoad;
  bool _busy = false, _needsModel = false;
  bool _ownsRenderer = false;
  String? _error, _shownSelection;
  TextSelection _observedSelection = const TextSelection.collapsed(offset: -1);
  Timer? _selectionTimer;
  Timer? _mouseLongPressTimer;
  Timer? _menuTapTimer;
  Timer? _pdfWheelZoomTimer;
  int _pendingPdfWheelZoom = 0;
  Duration? _pointerDownTime;
  int _selectionEpoch = 0;
  int? _expandingEpoch;
  bool _selectionSession = false, _expandInitialSelection = false;
  PointerDeviceKind? _pointerKind;
  Offset? _pointerOrigin;
  double? _progress;
  OcrCancellation? _cancel;
  List<BookNote> _notes = [];
  String t(String zh, String en) => ModuStrings.text(context, zh, en);
  String get chapter =>
      '${t('原书第', 'Original page')} ${(_page?.page ?? 0) + 1} ${t('页 · 重排', '· reflow')}';

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = (node, event) => canUseReadingKeys
        ? widget.onReaderKeyEvent?.call(node, event) ?? KeyEventResult.ignored
        : KeyEventResult.ignored;
    _controller.addListener(_selectionChanged);
    _translatedController.addListener(_translationSelectionChanged);
    _translation.addListener(_translationChanged);
    _removedFontSubscription = removedFonts.listen((filename) {
      if (mounted && _style.font == filename) {
        setState(() => _style = _style.withValue('font', ''));
      }
    });
    Prefs().addListener(_configureTranslationStyle);
    _configureTranslationStyle();
    _scroll.addListener(_queueVisibleTranslation);
    unawaited(_style.loadFont().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {}));
    unawaited(_load(widget.anchor?.page, anchor: widget.anchor));
  }

  @override
  void dispose() {
    stopAutoScroll();
    _removedFontSubscription?.cancel();
    _invalidateNarration();
    _generation++;
    _translation.removeListener(_translationChanged);
    Prefs().removeListener(_configureTranslationStyle);
    _translation.dispose();
    _translationModes.dispose();
    _translationScrollTimer?.cancel();
    _translatedController.dispose();
    _selectionTimer?.cancel();
    _mouseLongPressTimer?.cancel();
    _menuTapTimer?.cancel();
    _pdfWheelZoomTimer?.cancel();
    cancelLoading();
    _controller.dispose();
    _search.dispose();
    _scroll.dispose();
    _focus.dispose();
    _panels.dispose();
    super.dispose();
  }

  Future<void> refreshNotes() async {
    final version = _generation;
    final notes = await widget.loadNotes();
    if (!mounted || version != _generation) return;
    _notes = notes;
    _controller.setMarks(_page, notes);
  }

  void _selectionChanged() {
    if (!_showTranslation) _readingSelectionChanged();
  }

  void _readingSelectionChanged() {
    final controller = _readingController;
    final selection = controller.selection;
    if (!selection.isCollapsed) stopAutoScroll();
    if (selection == _observedSelection) return;
    _observedSelection = selection;
    widget.onKeyboardEligibilityChanged?.call();
    _selectionEpoch++;
    _shownSelection = null;
    if (_selectionSession &&
        !(_pointerOrigin != null && _pointerKind == PointerDeviceKind.mouse)) {
      _queueSelection();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          controller != _readingController ||
          selection != controller.selection ||
          _shownSelection != null) {
        return;
      }
      (widget.selectionInvalidated ?? widget.clearMenu)();
    });
  }

  void _translationSelectionChanged() {
    if (_showTranslation) _readingSelectionChanged();
  }

  void clearSelection() {
    _resetSelectionGesture();
    _editable?.hideToolbar();
    _shownSelection = null;
    _controller.selection = TextSelection.collapsed(
        offset: _controller.selection.extentOffset
            .clamp(0, _controller.text.length));
    _translatedController.selection = TextSelection.collapsed(
        offset: _translatedController.selection.extentOffset
            .clamp(0, _translatedController.text.length));
  }

  bool get canUseReadingKeys =>
      _focus.hasPrimaryFocus && _readingController.selection.isCollapsed;

  void requestKeyboardFocus() => _focus.requestFocus();

  Future<void> navigate(DocumentReflowAnchor anchor) async {
    if (_busy) {
      cancelLoading();
    }
    _forceOcr = widget.forceOcr || anchor.ocr;
    await _load(anchor.page, anchor: anchor);
  }

  Future<void> setMode(bool ocr) async {
    await stopLoading();
    if (!mounted) return;
    setState(() => _forceOcr = ocr);
    await _load(_navigationPage);
  }

  Future<void> turn(int direction) async {
    stopAutoScroll();
    if (_busy) return;
    if (_page == null || _navigationPage != _page!.page) {
      await turnOriginalPage(direction);
      return;
    }
    clearSelection();
    widget.clearMenu();
    if (_scroll.hasClients) {
      final next =
          _scroll.offset + direction * _scroll.position.viewportDimension * .9;
      if ((direction > 0 &&
              _scroll.offset < _scroll.position.maxScrollExtent - 1) ||
          (direction < 0 && _scroll.offset > 1)) {
        final target =
            next.clamp(0, _scroll.position.maxScrollExtent).toDouble();
        if (AppMotion.disabled) {
          _scroll.jumpTo(target);
        } else {
          await _scroll.animateTo(target,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut);
        }
        return;
      }
    }
    await turnOriginalPage(direction);
  }

  void cancelLoading({bool queued = true}) {
    stopAutoScroll();
    if (queued) _loadRequest++;
    _cancel?.cancel();
    if (_ownsRenderer) widget.cancelRender();
  }

  Future<void> stopLoading() async {
    _invalidateNarration();
    cancelLoading();
    await _pendingLoad;
  }

  Future<void> turnOriginalPage(int direction) async {
    final page = _navigationPage;
    if (_busy || page == null) return;
    final target = page + direction;
    if (target >= 0 && target < _total) await _load(target);
  }

  Future<void> goToPage(int page) async {
    if (page >= 0 && page < _total) await _load(page);
  }

  /// Source scrolling must not navigate the PDF back after recognition finishes.
  Future<void> followOriginalPage(int page) async {
    if (page < 0 || (_total > 0 && page >= _total)) return;
    if (page == _navigationPage &&
        (_busy || _page?.page == page || _error != null || _needsModel)) {
      return;
    }
    await _load(page, followOriginal: true);
  }

  String get actionText {
    final selection = _readingController.selection;
    return selection.isValid && !selection.isCollapsed
        ? selection.textInside(_readingController.text)
        : _readingController.text;
  }

  Future<void> _jumpToPage() async {
    final input = TextEditingController(text: '${(_navigationPage ?? 0) + 1}');
    final target = await showReaderDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(t('跳转原书页码', 'Go to original page')),
              content: TextField(
                  controller: input,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(helperText: '1–$_total'),
                  onSubmitted: (value) {
                    final number = int.tryParse(value);
                    if (number != null && number > 0 && number <= _total) {
                      Navigator.pop(context, number - 1);
                    }
                  }),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(t('取消', 'Cancel'))),
                TextButton(
                    onPressed: () {
                      final number = int.tryParse(input.text);
                      if (number != null && number > 0 && number <= _total) {
                        Navigator.pop(context, number - 1);
                      }
                    },
                    child: Text(t('跳转', 'Go')))
              ],
            ));
    // Dialog route transitions can still reference its controller this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
    if (mounted && target != null) await goToPage(target);
  }

  void _findNext() {
    final query = _search.text;
    if (query.isEmpty) return;
    final controller = _readingController;
    final text = controller.text;
    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    final match = pattern
            .allMatches(text,
                controller.selection.isValid ? controller.selection.end : 0)
            .firstOrNull ??
        pattern.firstMatch(text);
    final index = match?.start ?? -1;
    setState(() => _searchStatus =
        index < 0 ? t('本页未找到', 'Not found on this page') : null);
    _panels.value++;
    if (index < 0) return;
    final state = _textState;
    state?.userUpdateTextEditingValue(
        controller.value.copyWith(
            selection:
                TextSelection(baseOffset: index, extentOffset: match!.end)),
        SelectionChangedCause.keyboard);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) state?.bringIntoView(TextPosition(offset: index));
    });
  }

  Future<void> _action(String action) async {
    stopAutoScroll();
    if (action == 'translate' && widget.onOpenTranslationSettings != null) {
      widget.onOpenTranslationSettings!();
      return;
    }
    final text = actionText, page = _page;
    if (text.isEmpty || page == null) return;
    if (action == 'search') {
      _openMenu('search');
      return;
    }
    closeMenu();
    try {
      switch (action) {
        case 'copy':
          await Clipboard.setData(ClipboardData(text: text));
        case 'query':
          await widget.onQuery?.call(text, page.text, false);
        case 'translate':
          await widget.onQuery?.call(text, page.text, true);
        case 'ai':
          await widget.onAiDraft?.call(text);
        case 'bookmark':
          final selection = _showTranslation
              ? const TextSelection(baseOffset: 0, extentOffset: 0)
              : _controller.selection;
          final start = selection.isValid
              ? selection.start.clamp(0, page.text.length - 1)
              : 0;
          final end = selection.isValid && !selection.isCollapsed
              ? selection.end
              : (start + 120).clamp(0, page.text.length);
          await widget.onBookmark
              ?.call(page.anchor(start, end), page.text.substring(start, end));
          await refreshNotes();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t(
                '操作失败，请重试', 'Could not complete the action. Please retry.'))));
      }
    }
  }

  Future<void> _load(int? target,
      {DocumentReflowAnchor? anchor,
      bool refresh = false,
      bool followOriginal = false,
      bool Function()? narrationCurrent}) async {
    stopAutoScroll();
    if (narrationCurrent == null) {
      stopTranslation();
      _invalidateNarration();
    }
    final request = ++_loadRequest;
    if (target != null) _requestedPage = target;
    while (_pendingLoad != null) {
      cancelLoading(queued: false);
      await _pendingLoad;
      if (!mounted || request != _loadRequest) return;
    }
    if (!mounted) return;
    final pending = _performLoad(target,
        anchor: anchor,
        refresh: refresh,
        followOriginal: followOriginal,
        narrationCurrent: narrationCurrent);
    _pendingLoad = pending;
    try {
      await pending;
    } finally {
      if (identical(_pendingLoad, pending)) _pendingLoad = null;
    }
  }

  Future<void> _performLoad(int? target,
      {DocumentReflowAnchor? anchor,
      bool refresh = false,
      bool followOriginal = false,
      bool Function()? narrationCurrent}) async {
    _resetSelectionGesture();
    final generation = ++_generation, cancel = OcrCancellation();
    _cancel?.cancel();
    _cancel = cancel;
    widget.clearMenu();
    setState(() {
      _busy = true;
      // Navigation follows the attempted source page, not stale reflow text.
      _requestedPage = target ?? _navigationPage;
      if (followOriginal && target != _page?.page) _page = null;
      _error = null;
      _needsModel = false;
      _progress = null;
    });
    _panels.value++;
    final model = widget.modelStore ??
        OcrModelStore(model: OcrModels.byId(Prefs().ocrModelId));
    bool active() =>
        mounted &&
        generation == _generation &&
        !cancel.cancelled &&
        (narrationCurrent?.call() ?? true);
    void check() {
      cancel.check();
      if (!active()) throw StateError('Reader changed');
    }

    try {
      final info = await widget.info(target);
      check();
      final page = (info['page'] as num).toInt(),
          total = (info['total'] as num).toInt();
      if (page < 0 ||
          page >= total ||
          (target != null && page != target) ||
          info['imageOnly'] == false) {
        throw const FormatException('Invalid image page');
      }
      _requestedPage = page;
      _total = total;
      Future<DocumentReflowPage> load() async {
        check();
        _ownsRenderer = true;
        try {
          return await loadDocumentReflowPage(
              info: info,
              store: widget.store,
              model: model,
              cancel: cancel,
              anchor: anchor,
              forceOcr: _forceOcr,
              refresh: refresh,
              extract: widget.extractText,
              render: widget.render,
              recognize: (bytes, token, progress) =>
                  widget.recognizeWithRegions?.call(bytes, token, progress) ??
                  (widget.recognize != null
                      ? widget.recognize!(bytes, token, progress)
                          .then(DocumentTextResult.new)
                      : LocalOcrService().recognizeWithRegions(
                          bytes, model, token,
                          progress: progress)),
              progress: (n, total) {
                if (active()) {
                  setState(() => _progress = total > 0 ? n / total : null);
                }
              });
        } finally {
          _ownsRenderer = false;
        }
      }

      final cached = refresh
          ? null
          : anchor == null
              ? await widget.store.read(page, '')
              : await widget.store.readAnchor(anchor);
      check();
      final result = cached != null &&
              (anchor != null || !_forceOcr || cached.ocr)
          ? cached
          : await (widget.precache?.runForeground<DocumentReflowPage>(load) ??
              load());
      check();
      final notes = await widget.loadNotes();
      check();
      // Commit page and reader progress together only after successful loading.
      if (!followOriginal) {
        final navigate = narrationCurrent == null
            ? widget.onPageChanged
            : widget.onNarrationPageChanged ?? widget.onPageChanged;
        await navigate(page);
      }
      check();
      widget.onSourcePageChanged?.call(page, total);
      _page = result;
      _notes = notes;
      _controller.text = result.text;
      _controller.setMarks(result, notes);
      _controller.paragraphSpacing = _style.paragraphSpacing;
      _shownSelection = null;
      setState(() {
        if (anchor != null && !anchor.matches(result)) {
          _error = t("已返回笔记所在的原书页。", "Returned to the note’s original page.");
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!active()) return;
        if (_scroll.hasClients) _scroll.jumpTo(0);
        if (anchor != null && anchor.matches(result)) {
          _controller.selection =
              TextSelection(baseOffset: anchor.start, extentOffset: anchor.end);
          _textState?.bringIntoView(TextPosition(offset: anchor.start));
        }
      });
    } on ReflowModelUnavailable {
      if (active()) setState(() => _needsModel = true);
    } catch (_) {
      if (active()) {
        setState(() => _error =
            t("重排失败，请重试或切换页面。", "Reflow failed. Try again or switch pages."));
      }
    } finally {
      if (widget.modelStore == null) model.close();
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _progress = null;
        });
        _panels.value++;
      }
    }
  }

  Future<void> _settings() async {
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const OcrModelSettings()));
    if (mounted) {
      await _load(_requestedPage ?? _page?.page ?? widget.anchor?.page);
    }
  }

  Future<void> _editPage() async {
    _invalidateNarration();
    final page = _page;
    if (_busy || page == null) return;
    closeMenu();
    widget.clearMenu();
    clearSelection();
    final edited = await editSavedDocumentPage(context, widget.store, page);
    if (!mounted || edited == null) return;
    await _load(edited.page);
  }

  Future<void> _recognizeAgain() async {
    final page = _navigationPage;
    if (_busy || page == null) return;
    if (!await confirmDocumentRecognition(context) || !mounted) return;
    final previous = _forceOcr;
    _forceOcr = true;
    closeMenu();
    try {
      await _load(page, refresh: true);
    } finally {
      _forceOcr = previous;
    }
  }

  Widget _readerPanel(String menu) => switch (menu) {
        'style' => stylePanel(),
        'search' => ReaderMenuGroup(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  key: const ValueKey('reflow-search'),
                  controller: _search,
                  decoration:
                      InputDecoration(labelText: t('本页搜索', 'Search this page')),
                  onSubmitted: (_) => _findNext()),
              TextButton(
                  key: const ValueKey('reflow-find-next'),
                  onPressed: _findNext,
                  child: Text(t('下一个', 'Find next'))),
              if (_searchStatus != null) Text(_searchStatus!),
            ])),
        _ => Column(mainAxisSize: MainAxisSize.min, children: [
            Text(t('PDF / OCR', 'PDF / OCR'),
                style: readerSubmenuTitleStyle(context)),
            const SizedBox(height: 8),
            ReaderMenuGroup(
                child: Column(children: [
              if (widget.onComparisonChanged != null)
                SwitchListTile(
                    key: const ValueKey('reflow-comparison-switch'),
                    title: SettingHelp(
                        title: Text(t('原页对照', 'Compare with original')),
                        description: Text(t('竖屏上下，横屏左右；按原页码联动',
                            'Top/bottom in portrait, side by side in landscape'))),
                    value: widget.comparison,
                    onChanged: widget.onComparisonChanged),
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: OcrPrecacheSettings(cache: widget.precache)),
            ])),
            ReaderMenuGroup(
                child: Column(children: [
              ListTile(
                  key: const ValueKey('edit-saved-page'),
                  leading: const Icon(Icons.edit_note),
                  title: Text(t('编辑本页文字', 'Edit saved page')),
                  subtitle: Text(_page?.editedText != null
                      ? t('已校对', 'Edited')
                      : t('校对后自动保存到本书', 'Save corrections with this book')),
                  onTap: _busy || _page == null ? null : _editPage),
              ListTile(
                  key: const ValueKey('export-saved-txt'),
                  leading: const Icon(Icons.file_download_outlined),
                  title: SettingHelp(
                      title: Text(t('导出本书已保存文字', 'Export saved text')),
                      description: Text(t('按原始页码排列，优先导出编辑结果',
                          'Original page order; edited text takes priority'))),
                  onTap: _busy
                      ? null
                      : () => exportSavedDocumentText(context, widget.store)),
              ListTile(
                  leading: const Icon(Icons.refresh),
                  title: SettingHelp(
                      title: Text(t('重新识别本页', 'Recognize this page again')),
                      description: Text(t('确认后替换本页识别及编辑结果，保留旧笔记',
                          'Confirm replacement of this page’s recognition and edits; keep older notes'))),
                  onTap: _busy ? null : _recognizeAgain),
              if (widget.onExtract != null)
                ListTile(
                    leading: const Icon(Icons.crop),
                    title: Text(
                        t('区域 / 连续多页识别', 'Area / multiple-page recognition')),
                    onTap: widget.onExtract),
            ])),
            ReaderMenuGroup(
                child: Column(children: [
              ListTile(
                  leading: const Icon(Icons.arrow_back),
                  title: Text(t('返回原页', 'Return to original page')),
                  onTap: widget.onClose),
              ListTile(
                  leading: const Icon(Icons.document_scanner_outlined),
                  title: Text(t('OCR 模型设置', 'OCR model settings')),
                  onTap: _busy ? null : _settings),
            ])),
          ]),
      };

  Widget stylePanel() => DocumentTextStyleDialog(
      initial: _style,
      embedded: true,
      onOpenPanel: widget.onOpenReaderPanel,
      save: (style) async {
        await widget.saveStyle(style);
        if (mounted) {
          setState(() {
            _style = style;
            _controller.paragraphSpacing = style.paragraphSpacing;
            _translatedController.paragraphSpacing = style.paragraphSpacing;
          });
        }
      });

  bool get _canRelayPdfWheelZoom =>
      mounted &&
      widget.onPdfWheelZoom != null &&
      widget.comparison &&
      !_busy &&
      _page != null &&
      !widget.readerMenuVisible &&
      _surfaceKey.currentState?.menuIsOpen != true &&
      ModalRoute.of(context)?.isCurrent != false &&
      (widget.wheelZoomAllowed?.call() ?? true) &&
      _readingController.selection.isCollapsed;

  void _flushPdfWheelZoom() {
    _pdfWheelZoomTimer = null;
    final direction = _pendingPdfWheelZoom;
    _pendingPdfWheelZoom = 0;
    if (direction != 0 && _canRelayPdfWheelZoom) {
      widget.onPdfWheelZoom!(direction);
      _pdfWheelZoomTimer =
          Timer(const Duration(milliseconds: 80), _flushPdfWheelZoom);
    }
  }

  void _handlePdfWheelZoom(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        !event.scrollDelta.dy.isFinite ||
        event.scrollDelta.dy == 0 ||
        !desktopWheelZoomModifierPressed() ||
        !_canRelayPdfWheelZoom) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final direction = event.scrollDelta.dy < 0 ? 1 : -1;
      if (_pdfWheelZoomTimer == null) {
        widget.onPdfWheelZoom!(direction);
        _pdfWheelZoomTimer =
            Timer(const Duration(milliseconds: 80), _flushPdfWheelZoom);
      } else {
        _pendingPdfWheelZoom = direction;
      }
    });
  }

  void _resetSelectionGesture() {
    _menuTapTimer?.cancel();
    _selectionTimer?.cancel();
    _mouseLongPressTimer?.cancel();
    _selectionEpoch++;
    _expandingEpoch = null;
    _selectionSession = false;
    _expandInitialSelection = false;
    _pointerOrigin = null;
  }

  void _selectionPointerDown(PointerDownEvent event) {
    _menuTapTimer?.cancel();
    _pointerDownTime = event.timeStamp;
    _selectionTimer?.cancel();
    _mouseLongPressTimer?.cancel();
    _selectionEpoch++;
    _selectionSession = true;
    _expandInitialSelection = event.buttons == kPrimaryButton;
    _pointerKind = event.kind;
    _pointerOrigin = event.position;
    if (event.kind == PointerDeviceKind.mouse && _expandInitialSelection) {
      // Desktop TextField supports double-click/drag but not press-and-hold.
      // Match the ordinary reader without competing with touch gestures.
      _mouseLongPressTimer = Timer(kLongPressTimeout, () {
        if (!mounted || !_expandInitialSelection || _pointerOrigin == null) {
          return;
        }
        final state = _textState;
        if (state == null) return;
        final position =
            state.renderEditable.getPositionForPoint(event.position);
        final word = state.renderEditable.getWordBoundary(position);
        if (!word.isValid || word.isCollapsed) return;
        state.userUpdateTextEditingValue(
            _readingController.value.copyWith(
                selection: TextSelection(
                    baseOffset: word.start, extentOffset: word.end)),
            SelectionChangedCause.longPress);
        _queueSelection();
      });
    }
  }

  void _selectionPointerMove(PointerMoveEvent event) {
    // A deliberate drag owns its exact range. Handle overlays live outside
    // this Listener, so dragging a handle never arms expansion again.
    if (_pointerOrigin != null &&
        (event.position - _pointerOrigin!).distance >
            (_pointerKind == PointerDeviceKind.mouse ? 2 : kTouchSlop)) {
      _expandInitialSelection = false;
      _mouseLongPressTimer?.cancel();
    }
  }

  void _selectionPointerUp(PointerUpEvent event) {
    _mouseLongPressTimer?.cancel();
    final shortTap = _expandInitialSelection &&
        _pointerOrigin != null &&
        (event.position - _pointerOrigin!).distance < kTouchSlop &&
        _pointerDownTime != null &&
        event.timeStamp - _pointerDownTime! < kLongPressTimeout;
    if (shortTap) {
      _menuTapTimer = Timer(kDoubleTapTimeout, () {
        if (mounted && _readingController.selection.isCollapsed) {
          _tapPage(event.position);
        }
      });
    }
    _pointerOrigin = null;
    _queueSelection();
  }

  void _tapPage(Offset global) {
    if (_busy || !_readingController.selection.isCollapsed) return;
    if (widget.onReaderTap?.call() == true) return;
    final box = _translationViewportKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final point = box.globalToLocal(global);
    final part = coordinatesToPart(
        point.dx / box.size.width, point.dy / box.size.height);
    final prefs = Prefs();
    var action = prefs.pageTurnMode == 'custom'
        ? PageTurningType.values[prefs.customPageTurnConfig[part]]
        : pageTurningTypes[
            prefs.pageTurningType.clamp(0, pageTurningTypes.length - 1)][part];
    if (prefs.pageTurnMode != 'custom' && prefs.swapPageTurnArea) {
      if (action == PageTurningType.prev) {
        action = PageTurningType.next;
      } else if (action == PageTurningType.next) {
        action = PageTurningType.prev;
      }
    }
    if (action == PageTurningType.menu) {
      widget.onOpenReaderMenu?.call();
    } else if (!prefs.keyboardShortcutTurnPage) {
      if (action == PageTurningType.next) unawaited(turn(1));
      if (action == PageTurningType.prev) unawaited(turn(-1));
    }
  }

  void _queueSelection() {
    _selectionTimer?.cancel();
    _selectionTimer = Timer(const Duration(milliseconds: 80), () {
      unawaited(_settleSelection());
    });
  }

  Future<void> _settleSelection() async {
    final controller = _readingController;
    final selection = controller.selection, page = _page;
    final state = _textState;
    if (!mounted ||
        state == null ||
        page == null ||
        !selection.isValid ||
        selection.isCollapsed) {
      _expandInitialSelection = false;
      return;
    }
    final epoch = _selectionEpoch, generation = _generation;
    if (_expandingEpoch == epoch) return;
    if (_expandInitialSelection) {
      // Consume before awaiting: late native results must not undo a user's
      // next gesture, a moved handle, or a restored annotation range.
      _expandInitialSelection = false;
      _expandingEpoch = epoch;
      final text = controller.text;
      final start = selection.start == 0
          ? 0
          : text.lastIndexOf('\n', selection.start - 1) + 1;
      final newline = text.indexOf('\n', selection.start);
      final end = newline < 0 ? text.length : newline;
      List<int>? bounds;
      if (Prefs().longPressSelectParagraph) {
        final paragraph = text.substring(start, end);
        final leading = paragraph.length - paragraph.trimLeft().length;
        bounds = [start + leading, start + paragraph.trimRight().length];
      } else {
        final word = await ReaderWordSelection.bounds({
          'text': text.substring(start, end),
          'offset': selection.start - start,
          'locale': Localizations.localeOf(context).toLanguageTag(),
        });
        if (word != null) bounds = [start + word[0], start + word[1]];
      }
      if (_expandingEpoch == epoch) _expandingEpoch = null;
      if (!mounted ||
          epoch != _selectionEpoch ||
          generation != _generation ||
          controller != _readingController ||
          selection != controller.selection) {
        return;
      }
      // Never shrink a native word/drag range into a smaller token.
      if (bounds != null &&
          bounds[0] <= selection.start &&
          bounds[1] >= selection.end &&
          bounds[0] < bounds[1]) {
        final expanded = selection.baseOffset <= selection.extentOffset
            ? TextSelection(baseOffset: bounds[0], extentOffset: bounds[1])
            : TextSelection(baseOffset: bounds[1], extentOffset: bounds[0]);
        state.userUpdateTextEditingValue(
            controller.value.copyWith(selection: expanded),
            _pointerKind == PointerDeviceKind.mouse
                ? SelectionChangedCause.tap
                : SelectionChangedCause.longPress);
        _selectionTimer?.cancel();
      }
    }
    // Wait for the expanded range's layout before reading global anchors.
    final settled = controller.selection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _generation ||
          controller != _readingController ||
          settled != controller.selection) {
        return;
      }
      _publishSelection(state);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Widget _selectionMenu(BuildContext context, EditableTextState state) {
    if (_expandingEpoch == _selectionEpoch) return const SizedBox.shrink();
    if (_expandInitialSelection) {
      _queueSelection();
    } else {
      _publishSelection(state);
    }
    return const SizedBox.shrink();
  }

  void _publishSelection(EditableTextState state) {
    _editable = state;
    final translated = _showTranslation;
    final controller = _readingController;
    final text = controller.text;
    final selection = controller.selection, page = _page;
    if (page == null || !selection.isValid || selection.isCollapsed) {
      return;
    }
    final anchor =
        translated ? null : page.anchor(selection.start, selection.end);
    final id = anchor?.encode() ??
        'translation:$_translationRequest:${selection.start}:${selection.end}';
    final primary = state.contextMenuAnchors.primaryAnchor;
    final secondary = state.contextMenuAnchors.secondaryAnchor ?? primary;
    if (_shownSelection != id) {
      _shownSelection = id;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted ||
            controller != _readingController ||
            controller.text != text ||
            controller.selection != selection ||
            _page != page ||
            _shownSelection != id) {
          return;
        }
        final contextText = text.substring(
            (selection.start - 800).clamp(0, text.length),
            (selection.end + 800).clamp(0, text.length));
        final rect = Rect.fromPoints(primary, secondary).inflate(4);
        if (translated) {
          // Display offsets are ephemeral, never original-page note anchors.
          await widget.onTranslatedSelection?.call(
              selection.textInside(text), contextText, rect, selection.start);
          return;
        }
        final ids = _notes
            .where((note) {
              final saved = DocumentReflowAnchor.parse(note.cfi);
              return saved != null &&
                  saved.matches(page) &&
                  saved.start < selection.end &&
                  saved.end > selection.start;
            })
            .map((note) => note.id)
            .whereType<int>()
            .toList();
        await widget.onSelection(
            anchor!, selection.textInside(text), contextText, rect, ids);
      });
    }
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: Prefs(), builder: (context, _) => _buildReader(context));
  }

  String? _filterSignature;
  String? _filteredOriginal, _filteredTranslation;
  Widget _buildReader(BuildContext context) {
    final rules =
        Prefs().textFiltersForBook(epubPlayerKey.currentState?.cssBookKey);
    final signature = jsonEncode(rules.map((p) => p.toJson()).toList());
    if (_filterSignature != signature) {
      _filteredOriginal = _filteredTranslation = null;
      _filterSignature = signature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _invalidateNarration();
      });
    }
    if (_filteredOriginal != _controller.text) {
      _filteredOriginal = _controller.text;
      _controller.filteredRanges = filteredTextRanges(_controller.text, rules);
    }
    if (_filteredTranslation != _translatedController.text) {
      _filteredTranslation = _translatedController.text;
      _translatedController.filteredRanges =
          filteredTextRanges(_translatedController.text, rules);
    }
    Color parse(String value, Color fallback) =>
        Color(int.tryParse(value.replaceFirst('#', ''), radix: 16) ??
            fallback.toARGB32());
    final theme = readingThemeForDisplay(Prefs(),
        isDarkMode: Theme.of(context).brightness == Brightness.dark);
    final foreground =
        parse(theme.textColor, Theme.of(context).colorScheme.onSurface);
    final prefs = Prefs();
    final selection =
        prefs.customCssSelection(epubPlayerKey.currentState?.cssBookKey);
    final css = ReflowCss(
        selection.enabled
            ? selection.activeIndices
                .map((i) => prefs.customCssProfiles[i])
                .toList()
            : [],
        _style.textStyle.copyWith(color: foreground));
    _controller.paragraphSpacing = css.paragraphGap ?? _style.paragraphSpacing;
    return DocumentReaderSurface(
      readerContentOnly: widget.onOpenReaderMenu != null,
      hideHeader: widget.readerMenuVisible,
      onBack: widget.readerMenuVisible ? closeMenu : widget.onClose,
      key: _surfaceKey,
      brightness: widget.brightness,
      style: stylePanel(),
      actions: widget.readerActions,
      extraMenus: {'search': _readerPanel('search')},
      onMenuOpened: () {
        stopAutoScroll();
        widget.clearMenu();
        clearSelection();
      },
      header: Row(children: [
        TextButton.icon(
            key: const ValueKey('reflow-original'),
            onPressed: widget.onClose,
            icon: const Icon(Icons.arrow_back),
            label: Text(t('原页', 'Original'))),
        Expanded(
            child: Text(t('文字重排', 'Reflow text'),
                key: const ValueKey('reflow-mode'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)),
        if (widget.onComparisonChanged != null)
          IconButton(
              key: const ValueKey('reflow-comparison'),
              tooltip: t('原页对照', 'Compare with original'),
              isSelected: widget.comparison,
              icon: const Icon(Icons.splitscreen_outlined),
              onPressed: () => widget.onComparisonChanged!(!widget.comparison)),
        if (widget.onOpenReaderMenu == null)
          PopupMenuButton<String>(
            clipBehavior: Clip.antiAlias,
            key: const ValueKey('reflow-more'),
            tooltip: t('更多阅读功能', 'More reading tools'),
            icon: const Icon(Icons.more_vert),
            enabled: !_busy && _page != null,
            onSelected: _action,
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'search', child: Text(t('本页搜索', 'Search this page'))),
              PopupMenuItem(
                  value: 'copy',
                  child: Text(t('复制选中内容 / 本页', 'Copy selection / page'))),
              if (widget.onQuery != null) ...[
                PopupMenuItem(
                    value: 'query', child: Text(t('综合查询', 'Look up'))),
                PopupMenuItem(
                    value: 'translate', child: Text(t('翻译', 'Translate'))),
              ],
              if (widget.onAiDraft != null)
                PopupMenuItem(value: 'ai', child: Text(t('AI 对话', 'AI chat'))),
              if (widget.onBookmark != null)
                PopupMenuItem(
                    value: 'bookmark', child: Text(t('添加书签', 'Add bookmark'))),
            ],
          ),
      ]),
      body: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _autoScrollPointerDown,
        onPointerMove: _autoScrollPointerMove,
        onPointerUp: (_) => _autoScrollPointerOrigin = null,
        onPointerCancel: (_) => _autoScrollPointerOrigin = null,
        onPointerSignal: (_) => stopAutoScroll(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _tapPage(details.globalPosition),
          child: Column(children: [
            if (_busy || _translation.busy)
              EinkStaticIndicator(
                  child:
                      LinearProgressIndicator(value: _busy ? _progress : null)),
            Expanded(
                child: _page == null
                    ? Center(
                        child: _busy
                            ? const EinkStaticIndicator(
                                child: CircularProgressIndicator())
                            : Text(t('等待本页文字', 'Waiting for page text'),
                                style: TextStyle(color: foreground)))
                    : ScrollConfiguration(
                        // EditableText re-enables scrollbars; do not inherit app gutters.
                        behavior: const MaterialScrollBehavior()
                            .copyWith(scrollbars: false),
                        child: AppScrollbar(
                            controller: _scroll,
                            child: SingleChildScrollView(
                                key: _translationViewportKey,
                                controller: _scroll,
                                padding: _style.padding,
                                child: Listener(
                                    onPointerSignal: _handlePdfWheelZoom,
                                    onPointerDown: _selectionPointerDown,
                                    onPointerMove: _selectionPointerMove,
                                    onPointerUp: _selectionPointerUp,
                                    onPointerCancel: (_) =>
                                        _resetSelectionGesture(),
                                    child: KeyedSubtree(
                                        key: _textFieldKey,
                                        child: TextField(
                                          key: ValueKey(_showTranslation
                                              ? 'reflow-translated-text'
                                              : 'reflow-text'),
                                          controller: _readingController,
                                          focusNode: _focus,
                                          readOnly: true,
                                          maxLines: null,
                                          showCursor: false,
                                          enableSuggestions: false,
                                          style: css.textStyle,
                                          textAlign:
                                              css.alignment ?? _style.alignment,
                                          decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              isCollapsed: true,
                                              contentPadding: EdgeInsets.zero),
                                          contextMenuBuilder: _selectionMenu,
                                          onTapOutside: (_) {},
                                        ))))))),
            if (_needsModel || _error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                      _error ??
                          t("请先在“离线本地模型”中下载 OCR 模型。",
                              "Download an OCR model in Offline models first."),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: foreground))),
          ]),
        ),
      ),
      tools: _readerPanel('tools'),
      navigation: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.center,
          children: [
            IconButton(
                key: const ValueKey('reflow-previous'),
                iconSize: 36,
                constraints:
                    const BoxConstraints.tightFor(width: 56, height: 56),
                visualDensity: VisualDensity.standard,
                tooltip: t('上一原页', 'Previous original page'),
                onPressed: !_busy && (_navigationPage ?? 0) > 0
                    ? () => turnOriginalPage(-1)
                    : null,
                icon: const Icon(Icons.chevron_left)),
            Tooltip(
                message: t('跳转原书页码', 'Go to original page'),
                child: TextButton(
                    onPressed: _busy || _total == 0 ? null : _jumpToPage,
                    child: Text('${(_navigationPage ?? 0) + 1} / $_total'))),
            IconButton(
                key: const ValueKey('reflow-next'),
                iconSize: 36,
                constraints:
                    const BoxConstraints.tightFor(width: 56, height: 56),
                visualDensity: VisualDensity.standard,
                tooltip: t('下一原页', 'Next original page'),
                onPressed: !_busy &&
                        _navigationPage != null &&
                        _navigationPage! + 1 < _total
                    ? () => turnOriginalPage(1)
                    : null,
                icon: const Icon(Icons.chevron_right)),
            if (_busy)
              TextButton(
                  onPressed: cancelLoading, child: Text(t('停止', 'Stop'))),
            if (_needsModel && !_busy)
              TextButton(
                  onPressed: _settings,
                  child: Text(t('OCR 模型设置', 'OCR model settings'))),
            if (!_busy && (_error != null || _page == null))
              TextButton(
                  onPressed: () => _load(
                      _requestedPage ?? _page?.page ?? widget.anchor?.page),
                  child: Text(t('重试', 'Retry'))),
          ]),
    );
  }
}

class _ReflowTextController extends TextEditingController {
  List<TextRange> translatedRanges = [];
  TextStyle? translationStyle;
  TextRange? _narrationRange;
  void setNarrationRange(TextRange? range) {
    if (_narrationRange == range) return;
    _narrationRange = range;
    notifyListeners();
  }

  List<TextRange> filteredRanges = const [];
  double paragraphSpacing = 1;
  DocumentReflowPage? page;
  List<BookNote> notes = [];
  void setMarks(DocumentReflowPage? value, List<BookNote> marks) {
    page = value;
    notes = marks;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final marks = <(DocumentReflowAnchor, BookNote)>[];
    if (page != null && page!.text == text) {
      for (final note in notes) {
        final anchor = DocumentReflowAnchor.parse(note.cfi);
        if (anchor != null &&
            anchor.matches(page!) &&
            (note.type == 'highlight' || note.type == 'underline')) {
          marks.add((anchor, note));
        }
      }
    }
    final edges = {
      0,
      text.length,
      for (final range in filteredRanges) ...[range.start, range.end],
      for (final range in translatedRanges) ...[range.start, range.end],
      if (_narrationRange case final range?
          when range.isValid && range.end <= text.length) ...[
        range.start,
        range.end
      ],
      for (final mark in marks) ...[mark.$1.start, mark.$1.end],
      for (final match in RegExp(r'\n\n').allMatches(text)) ...[
        match.start + 1,
        match.end
      ]
    }.toList()
      ..sort();
    return TextSpan(style: style, children: [
      for (var i = 0; i < edges.length - 1; i++)
        TextSpan(
            text: text.substring(edges[i], edges[i + 1]),
            style: (filteredRanges.any((range) => edges[i] >= range.start && edges[i] < range.end)
                    ? const TextStyle(
                        fontSize: 0,
                        height: 0.01,
                        letterSpacing: 0,
                        color: Colors.transparent)
                    : _styleAt(edges[i], marks))
                .merge(translatedRanges
                        .any((r) => edges[i] >= r.start && edges[i] < r.end)
                    ? translationStyle
                    : null)
                .merge(edges[i] > 0 &&
                        text[edges[i] - 1] == '\n' &&
                        text[edges[i]] == '\n'
                    ? TextStyle(
                        height: paragraphSpacing == 0 ? .01 : paragraphSpacing)
                    : null)
                .merge(filteredRanges.any((range) =>
                        edges[i] >= range.start && edges[i] < range.end)
                    ? const TextStyle(
                        fontSize: 0,
                        height: 0.01,
                        letterSpacing: 0,
                        color: Colors.transparent)
                    : null))
    ]);
  }

  TextStyle _styleAt(int offset, List<(DocumentReflowAnchor, BookNote)> marks) {
    Color? background, underline;
    for (final (anchor, note) in marks) {
      if (offset < anchor.start || offset >= anchor.end) continue;
      final color = Color(
          int.tryParse('ff${note.color.replaceFirst('#', '')}', radix: 16) ??
              0xffffff00);
      if (note.type == 'highlight') background = color.withValues(alpha: .35);
      if (note.type == 'underline') underline = color;
    }
    final range = _narrationRange;
    if (range != null && offset >= range.start && offset < range.end) {
      // Match the ordinary ebook speech overlay without changing selection/notes.
      background = const Color(0x8339c5bc);
    }
    return TextStyle(
        backgroundColor: background,
        decoration: underline == null ? null : TextDecoration.underline,
        decorationColor: underline);
  }
}
