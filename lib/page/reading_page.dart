import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/service/document_reader_rotation.dart';
import 'package:anx_reader/widgets/reading_page/document_style_widget.dart';
import 'package:anx_reader/widgets/reading_page/pdf_zoom_toolbar.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'dart:async';
import 'package:anx_reader/models/reader_shortcuts.dart';
import 'package:anx_reader/widgets/bookshelf/book_import_picker.dart';
import 'package:anx_reader/service/app_brightness.dart';
import 'package:anx_reader/widgets/reading_page/brightness_widget.dart';
import 'package:anx_reader/enums/translation_mode.dart';
import 'package:anx_reader/service/sync/reading_sync_scheduler.dart';
import 'package:anx_reader/utils/reader_route_observer.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'dart:math' as math;
import 'package:anx_reader/service/reader_fullscreen.dart';
import 'package:anx_reader/utils/platform_utils.dart';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/dao/theme.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/enums/ai_chat_display_mode.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/unified_query.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/widgets/ai/reading_skill_chips.dart';
import 'package:anx_reader/service/reader_focus.dart';
import 'package:anx_reader/service/reader_keyboard.dart';
import 'package:anx_reader/service/reader_page_keys.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/ui/status_bar.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:anx_reader/widgets/reading_page/notes_widget.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_lookup.dart';
import 'package:anx_reader/widgets/dictionary/unified_query.dart';
import 'package:anx_reader/widgets/reading_page/quick_mark_toggle.dart';
import 'package:anx_reader/models/reading_time.dart';
import 'package:anx_reader/widgets/reading_page/progress_widget.dart';
import 'package:anx_reader/widgets/reading_page/tts_quick_toolbar.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/widgets/reading_page/tts_widget.dart';
import 'package:anx_reader/widgets/reading_page/translation_widget.dart';
import 'package:anx_reader/widgets/reading_page/translation_toolbar_action.dart';
import 'package:anx_reader/widgets/reading_page/book_search.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/page_router/reader_cover_hero.dart';
import 'package:anx_reader/widgets/reading_page/selection_search_browser.dart';
import 'package:anx_reader/widgets/context_menu/translation_menu.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:anx_reader/widgets/reading_page/document_extraction_panel.dart';
import 'package:anx_reader/service/ocr/document_text_style.dart';
import 'package:anx_reader/service/ocr/document_reflow_store.dart';
import 'package:anx_reader/widgets/reading_page/document_reflow_reader.dart';
import 'package:anx_reader/widgets/reading_page/document_comparison_view.dart';
import 'package:anx_reader/widgets/reading_page/document_original_note.dart';
import 'package:anx_reader/widgets/context_menu/context_menu.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/widgets/reading_page/toc_widget.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'package:flutter/foundation.dart'
// show debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:anx_reader/utils/reader_wakelock.dart';

class ReadingPage extends ConsumerStatefulWidget {
  const ReadingPage({
    super.key,
    required this.book,
    this.cfi,
    required this.initialThemes,
    this.heroTag,
  });

  final Book book;
  final String? cfi;
  final List<ReadTheme> initialThemes;
  final String? heroTag;

  @override
  ConsumerState<ReadingPage> createState() => ReadingPageState();
}

final GlobalKey<ReadingPageState> readingPageKey =
    GlobalKey<ReadingPageState>();
final epubPlayerKey = GlobalKey<EpubPlayerState>();

class ReadingPageState extends ConsumerState<ReadingPage>
    with WidgetsBindingObserver, TickerProviderStateMixin, RouteAware {
  final _reflowKey = GlobalKey<DocumentReflowReaderState>();
  final _documentRotation = DocumentReaderRotation();
  Future<void> setDocumentRotation(int angle) => _documentRotation.set(angle);
  bool? _reflowOcr;
  bool _compareOriginal = false, _reflowFocused = true;
  DocumentReflowAnchor? _reflowAnchor;
  DocumentReflowReaderState? get reflowReader => _reflowKey.currentState;
  bool get isReflowReading => _reflowOcr != null;
  bool get isComparingDocument => isReflowReading && _compareOriginal;
  bool get isReflowActive =>
      isReflowReading && (!isComparingDocument || _reflowFocused);

  void activateOriginalDocumentPane() => _activateDocumentPane(false);

  void _activateDocumentPane(bool reflow) {
    if (!isComparingDocument || _reflowFocused == reflow) return;
    epubPlayerKey.currentState?.removeOverlay();
    if (!reflow) reflowReader?.clearSelection();
    setState(() {
      _reflowFocused = reflow;
      _currentPage = empty;
      bottomBarOffstage = true;
    });
    _updatePageKeys();
    _requestReaderFocus();
  }

  Future<void> setDocumentComparison(bool enabled) async {
    hideBottomBar();
    setState(() {
      _compareOriginal = enabled;
      _reflowFocused = true;
    });
    if (enabled && !isReflowReading) {
      await openDocumentExtraction(reflow: true);
    }
    if (mounted) {
      epubPlayerKey.currentState?.refreshReadingTheme();
      _updatePageKeys();
      _requestReaderFocus();
    }
  }

  void originalDocumentPageChanged(int page) {
    if (isComparingDocument && !isReflowActive) {
      unawaited(reflowReader?.followOriginalPage(page));
    }
  }

  Future<void> openReflowAnchor(DocumentReflowAnchor anchor) async {
    if (anchor.original) {
      final player = epubPlayerKey.currentState;
      if (player == null || !mounted || _viewingOriginalNote) return;
      _viewingOriginalNote = true;
      reflowReader?.cancelLoading();
      player.removeOverlay();
      try {
        await player.pauseDocumentOcrCache();
        await reflowReader?.stopLoading();
        if (!mounted) return;
        await showDialog<void>(
            context: context,
            builder: (_) => DocumentOriginalNote(
                anchor: anchor,
                render: (request) => player.renderPdfRegion(
                    {...request, if (player.isImageEpub) 'source': 'epub'}),
                cancelRender: () => player.isImageEpub
                    ? player.cancelEpubImageRender()
                    : player.cancelPdfRegionRender()));
      } finally {
        _viewingOriginalNote = false;
        player.resumeDocumentOcrCache();
      }
      return;
    }
    _activateDocumentPane(true);
    if (isReflowReading && reflowReader != null) {
      await reflowReader!.navigate(anchor);
      return;
    }
    _reflowAnchor = anchor;
    await openDocumentExtraction(reflow: true, forceOcr: anchor.ocr);
  }

  bool _viewingOriginalNote = false;

  Future<void> closeDocumentReflow() async {
    if (!isReflowReading) return;
    hideBottomBar();
    reflowReader?.cancelLoading();
    epubPlayerKey.currentState?.removeOverlay();
    await audioHandler.stop();
    if (!mounted) return;
    setState(() {
      _reflowOcr = null;
      _reflowAnchor = null;
      _compareOriginal = false;
      _reflowFocused = true;
    });
    epubPlayerKey.currentState?.refreshReadingTheme();
    epubPlayerKey.currentState?.resumeDocumentOcrCache();
    _restoreReaderFocusAfterPanel();
  }

  Widget _documentBrightness() => BrightnessWidget(
      controller: AppBrightness.instance,
      onNightModeChanged: () {
        // Hidden originals update on return; comparison updates both surfaces.
        if (mounted) setState(() {});
        if (isComparingDocument) {
          epubPlayerKey.currentState?.refreshReadingTheme();
        }
      });

  Widget _buildDocumentReflow() {
    final player = epubPlayerKey.currentState!;
    final styles = DocumentTextStyleStore(Prefs().prefs);
    return DocumentReflowReader(
      key: _reflowKey,
      onReaderKeyEvent: _handleReaderKeyEvent,
      onKeyboardEligibilityChanged: _updatePageKeys,
      onNarrationInvalidated: (source) {
        if (identical(TtsHandler().tts.pageSource, source)) {
          unawaited(audioHandler.stop().catchError((Object error) {
            AnxLog.warning('Reflow TTS stop failed: ${error.runtimeType}');
          }));
        }
      },
      comparison: isComparingDocument,
      onComparisonChanged: setDocumentComparison,
      readerMenuVisible: isReflowActive && !bottomBarOffstage,
      onOpenReaderMenu: () {
        _activateDocumentPane(true);
        showBottomBar();
      },
      onCloseReaderMenu: hideBottomBar,
      onOpenReaderPanel: (panel) {
        _activateDocumentPane(true);
        showBottomBar();
        setState(() => _currentPage = panel);
      },
      brightness: _documentBrightness(),
      onExtract: () => openDocumentExtraction(forceOcr: true),
      onQuery: (text, source, translation) => showReaderPopup(context,
          enableDrag: false,
          builder: (_) => UnifiedQuery(
              text: text,
              contextText: source,
              initialSection: translation ? QuerySection.translation : null)),
      onAiDraft: EnvVar.enableAIFeature
          ? (text) => showAiChat(
              draftScreen: 'documentExtraction',
              content: text,
              sourceText: text,
              sendImmediate: false,
              forcePopup: true)
          : null,
      onBookmark: (anchor, text) async {
        final now = DateTime.now();
        await bookNoteDao.save(BookNote(
            bookId: player.book.id,
            content: text,
            cfi: anchor.encode(),
            chapter: reflowReader?.chapter ?? '',
            type: 'bookmark',
            color: '000000',
            createTime: now,
            updateTime: now));
      },
      readerActions: [
        IconButton(
            icon: const Icon(Icons.toc),
            tooltip: ModuStrings.text(context, '目录', 'Contents'),
            onPressed: () {
              reflowReader?.closeMenu();
              tocHandler();
            }),
        IconButton(
            icon: const Icon(EvaIcons.edit),
            tooltip: ModuStrings.text(context, '笔记', 'Notes'),
            onPressed: () {
              reflowReader?.closeMenu();
              noteHandler();
            }),
      ],
      store: DocumentReflowStore(player.cssBookKey),
      precache: player.ocrPrecache,
      onSourcePageChanged: player.updateDocumentOcrCachePage,
      forceOcr: _reflowOcr!,
      anchor: _reflowAnchor,
      initialStyle: styles.read(player.cssBookKey),
      saveStyle: (value) => styles.save(player.cssBookKey, value),
      info: player.documentReflowInfo,
      extractText: player.extractDocumentText,
      render: (request) => player.renderPdfRegion(
          {...request, if (player.isImageEpub) 'source': 'epub'}),
      cancelRender: () {
        if (player.isImageEpub) {
          player.cancelEpubImageRender();
        } else {
          player.cancelPdfRegionRender();
        }
      },
      onClose: closeDocumentReflow,
      clearMenu: player.removeOverlay,
      selectionInvalidated: player.reflowSelectionInvalidated,
      onPageChanged: (page) async {
        await audioHandler.stop();
        await player.goToDocumentPage(page);
      },
      loadNotes: () => bookNoteDao.selectBookNotesByBookId(player.book.id),
      onSelection: (anchor, text, contextText, rect, ids) async {
        if (!mounted || !isReflowReading) return;
        final box = _reflowKey.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return;
        final origin = box.localToGlobal(Offset.zero);
        await showContextMenu(
            context,
            (rect.left - origin.dx) / box.size.width,
            (rect.top - origin.dy) / box.size.height,
            (rect.right - origin.dx) / box.size.width,
            (rect.bottom - origin.dy) / box.size.height,
            text,
            anchor.encode(),
            null,
            false,
            Axis.horizontal,
            readerViewport: origin & box.size,
            contextText: contextText,
            annotationIds: ids);
      },
    );
  }

  static const empty = SizedBox.shrink();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late Book _book;
  late Widget _currentPage = empty;
  final Stopwatch _readTimeWatch = Stopwatch();
  DateTime? _sessionStart;
  Timer? _awakeTimer;
  PageRoute<dynamic>? _observedRoute;
  bool _readingRouteVisible = true;
  late final _readingSync = ReadingSyncScheduler(
    sync: (stillAllowed) async {
      if (!mounted || !stillAllowed()) return;
      // Drain actual saved reading actions; never create a new position/time.
      await epubPlayerKey.currentState?.saveReadingProgress();
      if (!mounted || !stillAllowed()) return;
      await ref.read(syncProvider.notifier).syncData(
            SyncDirection.both,
            ref,
            trigger: SyncTrigger.auto,
            shouldStart: () => mounted && stillAllowed(),
          );
    },
    onError: (error, _) =>
        AnxLog.warning('Reading timed sync: ${error.runtimeType}'),
  );

  void _updateReadingSync() {
    if (!mounted) return;
    _updatePageKeys();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _readingSync.update(
      enabled:
          Prefs().readingTimedSync && Prefs().webdavStatus && Prefs().autoSync,
      foreground: lifecycle == null || lifecycle == AppLifecycleState.resumed,
      readingVisible: _readingRouteVisible && !widget.book.isDeleted,
      minutes: Prefs().readingSyncMinutes,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (_aiLocale != locale) {
      _aiLocale = locale;
      _rebuildAiChat();
    }
    final route = ModalRoute.of(context);
    if (route is PageRoute && route != _observedRoute) {
      readerRouteObserver.unsubscribe(this);
      _observedRoute = route;
      _readingRouteVisible = route.isCurrent;
      readerRouteObserver.subscribe(this, route);
    }
    _updateReadingSync();
  }

  @override
  void didPushNext() {
    _readingRouteVisible = false;
    _updateReadingSync();
  }

  @override
  void didPopNext() {
    _readingRouteVisible = true;
    _updateReadingSync();
  }

  @override
  void didPop() {
    _readingRouteVisible = false;
    _updateReadingSync();
  }

  bool bottomBarOffstage = true;
  late String heroTag;
  Widget? _aiChat;
  String _aiDraftScreen = 'reader';
  Locale? _aiLocale;
  final aiChatKey = GlobalKey<AiChatStreamState>();
  static const double _aiChatMinWidth = 240;
  late double _aiChatWidth;
  static const double _aiChatMinHeight = 200;
  late double _aiChatHeight;
  bool _isResizingAiChat = false;
  bool bookmarkExists = false;
  bool _searchDialogOpen = false;
  bool _readerDrawerOpen = false;
  bool _quickMarkEnabled = false;
  bool _changingQuickMark = false;

  Future<void> _toggleQuickMarkMenu() async {
    if (_changingQuickMark) return;
    final previous = Prefs().quickMarkShowMenu;
    setState(() {
      _changingQuickMark = true;
      Prefs().quickMarkShowMenu = !previous;
    });
    try {
      final applied = await epubPlayerKey.currentState
          ?.setQuickMarkEnabled(_quickMarkEnabled);
      if (applied != true) throw StateError('Reader not ready');
    } catch (_) {
      Prefs().quickMarkShowMenu = previous;
      if (mounted) {
        AnxToast.show(ModuStrings.text(context, '无法切换标记菜单，请重试。',
            'Could not switch the marking menu. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _changingQuickMark = false);
    }
  }

  Future<void> _toggleQuickMark() async {
    if (!AnxPlatform.isMobile || _changingQuickMark) return;
    setState(() => _changingQuickMark = true);
    final requested = !_quickMarkEnabled;
    try {
      final enabled =
          await epubPlayerKey.currentState?.setQuickMarkEnabled(requested) ??
              false;
      if (!mounted) return;
      setState(() => _quickMarkEnabled = enabled);
      if (requested && !enabled) {
        AnxToast.show(ModuStrings.text(context, '请等待正文载入。快速标记暂不支持 PDF 和固定版式书籍。',
            'Wait for the book to load. PDF and fixed-layout books are not supported.'));
      } else if (enabled) {
        showOrHideAppBarAndBottomBar(false);
        AnxToast.show(ModuStrings.text(context, '直接划过文字，松手即高亮；退出后恢复滑动翻页。',
            'Swipe across text to highlight. Exit to resume swipe navigation.'));
      }
    } catch (_) {
      AnxToast.show(ModuStrings.text(context, '无法切换快速标记，请重试。',
          'Could not switch quick mark. Please retry.'));
    } finally {
      if (mounted) setState(() => _changingQuickMark = false);
    }
  }

  late final FocusNode _readerFocusNode;
  final _readerWebViewFocusScope =
      FocusScopeNode(debugLabel: 'book_webview_focus_scope');
  late final ReaderPageKeys _pageKeys;

  bool get _canUsePageKeys {
    // Opening the drawer removes menu controls. Their old FocusNode context
    // can outlive its Element, so check route/panel eligibility before focus.
    if (!mounted ||
        widget.book.isDeleted ||
        !_readingRouteVisible ||
        _observedRoute?.isCurrent != true ||
        !bottomBarOffstage ||
        _readerDrawerOpen ||
        _searchDialogOpen ||
        _aiChat != null) {
      return false;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    if (isReflowActive && reflowReader?.canUseReadingKeys == true) return true;
    return !readerFocusBlocksPageKeys(
        FocusManager.instance.primaryFocus?.context);
  }

  bool get _canUseNarrationKeys =>
      mounted &&
      (!isReflowReading || isReflowActive) &&
      !widget.book.isDeleted &&
      _readingRouteVisible &&
      _observedRoute?.isCurrent == true &&
      !_readerDrawerOpen &&
      !_searchDialogOpen &&
      _aiChat == null &&
      (bottomBarOffstage || _currentPage is TtsWidget) &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed) &&
      ((isReflowActive && reflowReader?.canUseReadingKeys == true) ||
          !readerFocusBlocksPageKeys(
              FocusManager.instance.primaryFocus?.context));

  bool _isNarrationShortcut(String action) =>
      const ['playPause', 'previousPassage', 'nextPassage'].contains(action);

  bool get _documentArrowPan =>
      !isReflowActive &&
      epubPlayerKey.currentState?.supportsDocumentImages == true &&
      (epubPlayerKey.currentState?.pdfZoom.value ?? 1) > 1;

  void _updatePageKeys({bool force = false}) {
    if (!mounted) return;
    epubPlayerKey.currentState?.setDocumentReaderActive(_canUsePageKeys);
    _pageKeys.update(
        active: _canUsePageKeys || _canUseNarrationKeys,
        volume: _canUsePageKeys && Prefs().volumeKeyTurnPage,
        shortcuts: [
          ...Prefs()
              .readerShortcuts
              .nativeBindings(ctrlBrackets: Prefs().keyboardShortcutTurnPage)
              .where((binding) =>
                  _canUsePageKeys ||
                  const [4, 6, 7].contains(binding['action']))
              .where((binding) =>
                  !_documentArrowPan ||
                  binding['modifiers'] != 0 ||
                  !const [19, 20, 21, 22].contains(binding['keyCode'])),
          if (_canUsePageKeys && _documentArrowPan)
            for (final entry in documentPanKeys.entries)
              {
                'keyCode': readerShortcutKeys[entry.value]!.$2,
                'modifiers': 0,
                'action': entry.key
              },
        ],
        force: force);
  }

  void refreshDocumentReaderActivity() => _updatePageKeys();

  void _refreshReaderHostState() {
    if (!mounted) return;
    _updatePageKeys(force: true);
    _restoreReaderSystemUi();
  }

  void _restoreReaderSystemUi() {
    if (!AnxPlatform.isAndroid) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Never hide bars on another route, over an editor/keyboard, or while a
      // reader panel is open. Do not react to ordinary transient-bar swipes.
      if (!mounted ||
          !_canUsePageKeys ||
          !Prefs().hideStatusBar ||
          View.of(context).viewInsets.bottom > 0) {
        return;
      }
      hideStatusBar();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void initState() {
    _readerFocusNode = FocusNode(debugLabel: 'reading_page_focus');
    _pageKeys = ReaderPageKeys(
        onShortcut: (code) {
          if (documentPanKeys.containsKey(code)) {
            if (_canUsePageKeys && _documentArrowPan) {
              epubPlayerKey.currentState
                  ?.panDocumentFromKeyboard(documentPanKeys[code]!);
            }
            return;
          }
          for (final action in ReaderAction.values) {
            if (action.nativeCode == code &&
                (_isNarrationShortcut(action.name)
                    ? _canUseNarrationKeys
                    : _canUsePageKeys)) {
              _sendReaderShortcut(action.name);
            }
          }
        },
        onHostStateChanged: _refreshReaderHostState,
        onDirection: (direction) {
          if (_canUsePageKeys) {
            epubPlayerKey.currentState?.turnPageFromKeyboard(direction);
          }
        });
    FocusManager.instance.addListener(_updatePageKeys);

    // Initialize AI panel sizes from persistent storage
    _aiChatWidth = Prefs().aiPanelWidth;
    _aiChatHeight = Prefs().aiPanelHeight;

    if (widget.book.isDeleted) {
      Navigator.pop(context);
      AnxToast.show(L10n.of(context).bookDeleted);
      return;
    }
    if (Prefs().hideStatusBar) {
      hideStatusBar();
    }
    if (AnxPlatform.isDesktop && Prefs().readerFullscreen) {
      unawaited(setReaderFullscreen(true));
    }

    WidgetsBinding.instance.addObserver(this);
    Prefs().addListener(_updateReadingSync);
    _readTimeWatch.start();
    _sessionStart = DateTime.now();
    setAwakeTimer(Prefs().awakeTime);

    _book = widget.book;
    heroTag = widget.heroTag ?? 'preventHeroWhenStart';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestReaderFocus();
      }
    });
    // delay 1000ms to prevent hero animation
    if (widget.heroTag == null) {
      Future.delayed(const Duration(milliseconds: 2000), () {
        if (mounted) {
          setState(() {
            heroTag = _book.coverFullPath;
          });
        }
      });
    }
    super.initState();
  }

  @override
  void dispose() {
    unawaited(_documentRotation.close().catchError((Object error) {
      AnxLog.warning('Reader rotation restore failed: ${error.runtimeType}');
    }));
    epubPlayerKey.currentState?.detachNarration();
    FocusManager.instance.removeListener(_updatePageKeys);
    _pageKeys.dispose();
    Prefs().removeListener(_updateReadingSync);
    readerRouteObserver.unsubscribe(this);
    _readingSync.dispose();
    if (AnxPlatform.isDesktop) unawaited(_fullscreen.close());
    _readTimeWatch.stop();
    _awakeTimer?.cancel();
    unawaited(ReaderWakelock.setEnabled(false));
    showStatusBar();
    WidgetsBinding.instance.removeObserver(this);
    readingTimeDao.insertReadingTime(
      ReadingTime(
        bookId: _book.id,
        readingTime: _readTimeWatch.elapsed.inSeconds,
        round: _book.currentRound,
      ),
      startedAt: _sessionStart,
    );
    _sessionStart = null;
    audioHandler.stop();
    _readerFocusNode.dispose();
    _readerWebViewFocusScope.dispose();
    super.dispose();
  }

  final _fullscreen = ReaderFullscreenSession();
  Future<void> setReaderFullscreen(bool value) => _fullscreen.set(value);

  void _requestReaderFocus() {
    // Restore after menu/focus updates on every platform. Focusing the outer
    // keyboard handler makes the native selection inactive again.
    _restoreReaderFocusAfterPanel();
  }

  /// A completed, unselected tap in the book returns keyboard ownership from
  /// the AI editor to the reader. Keeping the panel open must not block this.
  void focusReaderFromTap() {
    _activateDocumentPane(false);
    if (!mounted || !AnxPlatform.isDesktop || !bottomBarOffstage) return;
    _focusReaderSurface();
  }

  void _focusReaderSurface() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (isReflowActive) {
      reflowReader?.requestKeyboardFocus();
      return;
    }
    if (AnxPlatform.isWindows || AnxPlatform.isLinux) {
      // Texture-backed plugins receive keys through their own child Focus.
      // Restore that remembered child, never the surrounding paging handler.
      _readerWebViewFocusScope.requestFocus();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    unawaited(restoreNativeReaderFocus(() async {
      if (mounted && !isReflowActive) {
        return await epubPlayerKey.currentState?.requestNativeFocus();
      }
      return null;
    }));
  }

  void _restoreReaderFocusAfterPanel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !bottomBarOffstage ||
          _readerDrawerOpen ||
          _searchDialogOpen ||
          _aiChat != null ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _focusReaderSurface();
      _restoreReaderSystemUi();
    });
  }

  void _closeAiChat() {
    setState(() => _aiChat = null);
    showOrHideAppBarAndBottomBar(false);
  }

  void _releaseReaderFocus() {
    if (_readerFocusNode.hasFocus) {
      _readerFocusNode.unfocus();
    }
  }

  KeyEventResult _handleReaderKeyEvent(FocusNode node, KeyEvent event) {
    final panKey = ReaderKey.fromEvent(event);
    if (_canUsePageKeys &&
        _documentArrowPan &&
        panKey?.modifiers == 0 &&
        documentPanKeys.containsValue(panKey!.key) &&
        readerOwnsPageKeys(_readerFocusNode, _readerWebViewFocusScope,
            windows: AnxPlatform.isWindows)) {
      epubPlayerKey.currentState?.panDocumentFromKeyboard(panKey.key);
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final key = ReaderKey.fromEvent(event);
      final action = Prefs().readerShortcuts.actions()[key?.id];
      if (action != null &&
          _isNarrationShortcut(action) &&
          _canUseNarrationKeys) {
        if (event is! KeyRepeatEvent) _sendReaderShortcut(action);
        return KeyEventResult.handled;
      }
    }
    if (!_canUsePageKeys ||
        _searchDialogOpen ||
        ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    if (!(isReflowActive && reflowReader?.canUseReadingKeys == true) &&
        !readerOwnsPageKeys(_readerFocusNode, _readerWebViewFocusScope,
            windows: AnxPlatform.isWindows)) {
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = ReaderKey.fromEvent(event);
    final action = Prefs()
        .readerShortcuts
        .actions(ctrlBrackets: Prefs().keyboardShortcutTurnPage)[key?.id];
    if (action != null) {
      if (event is! KeyRepeatEvent ||
          action == 'previous' ||
          action == 'next') {
        _sendReaderShortcut(action);
      }
      return KeyEventResult.handled;
    }

    // Other shortcuts belong to the child WebView/control, not its ancestor.
    if (!_readerFocusNode.hasPrimaryFocus) return KeyEventResult.ignored;

    if (Prefs().volumeKeyTurnPage) {
      if (event.physicalKey == PhysicalKeyboardKey.audioVolumeUp) {
        epubPlayerKey.currentState?.prevPage();
        return KeyEventResult.handled;
      }
      if (event.physicalKey == PhysicalKeyboardKey.audioVolumeDown) {
        epubPlayerKey.currentState?.nextPage();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _sendReaderShortcut(String action) {
    if (_isNarrationShortcut(action) &&
        (_currentPage is TtsWidget || isReflowActive)) {
      unawaited(handleReaderShortcut(action));
      return;
    }
    final direction = action == 'next'
        ? 1
        : action == 'previous'
            ? -1
            : 0;
    if (direction != 0) {
      epubPlayerKey.currentState?.turnPageFromKeyboard(direction);
    } else {
      epubPlayerKey.currentState?.readerActionFromKeyboard(action);
    }
  }

  bool _shortcutBusy = false;
  Future<void> handleReaderShortcut(String action) async {
    if ((_isNarrationShortcut(action)
            ? !_canUseNarrationKeys
            : !_canUsePageKeys) ||
        _shortcutBusy) {
      return;
    }
    if (action == 'menu') {
      showOrHideAppBarAndBottomBar(true);
      return;
    }
    final state = TtsHandler().ttsStateNotifier.value;
    if (state != TtsStateEnum.playing && state != TtsStateEnum.paused) return;
    _shortcutBusy = true;
    try {
      switch (action) {
        case 'playPause':
          if (state == TtsStateEnum.playing) {
            await audioHandler.pause();
          } else {
            await audioHandler.play();
          }
        case 'previousPassage':
          await _moveNarration(forward: false);
        case 'nextPassage':
          await _moveNarration(forward: true);
      }
    } catch (_) {
      if (mounted) {
        AnxToast.show(ModuStrings.text(
            context, '朗读操作失败，请重试。', 'Narration action failed. Please retry.'));
      }
    } finally {
      _shortcutBusy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final reader = epubPlayerKey.currentState;
    if (reader != null) {
      unawaited(reader.setTtsBackground(state != AppLifecycleState.resumed));
      if (state == AppLifecycleState.resumed) {
        reader.resumeDocumentOcrCache();
      } else {
        unawaited(reader.pauseDocumentOcrCache());
      }
    }
    _updateReadingSync();
    switch (state) {
      case AppLifecycleState.resumed:
        _refreshReaderHostState();
        if (!_readTimeWatch.isRunning) {
          _readTimeWatch.start();
        }
        _sessionStart ??= DateTime.now();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_readTimeWatch.isRunning) {
          _readTimeWatch.stop();
        }
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) {
          final elapsedSeconds = _readTimeWatch.elapsed.inSeconds;
          if (elapsedSeconds > 5) {
            epubPlayerKey.currentState?.saveReadingProgress();
            readingTimeDao.insertReadingTime(
              ReadingTime(
                bookId: _book.id,
                readingTime: elapsedSeconds,
                round: _book.currentRound,
              ),
              startedAt: _sessionStart,
            );
          }
          _readTimeWatch.reset();
          _sessionStart = null;
        }
        break;
    }
  }

  Future<void> setAwakeTimer(int minutes) async {
    _awakeTimer?.cancel();
    _awakeTimer = null;
    unawaited(ReaderWakelock.setEnabled(true));
    _awakeTimer = Timer.periodic(Duration(minutes: minutes), (timer) {
      unawaited(ReaderWakelock.setEnabled(false));
      _awakeTimer?.cancel();
      _awakeTimer = null;
    });
  }

  void resetAwakeTimer() {
    setAwakeTimer(Prefs().awakeTime);
  }

  void showBottomBar() {
    if (isReflowReading) epubPlayerKey.currentState?.removeOverlay();
    setState(() {
      // The bars are painted over the reader in the body Stack. Changing the
      // system UI mode here changes WebView viewport metrics and repaginates
      // the book even though the reader itself has not moved.
      bottomBarOffstage = false;
      _releaseReaderFocus();
    });
    _updatePageKeys();
  }

  void hideBottomBar() {
    setState(() {
      _currentPage = empty;
      bottomBarOffstage = true;
      _requestReaderFocus();
    });
    _updatePageKeys();
  }

  void showOrHideAppBarAndBottomBar(bool show) {
    if (show) {
      showBottomBar();
    } else {
      hideBottomBar();
    }
  }

  Future<void> tocHandler() async {
    if (!mounted || _readerDrawerOpen) {
      return;
    }
    _readerDrawerOpen = true;
    hideBottomBar();
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> searchHandler() async {
    if (isReflowActive) {
      await reflowReader?.readerAction('search');
      return;
    }
    if (_searchDialogOpen || !mounted) return;
    _searchDialogOpen = true;
    hideBottomBar();
    _releaseReaderFocus();
    try {
      await showBookSearchDialog(
        context,
        onSearch: (query) => epubPlayerKey.currentState?.search(query),
        onClear: () => epubPlayerKey.currentState?.clearSearch(),
        onNavigate: (cfi) async =>
            await epubPlayerKey.currentState?.navigateSearch(cfi),
      );
    } finally {
      _searchDialogOpen = false;
      if (mounted) _requestReaderFocus();
    }
  }

  void noteHandler() {
    setState(() {
      _currentPage = ReadingNotes(book: _book);
    });
  }

  Future<void> styleHandler() async {
    if (isReflowActive) {
      reflowReader?.openStyleMenu();
      return;
    }
    List<ReadTheme> themes = await themeDao.selectThemes();
    if (!mounted || bottomBarOffstage) return;
    setState(() {
      _currentPage = StyleWidget(
        themes: themes,
        epubPlayerKey: epubPlayerKey,
        setCurrentPage: (Widget page) {
          setState(() {
            _currentPage = page;
          });
        },
        hideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
      );
    });
  }

  Future<void> _documentPanel({required bool textOnly}) async {
    if (!mounted) return;
    if (!textOnly && isReflowReading && !isComparingDocument) {
      await closeDocumentReflow();
    }
    final player = epubPlayerKey.currentState;
    if (!mounted || player == null) return;
    showBottomBar();
    setState(() => _currentPage = DocumentStyleWidget(
          key: ValueKey('document-$textOnly'),
          player: player,
          textOnly: textOnly,
          comparison: isComparingDocument,
          onComparisonChanged: setDocumentComparison,
          openReflow: (ocr) =>
              openDocumentExtraction(reflow: true, forceOcr: ocr),
          openExtraction: () => openDocumentExtraction(),
        ));
  }

  Future<void> ttsHandler() async {
    final source = isReflowActive ? reflowReader?.narrationSource : null;
    if (isReflowReading && source == null) return;
    setState(() {
      _currentPage = TtsWidget(
        key: ValueKey(source),
        epubPlayerKey: epubPlayerKey,
        pageSource: source,
      );
    });
    _updatePageKeys();
  }

  Future<void> _returnToNarration() async {
    if (isReflowReading) {
      reflowReader?.narrationSource?.showCurrent();
      return;
    }
    await epubPlayerKey.currentState?.returnToTtsPosition();
  }

  Future<void> _moveNarration({required bool forward}) async {
    if (isReflowReading) {
      final source = reflowReader?.narrationSource;
      if (source == null || !identical(TtsHandler().tts.pageSource, source)) {
        return;
      }
      await (forward ? TtsHandler().playNext() : TtsHandler().playPrevious());
      return;
    }
    final player = epubPlayerKey.currentState;
    if (player == null || !player.mounted) return;
    await TtsHandler().navigateParagraph(
        forward ? player.ttsNextParagraph : player.ttsPrevParagraph,
        forward: forward);
    if (mounted && player.mounted && epubPlayerKey.currentState == player) {
      await player.returnToTtsPosition();
    }
  }

  Future<void> _readAloudFromHere() async {
    if (isReflowReading) {
      final source = reflowReader?.narrationSource;
      if (source == null) return;
      await audioHandler.stop();
      if (!mounted || !source.valid) return;
      source.rewind();
      await TtsHandler().init(
          source.currentText, source.nextText, source.previousText,
          pageSource: source);
      if (mounted && source.valid) await audioHandler.play();
      return;
    }
    final player = epubPlayerKey.currentState;
    if (player == null || !player.mounted || player.cfi.isEmpty) return;
    // Freeze the visible destination before stopping speech clears its cursor.
    final destination = player.cfi;
    await audioHandler.stop();
    if (!mounted || !player.mounted || epubPlayerKey.currentState != player) {
      return;
    }
    await TtsHandler().init(() => player.initTts(fromCfi: destination),
        player.ttsNext, player.ttsPrev);
    if (!mounted || !player.mounted || epubPlayerKey.currentState != player) {
      return;
    }
    await audioHandler.play();
  }

  void _openNarrationSettings() {
    if (isReflowReading) _activateDocumentPane(true);
    showBottomBar();
    ttsHandler();
  }

  void translationHandler() {
    if (isReflowActive) {
      unawaited(reflowReader?.readerAction('translate'));
      return;
    }
    setState(() {
      _currentPage = TranslationWidget(
        bookId: _book.id,
        epubPlayerKey: epubPlayerKey,
      );
    });
  }

  Future<void> _copyChapterContent() async {
    if (isReflowActive) {
      await reflowReader?.readerAction('copy');
      return;
    }
    try {
      final content = await epubPlayerKey.currentState?.theChapterContent();
      if (!mounted) return;
      if (content != null && content.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: content));
      }
      if (!mounted) return;
      AnxToast.show(
          L10n.of(context).readingPageCopiedCharacters(content?.length ?? 0));
    } catch (_) {
      if (mounted) {
        AnxToast.show(L10n.of(context).readingPageErrorCopyingContent);
      }
    }
  }

  void _openBookDetails() {
    Navigator.push(
        context,
        MotionCupertinoPageRoute(
          builder: (_) => BookDetail(book: widget.book),
        ));
  }

  Future<void> showSelectionTranslation(String content,
      {String? contextText}) async {
    showOrHideAppBarAndBottomBar(false);
    await showReaderPopup(context,
        builder: (_) => TranslationMenu(
              content: content,
              contextText: contextText,
            ));
    _restoreReaderFocusAfterPanel();
  }

  Future<void> showSelectionDictionary(String content) async {
    showOrHideAppBarAndBottomBar(false);
    await showReaderPopup(context,
        builder: (_) => DictionaryLookup(word: content));
    _restoreReaderFocusAfterPanel();
  }

  Future<void> showUnifiedQuery(String content, {String? contextText}) async {
    showOrHideAppBarAndBottomBar(false);
    try {
      await showReaderPopup(context,
          enableDrag: false,
          builder: (_) =>
              UnifiedQuery(text: content, contextText: contextText));
    } finally {
      _restoreReaderFocusAfterPanel();
    }
  }

  Future<void> showSelectionSearch(String content) async {
    showOrHideAppBarAndBottomBar(false);
    try {
      await showSelectionSearchBrowser(context, text: content);
    } finally {
      _restoreReaderFocusAfterPanel();
    }
  }

  double _aiChatMaxWidth(BuildContext context) {
    final totalWidth = MediaQuery.sizeOf(context).width;
    final maxByPercentage = totalWidth * 0.65;
    final maxByRemaining = totalWidth - 320;
    final maxWidth = math.min(maxByPercentage, maxByRemaining);
    return math.max(_aiChatMinWidth, maxWidth);
  }

  double _aiChatMaxHeight(BuildContext context) {
    final totalHeight = MediaQuery.sizeOf(context).height;
    final maxByPercentage = totalHeight * 0.60;
    final maxByRemaining = totalHeight - 320;
    final maxHeight = math.min(maxByPercentage, maxByRemaining);
    return math.max(_aiChatMinHeight, maxHeight);
  }

  void _beginAiChatResize(double globalDx) {
    setState(() {
      _isResizingAiChat = true;
    });
  }

  void _applyAiChatResizeDelta(double delta, BuildContext context) {
    final maxWidth = _aiChatMaxWidth(context);
    final updated =
        (_aiChatWidth - delta).clamp(_aiChatMinWidth, maxWidth).toDouble();
    if (updated != _aiChatWidth) {
      setState(() {
        _aiChatWidth = updated;
      });
    }
  }

  void _endAiChatResize() {
    if (_isResizingAiChat) {
      setState(() {
        _isResizingAiChat = false;
      });
      // Save the panel sizes to persistent storage
      Prefs().aiPanelWidth = _aiChatWidth;
      Prefs().aiPanelHeight = _aiChatHeight;
    }
  }

  void _beginAiChatResizeVertical(double globalDy) {
    setState(() {
      _isResizingAiChat = true;
    });
  }

  void _applyAiChatResizeDeltaVertical(double delta, BuildContext context) {
    final maxHeight = _aiChatMaxHeight(context);
    final updated =
        (_aiChatHeight - delta).clamp(_aiChatMinHeight, maxHeight).toDouble();
    if (updated != _aiChatHeight) {
      setState(() {
        _aiChatHeight = updated;
      });
    }
  }

  Future<void> onLoadEnd() async {
    if (Prefs().autoSummaryPreviousContent) {
      final previousContent =
          await epubPlayerKey.currentState!.previousContent(2000);
      if (!mounted) return;
      final prompt = generatePromptSummaryThePreviousContent(previousContent);
      await showReaderPopup(
        context,
        builder: (context) => ProviderScope(
          overrides: [
            aiChatProvider(AiChatScope.selection).overrideWith(AiChat.new),
          ],
          child: AiChatStream(
            scope: AiChatScope.selection,
            draftScreen: 'reader.previous-content',
            title: L10n.of(context).readingPageSummaryPreviousContent,
            initialMessage: prompt.buildString(),
            initialSourceText: previousContent,
            initialSkillId: 'selection_toolbar',
            initialSelectionRequest: true,
            newConversation: true,
            sendImmediate: true,
            showSkillControls: false,
          ),
        ),
      );
    }
  }

  List<Widget> _buildAiChatTrailing(BuildContext context) {
    return [
      IconButton(
        onPressed: () {
          setState(() {
            Prefs().aiPanelPosition =
                Prefs().aiPanelPosition == AiPanelPositionEnum.right
                    ? AiPanelPositionEnum.bottom
                    : AiPanelPositionEnum.right;
            // Rebuild the _aiChat widget to update the button
            _rebuildAiChat();
          });
        },
        icon: Icon(
          Prefs().aiPanelPosition == AiPanelPositionEnum.right
              ? Icons.arrow_downward
              : Icons.arrow_forward,
        ),
        tooltip: Prefs().aiPanelPosition == AiPanelPositionEnum.right
            ? L10n.of(context).aiShowAtBottom
            : L10n.of(context).aiShowAtRight,
      ),
      IconButton(
        onPressed: _closeAiChat,
        icon: const Icon(Icons.close),
      ),
    ];
  }

  void _rebuildAiChat() {
    if (_aiChat == null) return;
    final maxWidth = _aiChatMaxWidth(context);
    final maxHeight = _aiChatMaxHeight(context);
    _aiChatWidth = _aiChatWidth.clamp(_aiChatMinWidth, maxWidth);
    _aiChatHeight = _aiChatHeight.clamp(_aiChatMinHeight, maxHeight);
    _aiChat = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: AiChatStream(
            key: aiChatKey,
            scope: AiChatScope.reader,
            draftScreen: _aiDraftScreen,
            initialMessage: null,
            sendImmediate: false,
            quickPromptChips: _getAiQuickPromptChips(),
            quickPromptChipsBuilder: _getAiQuickPromptChips,
            trailing: _buildAiChatTrailing(context),
          ),
        ),
      ],
    );
  }

  List<AiQuickPromptChip> _getAiQuickPromptChips() {
    return configuredReadingSkillChips(Localizations.localeOf(context));
  }

  Future<void> openDocumentExtraction(
      {bool reflow = false, bool forceOcr = false}) async {
    final player = epubPlayerKey.currentState;
    if (player == null || !player.supportsDocumentImages) return;
    final bookKey = player.cssBookKey;
    hideBottomBar();
    if (!reflow) {
      await player.pauseDocumentOcrCache();
      await reflowReader?.stopLoading();
    }
    if (!mounted) return;
    if (reflow) {
      await audioHandler.stop();
      if (!mounted || epubPlayerKey.currentState?.cssBookKey != bookKey) return;
      player.removeOverlay();
      _activateDocumentPane(true);
      if (isReflowReading && reflowReader != null) {
        await reflowReader!.setMode(forceOcr);
      } else {
        setState(() => _reflowOcr = forceOcr);
      }
      _updatePageKeys();
      _requestReaderFocus();
      return;
    }
    final textStyles = DocumentTextStyleStore(Prefs().prefs);
    reflowReader?.closeMenu();
    int? comparisonPage;
    bool? comparisonEnabled;
    final text = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => Scaffold(
          body: DocumentExtractionPanel(
        comparison: isComparingDocument,
        onComparisonChanged: (page, enabled) {
          comparisonPage = page;
          comparisonEnabled = enabled;
          Navigator.of(context).pop();
        },
        reflowStore: DocumentReflowStore(bookKey),
        brightness: _documentBrightness(),
        narrationBuilder: player.isPdfDocument
            ? null
            : (text) =>
                TtsWidget(epubPlayerKey: epubPlayerKey, extractedText: text),
        stopNarration: () => audioHandler.stop(),
        initialTextStyle: textStyles.read(bookKey),
        saveTextStyle: (style) => textStyles.save(bookKey, style),
        forceOcr: forceOcr,
        info: player.isImageEpub ? player.epubImageInfo : player.pdfRegionInfo,
        extractText: player.extractDocumentText,
        render: (request) => player.renderPdfRegion({
          ...request,
          if (player.isImageEpub) 'source': 'epub',
        }),
        cancelRender: () {
          if (player.isImageEpub) {
            player.cancelEpubImageRender();
          } else {
            player.cancelPdfRegionRender();
          }
        },
      )),
    ));
    if (!mounted || epubPlayerKey.currentState?.cssBookKey != bookKey) return;
    player.resumeDocumentOcrCache();
    if (comparisonEnabled != null) {
      await player.goToDocumentPage(comparisonPage!);
      if (!mounted) return;
      await setDocumentComparison(comparisonEnabled!);
      await reflowReader?.followOriginalPage(comparisonPage!);
      return;
    }
    if (!isReflowReading) player.refreshReadingTheme();
    if (text == null || text.trim().isEmpty) {
      _restoreReaderFocusAfterPanel();
      return;
    }
    // Open the familiar chat with a draft. Preserve the conversation and do not
    // transmit recognized book content until the user explicitly presses Send.
    // Repeated extraction of the same text must also refill an existing editor;
    // widget initial-value equality alone would otherwise skip this update.
    if (_aiChat != null) aiChatKey.currentState?.setReaderSourceText(text);
    await showAiChat(
        content: text,
        sourceText: text,
        sendImmediate: false,
        newConversation: false);
  }

  Future<void> showAiChat({
    String draftScreen = 'reader',
    String? content,
    String? sourceText,
    String? sourceContext,
    bool selectionRequest = false,
    bool webSearch = false,
    String? skillId,
    bool sendImmediate = false,
    bool newConversation = false,
    bool forcePopup = false,
  }) async {
    _aiDraftScreen = draftScreen;
    List<AiQuickPromptChip> quickPrompts = _getAiQuickPromptChips();

    // Determine display mode
    final displayMode = Prefs().aiChatDisplayMode;
    final screenWidth = MediaQuery.sizeOf(navigatorKey.currentContext!).width;

    bool shouldShowAsPopup = false;

    switch (displayMode) {
      case AiChatDisplayMode.adaptive:
        // Show as popup if width < 600
        shouldShowAsPopup = screenWidth < 600;
        break;
      case AiChatDisplayMode.popup:
        // Always show as popup
        shouldShowAsPopup = true;
        break;
      case AiChatDisplayMode.split:
        // Always show as split screen
        shouldShowAsPopup = false;
        break;
    }

    shouldShowAsPopup = shouldShowAsPopup || forcePopup;
    if (shouldShowAsPopup) {
      // A shared GlobalKey must not be mounted in both the split panel and
      // popup. Dispose the panel (and cancel its stream) before reusing it.
      if (_aiChat != null) {
        _closeAiChat();
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      await showReaderPopup(navigatorKey.currentContext!,
          builder: (context) => AiChatStream(
                key: aiChatKey,
                scope: AiChatScope.reader,
                draftScreen: draftScreen,
                initialMessage: content,
                initialSourceText: sourceText,
                initialSourceContext: sourceContext,
                initialSelectionRequest: selectionRequest,
                initialWebSearch: webSearch,
                initialSkillId: skillId,
                newConversation: newConversation,
                sendImmediate: sendImmediate,
                quickPromptChips: quickPrompts,
                quickPromptChipsBuilder: _getAiQuickPromptChips,
              ));
      _restoreReaderFocusAfterPanel();
    } else {
      final existingChat = aiChatKey.currentState;
      setState(() {
        final maxWidth = _aiChatMaxWidth(navigatorKey.currentContext!);
        final maxHeight = _aiChatMaxHeight(navigatorKey.currentContext!);
        _aiChatWidth = _aiChatWidth.clamp(_aiChatMinWidth, maxWidth);
        _aiChatHeight = _aiChatHeight.clamp(_aiChatMinHeight, maxHeight);
        _aiChat = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: AiChatStream(
                key: aiChatKey,
                scope: AiChatScope.reader,
                draftScreen: draftScreen,
                initialMessage: content,
                initialSourceText: sourceText,
                initialSourceContext: sourceContext,
                initialSelectionRequest: selectionRequest,
                initialWebSearch: webSearch,
                initialSkillId: skillId,
                newConversation: newConversation,
                sendImmediate: existingChat == null && sendImmediate,
                quickPromptChips: quickPrompts,
                quickPromptChipsBuilder: _getAiQuickPromptChips,
                trailing: _buildAiChatTrailing(navigatorKey.currentContext!),
              ),
            ),
          ],
        );
      });
      if (existingChat != null && (newConversation || sendImmediate)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || aiChatKey.currentState != existingChat) return;
          existingChat.beginSelectionQuestion(
              message: content ?? '',
              sourceText: sourceText ?? content ?? '',
              sourceContext: sourceContext,
              selectionRequest: selectionRequest,
              webSearch: webSearch,
              skillId: skillId,
              sendImmediate: sendImmediate);
        });
      }
    }
  }

  void updateState() {
    if (mounted) {
      setState(() {
        bookmarkExists = epubPlayerKey.currentState!.bookmarkExists;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final documentPlayer = epubPlayerKey.currentState;
    final documentMenu =
        !isReflowActive && documentPlayer?.supportsDocumentImages == true;
    final documentSettings = _currentPage is DocumentStyleWidget;
    // Route changes (including dialogs), AI panels and settings must release
    // native keys; none of these depend on the WebView's Flutter focus node.
    _updatePageKeys();
    final compactToolbar = MediaQuery.sizeOf(context).width < 420;
    var aiButton = IconButton(
      tooltip: L10n.of(context).aiChat,
      icon: const Icon(Icons.auto_awesome),
      onPressed: () async {
        if (isReflowActive) {
          await reflowReader?.readerAction('ai');
          return;
        }
        // Determine if should show as split based on display mode
        final displayMode = Prefs().aiChatDisplayMode;
        final screenWidth = MediaQuery.sizeOf(context).width;

        bool shouldShowAsSplit = false;
        switch (displayMode) {
          case AiChatDisplayMode.adaptive:
            shouldShowAsSplit = screenWidth >= 600;
            break;
          case AiChatDisplayMode.split:
            shouldShowAsSplit = true;
            break;
          case AiChatDisplayMode.popup:
            shouldShowAsSplit = false;
            break;
        }

        if (shouldShowAsSplit && _aiChat != null) {
          _closeAiChat();
          return;
        }

        showOrHideAppBarAndBottomBar(false);
        showAiChat();
      },
    );
    Offstage controller = Offstage(
      offstage: bottomBarOffstage,
      child: PointerInterceptor(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                  onTap: () {
                    showOrHideAppBarAndBottomBar(false);
                  },
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {},
                  onVerticalDragEnd: (details) {},
                  child: Container(
                    color: Colors.black.withAlpha(30),
                  )),
            ),
            Column(
              children: [
                if (identical(_currentPage, empty))
                  AppBar(
                    title: Text(_book.title, overflow: TextOverflow.ellipsis),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        // close reading page
                        Navigator.pop(context);
                      },
                    ),
                    actions: [
                      if (AnxPlatform.isMobile && !isReflowReading)
                        QuickMarkToggle(
                            enabled: _quickMarkEnabled,
                            onPressed:
                                _changingQuickMark ? null : _toggleQuickMark),
                      if (EnvVar.enableAIFeature) aiButton,
                      TranslationToolbarAction(
                        mode: isReflowActive
                            ? null
                            : epubPlayerKey.currentState?.translationMode,
                        onOpenSettings: translationHandler,
                        onStop: () async {
                          try {
                            await epubPlayerKey.currentState
                                ?.setTranslationMode(TranslationModeEnum.off);
                          } catch (_) {
                            // Cancellation occurs before the WebView update.
                          }
                        },
                      ),
                      IconButton(
                        key: const ValueKey('reader-search-button'),
                        tooltip: L10n.of(context).contextMenuSearch,
                        icon: const Icon(Icons.search),
                        onPressed: searchHandler,
                      ),
                      IconButton(
                          key: const ValueKey('reader-bookmark-button'),
                          tooltip: L10n.of(context).readingPageBookmark,
                          onPressed: () {
                            if (isReflowActive) {
                              unawaited(reflowReader?.readerAction('bookmark'));
                              return;
                            }
                            if (bookmarkExists) {
                              epubPlayerKey.currentState!.removeAnnotation(
                                epubPlayerKey.currentState!.bookmarkCfi,
                              );
                            } else {
                              epubPlayerKey.currentState!.addBookmarkHere();
                            }
                          },
                          icon: !isReflowActive && bookmarkExists
                              ? const Icon(Icons.bookmark)
                              : const Icon(Icons.bookmark_border)),
                      if (!compactToolbar)
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip:
                              L10n.of(context).readingPageCopyChapterContent,
                          onPressed: _copyChapterContent,
                        ),
                      if (compactToolbar)
                        PopupMenuButton<String>(
                          popUpAnimationStyle: AppMotion.style,
                          icon: const Icon(EvaIcons.more_vertical),
                          onSelected: (action) {
                            if (action == 'copy') {
                              _copyChapterContent();
                            } else {
                              _openBookDetails();
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                                value: 'copy',
                                child: Text(L10n.of(context)
                                    .readingPageCopyChapterContent)),
                            PopupMenuItem(
                                value: 'details',
                                child: Text(
                                    L10n.of(context).readingPageBookDetails)),
                          ],
                        )
                      else
                        IconButton(
                          tooltip: L10n.of(context).readingPageBookDetails,
                          icon: const Icon(EvaIcons.more_vertical),
                          onPressed: _openBookDetails,
                        ),
                    ],
                  ),
                const Spacer(),
                BottomSheet(
                  onClosing: () {},
                  enableDrag: false,
                  constraints: _currentPage is StyleWidget ||
                          isReflowReading ||
                          documentSettings
                      ? ReaderPopup.constraints(context)
                      : null,
                  builder: (context) => SafeArea(
                    top: false,
                    child: Container(
                      constraints: _currentPage is StyleWidget ||
                              isReflowReading ||
                              documentSettings
                          ? ReaderPopup.constraints(context)
                          : const BoxConstraints(maxWidth: 600),
                      padding: EdgeInsets.only(
                        bottom: AnxPlatform.isMobile ? 16 : 0,
                      ),
                      child: Builder(
                        builder: (BuildContext context) {
                          final content = identical(_currentPage, empty)
                              ? (isReflowActive
                                  ? reflowReader?.progressPanel() ?? empty
                                  : ProgressWidget(
                                      epubPlayerKey: epubPlayerKey))
                              : _currentPage;
                          final toolbar = Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.toc),
                                tooltip:
                                    ModuStrings.text(context, '目录', 'Contents'),
                                onPressed: tocHandler,
                              ),
                              IconButton(
                                icon: const Icon(EvaIcons.edit),
                                tooltip:
                                    ModuStrings.text(context, '笔记', 'Notes'),
                                onPressed: noteHandler,
                              ),
                              IconButton(
                                icon: Icon(documentMenu
                                    ? Icons.text_fields
                                    : Icons.color_lens),
                                tooltip: documentMenu
                                    ? ModuStrings.text(context, '文字', 'Text')
                                    : null,
                                onPressed: () {
                                  documentMenu
                                      ? _documentPanel(textOnly: true)
                                      : styleHandler();
                                },
                              ),
                              if (documentMenu)
                                IconButton(
                                  tooltip:
                                      ModuStrings.text(context, '页面', 'Page'),
                                  icon: const Icon(Icons.crop_rotate),
                                  onPressed: () =>
                                      _documentPanel(textOnly: false),
                                ),
                              IconButton(
                                tooltip: L10n.of(context).readingBrightness,
                                icon: const Icon(Icons.brightness_6_outlined),
                                onPressed: () {
                                  setState(() {
                                    _currentPage = BrightnessWidget(
                                      controller: AppBrightness.instance,
                                      onNightModeChanged: () {
                                        if (!isReflowReading ||
                                            isComparingDocument) {
                                          epubPlayerKey.currentState
                                              ?.refreshReadingTheme();
                                        }
                                      },
                                    );
                                  });
                                },
                              ),
                              if (!documentMenu)
                                IconButton(
                                  icon: const Icon(EvaIcons.headphones),
                                  onPressed: ttsHandler,
                                ),
                              if (isReflowActive)
                                IconButton(
                                  tooltip: ModuStrings.text(context, '识别 / 原页',
                                      'Recognition / original page'),
                                  icon: const Icon(
                                      Icons.document_scanner_outlined),
                                  onPressed: () =>
                                      reflowReader?.openToolsMenu(),
                                ),
                            ],
                          );
                          // Short settings fit their content; long ones scroll.
                          return content is StyleWidget ||
                                  isReflowReading ||
                                  documentSettings
                              ? ReaderQuickStylePanel(
                                  content: content, toolbar: toolbar)
                              : IntrinsicHeight(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Expanded(child: content),
                                      toolbar
                                    ],
                                  ),
                                );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final reader = Scaffold(
      resizeToAvoidBottomInset: false,
      body: ReaderCoverHero(
        tag: widget.heroTag ??
            (Prefs().openBookAnimation ? _book.coverFullPath : heroTag),
        cover: BookCover(book: _book),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height,
            width: MediaQuery.sizeOf(context).width,
            child: Scaffold(
              key: _scaffoldKey,
              resizeToAvoidBottomInset: false,
              onDrawerChanged: (open) {
                if (!mounted) {
                  return;
                }
                _readerDrawerOpen = open;
                _updatePageKeys();
                if (!open) _requestReaderFocus();
              },
              drawer: PointerInterceptor(
                child: Drawer(
                  width: math.min(
                    MediaQuery.sizeOf(context).width * 0.8,
                    420,
                  ),
                  child: SafeArea(
                    child: TocWidget(
                      epubPlayerKey: epubPlayerKey,
                      hideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
                      closeDrawer: () {
                        _scaffoldKey.currentState?.closeDrawer();
                      },
                    ),
                  ),
                ),
              ),
              body: Stack(
                children: [
                  AxisFlex(
                    axis: Prefs().aiPanelPosition == AiPanelPositionEnum.right
                        ? Axis.horizontal
                        : Axis.vertical,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: MouseRegion(
                          onHover: (PointerHoverEvent detail) {
                            if (!Prefs().showMenuOnHover) {
                              return;
                            }
                            var y = detail.position.dy;
                            if (y < 30 ||
                                y > MediaQuery.sizeOf(context).height - 30) {
                              showOrHideAppBarAndBottomBar(true);
                            }
                          },
                          child: Focus(
                            focusNode: _readerFocusNode,
                            onKeyEvent: _handleReaderKeyEvent,
                            child: Stack(
                              children: [
                                DocumentComparisonView(
                                  compare: isComparingDocument,
                                  onOriginalInteraction: () =>
                                      _activateDocumentPane(false),
                                  onReflowInteraction: () =>
                                      _activateDocumentPane(true),
                                  original: Stack(children: [
                                    FocusScope(
                                      node: _readerWebViewFocusScope,
                                      child: EpubPlayer(
                                        key: epubPlayerKey,
                                        book: _book,
                                        cfi: widget.cfi,
                                        showOrHideAppBarAndBottomBar:
                                            (bool show) {
                                          if (show) {
                                            _activateDocumentPane(false);
                                          }
                                          showOrHideAppBarAndBottomBar(show);
                                        },
                                        onLoadEnd: onLoadEnd,
                                        initialThemes: widget.initialThemes,
                                        updateParent: updateState,
                                      ),
                                    ),
                                    if (documentPlayer
                                                ?.supportsDocumentImages ==
                                            true &&
                                        (!isReflowReading ||
                                            isComparingDocument) &&
                                        bottomBarOffstage &&
                                        _aiChat == null)
                                      Positioned.fill(
                                        child: PdfZoomToolbar(
                                          zoom: documentPlayer!.pdfZoom,
                                          change:
                                              documentPlayer.zoomPdfReadingView,
                                          boxZoom: AnxPlatform.isDesktop
                                              ? documentPlayer.setPdfBoxZoom
                                              : null,
                                        ),
                                      ),
                                    if (AnxPlatform.isMobile &&
                                        _quickMarkEnabled)
                                      Positioned(
                                          top: 8,
                                          right: 12,
                                          child: PointerInterceptor(
                                              child: SafeArea(
                                                  child: QuickMarkToggle(
                                                      enabled: true,
                                                      showExit: true,
                                                      showMenu: Prefs()
                                                          .quickMarkShowMenu,
                                                      onToggleMenu:
                                                          _toggleQuickMarkMenu,
                                                      onPressed: _changingQuickMark
                                                          ? null
                                                          : _toggleQuickMark)))),
                                  ]),
                                  reflow: isReflowReading &&
                                          documentPlayer != null
                                      ? PointerInterceptor(
                                          child: Stack(children: [
                                          Positioned.fill(
                                              child: _buildDocumentReflow()),
                                          if (bottomBarOffstage &&
                                              _aiChat == null)
                                            Positioned.fill(
                                                child: TtsQuickToolbar(
                                              floating: true,
                                              stateListenable:
                                                  TtsHandler().ttsStateNotifier,
                                              onReturnToPosition:
                                                  _returnToNarration,
                                              onReadHere: _readAloudFromHere,
                                              onPrevious: () => _moveNarration(
                                                  forward: false),
                                              onNext: () =>
                                                  _moveNarration(forward: true),
                                              onPlay: audioHandler.play,
                                              onPause: audioHandler.pause,
                                              onStop: audioHandler.stop,
                                              onOpenSettings:
                                                  _openNarrationSettings,
                                            )),
                                        ]))
                                      : null,
                                ),
                                if (_isResizingAiChat)
                                  SizedBox.expand(
                                    child: Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surface
                                          .withAlpha(1),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_aiChat != null)
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragStart: Prefs().aiPanelPosition ==
                                  AiPanelPositionEnum.right
                              ? (details) {
                                  _beginAiChatResize(details.globalPosition.dx);
                                }
                              : null,
                          onHorizontalDragUpdate: Prefs().aiPanelPosition ==
                                  AiPanelPositionEnum.right
                              ? (details) {
                                  _applyAiChatResizeDelta(
                                    details.delta.dx,
                                    context,
                                  );
                                }
                              : null,
                          onHorizontalDragEnd: Prefs().aiPanelPosition ==
                                  AiPanelPositionEnum.right
                              ? (_) {
                                  _endAiChatResize();
                                }
                              : null,
                          onHorizontalDragCancel: Prefs().aiPanelPosition ==
                                  AiPanelPositionEnum.right
                              ? () {
                                  _endAiChatResize();
                                }
                              : null,
                          onVerticalDragStart: Prefs().aiPanelPosition ==
                                  AiPanelPositionEnum.bottom
                              ? (details) {
                                  _beginAiChatResizeVertical(
                                      details.globalPosition.dy);
                                }
                              : null,
                          onVerticalDragUpdate: Prefs().aiPanelPosition ==
                                  AiPanelPositionEnum.bottom
                              ? (details) {
                                  _applyAiChatResizeDeltaVertical(
                                    details.delta.dy,
                                    context,
                                  );
                                }
                              : null,
                          onVerticalDragEnd: Prefs().aiPanelPosition ==
                                  AiPanelPositionEnum.bottom
                              ? (_) {
                                  _endAiChatResize();
                                }
                              : null,
                          onVerticalDragCancel: Prefs().aiPanelPosition ==
                                  AiPanelPositionEnum.bottom
                              ? () {
                                  _endAiChatResize();
                                }
                              : null,
                          child: MouseRegion(
                            cursor: Prefs().aiPanelPosition ==
                                    AiPanelPositionEnum.right
                                ? SystemMouseCursors.resizeColumn
                                : SystemMouseCursors.resizeRow,
                            child: Prefs().aiPanelPosition ==
                                    AiPanelPositionEnum.right
                                ? VerticalDivider(
                                    width: 2,
                                    thickness: 1,
                                  )
                                : Divider(
                                    height: 2,
                                    thickness: 1,
                                  ),
                          ),
                        ),
                      if (_aiChat != null)
                        SizedBox(
                          key: const ValueKey('ai-chat-panel'),
                          width: Prefs().aiPanelPosition ==
                                  AiPanelPositionEnum.right
                              ? _aiChatWidth
                              : null,
                          height: Prefs().aiPanelPosition ==
                                  AiPanelPositionEnum.bottom
                              ? _aiChatHeight
                              : null,
                          child: _aiChat,
                        )
                    ],
                  ),
                  controller,
                  // Paint controls above the book without changing WebView
                  // dimensions, pagination or reader margins.
                  if (!documentMenu &&
                      !isReflowReading &&
                      bottomBarOffstage &&
                      _aiChat == null)
                    Positioned.fill(
                      child: TtsQuickToolbar(
                        floating: true,
                        stateListenable: TtsHandler().ttsStateNotifier,
                        onReturnToPosition: _returnToNarration,
                        onReadHere: _readAloudFromHere,
                        onPrevious: () => _moveNarration(forward: false),
                        onNext: () => _moveNarration(forward: true),
                        onPlay: audioHandler.play,
                        onPause: audioHandler.pause,
                        onStop: audioHandler.stop,
                        onOpenSettings: _openNarrationSettings,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return BookImportDropTarget(child: reader);
  }
}
