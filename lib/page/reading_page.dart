import 'dart:async';
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
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/ai/prompt_generate.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/service/ai/reading_skill_prompt_store.dart';
import 'package:anx_reader/service/reader_focus.dart';
import 'package:anx_reader/service/reader_keyboard.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/utils/ui/status_bar.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:anx_reader/widgets/ai/ai_stream.dart';
import 'package:anx_reader/widgets/reading_page/notes_widget.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_lookup.dart';
import 'package:anx_reader/widgets/reading_page/quick_mark_toggle.dart';
import 'package:anx_reader/models/reading_time.dart';
import 'package:anx_reader/widgets/reading_page/progress_widget.dart';
import 'package:anx_reader/widgets/reading_page/tts_fab.dart';
import 'package:anx_reader/widgets/reading_page/tts_widget.dart';
import 'package:anx_reader/widgets/reading_page/translation_widget.dart';
import 'package:anx_reader/widgets/reading_page/translation_toolbar_action.dart';
import 'package:anx_reader/widgets/reading_page/book_search.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:anx_reader/widgets/reading_page/selection_search_browser.dart';
import 'package:anx_reader/widgets/context_menu/translation_menu.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:anx_reader/widgets/reading_page/toc_widget.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'package:flutter/foundation.dart'
// show debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:icons_plus/icons_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
    final zh = Localizations.localeOf(context).languageCode == 'zh';
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
        AnxToast.show(zh
            ? '无法切换标记菜单，请重试。'
            : 'Could not switch the marking menu. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _changingQuickMark = false);
    }
  }

  Future<void> _toggleQuickMark() async {
    if (!AnxPlatform.isMobile || _changingQuickMark) return;
    setState(() => _changingQuickMark = true);
    final requested = !_quickMarkEnabled;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    try {
      final enabled =
          await epubPlayerKey.currentState?.setQuickMarkEnabled(requested) ??
              false;
      if (!mounted) return;
      setState(() => _quickMarkEnabled = enabled);
      if (requested && !enabled) {
        AnxToast.show(zh
            ? '请等待正文载入。快速标记暂不支持 PDF 和固定版式书籍。'
            : 'Wait for the book to load. PDF and fixed-layout books are not supported.');
      } else if (enabled) {
        showOrHideAppBarAndBottomBar(false);
        AnxToast.show(zh
            ? '直接划过文字，松手即高亮；退出后恢复滑动翻页。'
            : 'Swipe across text to highlight. Exit to resume swipe navigation.');
      }
    } catch (_) {
      AnxToast.show(
          zh ? '无法切换快速标记，请重试。' : 'Could not switch quick mark. Please retry.');
    } finally {
      if (mounted) setState(() => _changingQuickMark = false);
    }
  }

  late final FocusNode _readerFocusNode;
  final _readerWebViewFocusScope =
      FocusScopeNode(debugLabel: 'book_webview_focus_scope');
  // late final VolumeKeyBoard _volumeKeyBoard;
  // bool _volumeKeyListenerAttached = false;

  @override
  void initState() {
    _readerFocusNode = FocusNode(debugLabel: 'reading_page_focus');

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
    // _volumeKeyBoard = VolumeKeyBoard.instance;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _requestReaderFocus();
        // _attachVolumeKeyListener();
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
    Prefs().removeListener(_updateReadingSync);
    readerRouteObserver.unsubscribe(this);
    _readingSync.dispose();
    if (AnxPlatform.isDesktop) unawaited(_fullscreen.close());
    Sync().syncData(SyncDirection.upload, ref, trigger: SyncTrigger.auto);
    _readTimeWatch.stop();
    _awakeTimer?.cancel();
    WakelockPlus.disable();
    showStatusBar();
    WidgetsBinding.instance.removeObserver(this);
    readingTimeDao.insertReadingTime(
      ReadingTime(
        bookId: _book.id,
        readingTime: _readTimeWatch.elapsed.inSeconds,
      ),
      startedAt: _sessionStart,
    );
    _sessionStart = null;
    audioHandler.stop();
    // if (_volumeKeyListenerAttached) {
    //   unawaited(_volumeKeyBoard.removeListener());
    // }
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
    if (!mounted || !AnxPlatform.isDesktop || !bottomBarOffstage) return;
    _focusReaderSurface();
  }

  void _focusReaderSurface() {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (AnxPlatform.isWindows || AnxPlatform.isLinux) {
      // Texture-backed plugins receive keys through their own child Focus.
      // Restore that remembered child, never the surrounding paging handler.
      _readerWebViewFocusScope.requestFocus();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    unawaited(restoreNativeReaderFocus(
        () async => await epubPlayerKey.currentState?.requestNativeFocus()));
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

  // Future<void> _attachVolumeKeyListener() async {
  //   if (defaultTargetPlatform != TargetPlatform.iOS ||
  //       _volumeKeyListenerAttached) {
  //     return;
  //   }

  //   try {
  //     await _volumeKeyBoard.addListener(_handleVolumeKeyEvent);
  //     _volumeKeyListenerAttached = true;
  //   } catch (error) {
  //     debugPrint('Failed to attach volume key listener: $error');
  //   }
  // }

  // void _handleVolumeKeyEvent(VolumeKey key) {
  //   if (!Prefs().volumeKeyTurnPage || !_readerFocusNode.hasFocus) {
  //     return;
  //   }

  //   if (key == VolumeKey.up) {
  //     epubPlayerKey.currentState?.prevPage();
  //   } else if (key == VolumeKey.down) {
  //     epubPlayerKey.currentState?.nextPage();
  //   }
  // }

  KeyEventResult _handleReaderKeyEvent(FocusNode node, KeyEvent event) {
    if (_searchDialogOpen || ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    if (!readerOwnsPageKeys(_readerFocusNode, _readerWebViewFocusScope,
        windows: AnxPlatform.isWindows)) {
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final logicalKey = event.logicalKey;

    final keyboard = HardwareKeyboard.instance;
    final direction = readerPageKeyDirection(event,
        control: keyboard.isControlPressed,
        shift: keyboard.isShiftPressed,
        alt: keyboard.isAltPressed,
        meta: keyboard.isMetaPressed,
        ctrlBrackets: Prefs().keyboardShortcutTurnPage);
    if (direction != 0) {
      if (AnxPlatform.isDesktop) {
        // A bubbled Windows key must use the same DOM editor/selection guards
        // as a key received directly by the native WebView.
        epubPlayerKey.currentState?.turnPageFromKeyboard(direction);
      } else if (direction > 0) {
        epubPlayerKey.currentState?.nextPage();
      } else {
        epubPlayerKey.currentState?.prevPage();
      }
      return KeyEventResult.handled;
    }

    // Other shortcuts belong to the child WebView/control, not its ancestor.
    if (!_readerFocusNode.hasPrimaryFocus) return KeyEventResult.ignored;

    if (logicalKey == LogicalKeyboardKey.enter) {
      showOrHideAppBarAndBottomBar(true);
      return KeyEventResult.handled;
    }

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final reader = epubPlayerKey.currentState;
    if (reader != null) {
      unawaited(reader.setTtsBackground(state != AppLifecycleState.resumed));
    }
    _updateReadingSync();
    switch (state) {
      case AppLifecycleState.resumed:
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
    WakelockPlus.enable();
    _awakeTimer = Timer.periodic(Duration(minutes: minutes), (timer) {
      WakelockPlus.disable();
      _awakeTimer?.cancel();
      _awakeTimer = null;
    });
  }

  void resetAwakeTimer() {
    setAwakeTimer(Prefs().awakeTime);
  }

  void showBottomBar() {
    setState(() {
      // The bars are painted over the reader in the body Stack. Changing the
      // system UI mode here changes WebView viewport metrics and repaginates
      // the book even though the reader itself has not moved.
      bottomBarOffstage = false;
      _releaseReaderFocus();
    });
  }

  void hideBottomBar() {
    setState(() {
      _currentPage = empty;
      bottomBarOffstage = true;
      _requestReaderFocus();
    });
  }

  void showOrHideAppBarAndBottomBar(bool show) {
    if (show) {
      showBottomBar();
    } else {
      hideBottomBar();
    }
  }

  Future<void> tocHandler() async {
    _readerDrawerOpen = true;
    hideBottomBar();
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> searchHandler() async {
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

  void progressHandler() {
    setState(() {
      _currentPage = ProgressWidget(
        epubPlayerKey: epubPlayerKey,
        showOrHideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
      );
    });
  }

  Future<void> styleHandler(StateSetter modalSetState) async {
    List<ReadTheme> themes = await themeDao.selectThemes();
    setState(() {
      _currentPage = StyleWidget(
        themes: themes,
        epubPlayerKey: epubPlayerKey,
        setCurrentPage: (Widget page) {
          modalSetState(() {
            _currentPage = page;
          });
        },
        hideAppBarAndBottomBar: showOrHideAppBarAndBottomBar,
      );
    });
  }

  Future<void> ttsHandler() async {
    setState(() {
      _currentPage = TtsWidget(
        epubPlayerKey: epubPlayerKey,
      );
    });
  }

  void translationHandler() {
    setState(() {
      _currentPage = TranslationWidget(
        bookId: _book.id,
        epubPlayerKey: epubPlayerKey,
      );
    });
  }

  Future<void> _copyChapterContent() async {
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
        CupertinoPageRoute(
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

  Future<void> showSelectionSearch(String content) async {
    showOrHideAppBarAndBottomBar(false);
    try {
      await showSelectionSearchBrowser(context, text: content);
    } finally {
      _restoreReaderFocusAfterPanel();
    }
  }

  double _aiChatMaxWidth(BuildContext context) {
    final totalWidth = MediaQuery.of(context).size.width;
    final maxByPercentage = totalWidth * 0.65;
    final maxByRemaining = totalWidth - 320;
    final maxWidth = math.min(maxByPercentage, maxByRemaining);
    return math.max(_aiChatMinWidth, maxWidth);
  }

  double _aiChatMaxHeight(BuildContext context) {
    final totalHeight = MediaQuery.of(context).size.height;
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
      final prompt = generatePromptSummaryThePreviousContent(previousContent);
      SmartDialog.show(
        builder: (context) => AlertDialog(
          title: Text(L10n.of(context).readingPageSummaryPreviousContent),
          content: AiStream(
            prompt: prompt,
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
            initialMessage: null,
            sendImmediate: false,
            quickPromptChips: _getAiQuickPromptChips(),
            trailing: _buildAiChatTrailing(context),
          ),
        ),
      ],
    );
  }

  List<AiQuickPromptChip> _getAiQuickPromptChips() {
    return [
      ...readAnySkills
          .where((skill) => Prefs().isReadAnySkillEnabled(skill.id))
          .map(
            (skill) => AiQuickPromptChip(
              icon: _readAnySkillIcon(skill.id),
              label: skill.name,
              prompt: ReadingSkillPromptStore.promptFor(skill),
              skillId: skill.id,
            ),
          ),
      // User custom prompts (enabled only)
      ...Prefs()
          .userPrompts
          .where((p) => p.enabled)
          .map((userPrompt) => AiQuickPromptChip(
                icon: Icons.person_outline,
                label: userPrompt.name,
                prompt: userPrompt.content,
              )),
    ];
  }

  IconData _readAnySkillIcon(String skillId) {
    return switch (skillId) {
      'smart_summary' => Icons.summarize_outlined,
      'book_summary' => Icons.menu_book_rounded,
      'concept_explainer' => Icons.lightbulb_outline,
      'argument_analyzer' => Icons.account_tree_outlined,
      'character_tracker' => Icons.groups_outlined,
      'quote_collector' => Icons.format_quote_outlined,
      'reading_guide' => Icons.explore_outlined,
      'smart_translator' => Icons.translate_outlined,
      'vocabulary_helper' => Icons.spellcheck_outlined,
      'mindmap' => Icons.account_tree_outlined,
      _ => Icons.extension_outlined,
    };
  }

  Future<void> showAiChat({
    String? content,
    bool sendImmediate = false,
  }) async {
    List<AiQuickPromptChip> quickPrompts = _getAiQuickPromptChips();

    // Determine display mode
    final displayMode = Prefs().aiChatDisplayMode;
    final screenWidth = MediaQuery.of(navigatorKey.currentContext!).size.width;

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

    if (shouldShowAsPopup) {
      await showReaderPopup(navigatorKey.currentContext!,
          builder: (context) => AiChatStream(
                key: aiChatKey,
                scope: AiChatScope.reader,
                initialMessage: content,
                sendImmediate: sendImmediate,
                quickPromptChips: quickPrompts,
              ));
      _restoreReaderFocusAfterPanel();
    } else {
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
                initialMessage: content,
                sendImmediate: sendImmediate,
                quickPromptChips: quickPrompts,
                trailing: _buildAiChatTrailing(navigatorKey.currentContext!),
              ),
            ),
          ],
        );
      });
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
    final compactToolbar = MediaQuery.sizeOf(context).width < 420;
    var aiButton = IconButton(
      tooltip: L10n.of(context).aiChat,
      icon: const Icon(Icons.auto_awesome),
      onPressed: () async {
        // Determine if should show as split based on display mode
        final displayMode = Prefs().aiChatDisplayMode;
        final screenWidth = MediaQuery.of(context).size.width;

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
                    if (AnxPlatform.isMobile)
                      QuickMarkToggle(
                          enabled: _quickMarkEnabled,
                          onPressed:
                              _changingQuickMark ? null : _toggleQuickMark),
                    if (EnvVar.enableAIFeature) aiButton,
                    TranslationToolbarAction(
                      mode: epubPlayerKey.currentState?.translationMode,
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
                          if (bookmarkExists) {
                            epubPlayerKey.currentState!.removeAnnotation(
                              epubPlayerKey.currentState!.bookmarkCfi,
                            );
                          } else {
                            epubPlayerKey.currentState!.addBookmarkHere();
                          }
                        },
                        icon: bookmarkExists
                            ? const Icon(Icons.bookmark)
                            : const Icon(Icons.bookmark_border)),
                    if (!compactToolbar)
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: L10n.of(context).readingPageCopyChapterContent,
                        onPressed: _copyChapterContent,
                      ),
                    if (compactToolbar)
                      PopupMenuButton<String>(
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
                  builder: (context) => SafeArea(
                    top: false,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 600),
                      padding: EdgeInsets.only(
                        bottom: AnxPlatform.isMobile ? 16 : 0,
                      ),
                      child: StatefulBuilder(
                        builder: (BuildContext context, StateSetter setState) {
                          final hasContent = !identical(_currentPage, empty);
                          return IntrinsicHeight(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasContent)
                                  Expanded(
                                    child: _currentPage,
                                  ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.toc),
                                      onPressed: tocHandler,
                                    ),
                                    IconButton(
                                      icon: const Icon(EvaIcons.edit),
                                      onPressed: noteHandler,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.data_usage),
                                      onPressed: progressHandler,
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.color_lens),
                                      onPressed: () {
                                        styleHandler(setState);
                                      },
                                    ),
                                    IconButton(
                                      tooltip:
                                          L10n.of(context).readingBrightness,
                                      icon: const Icon(
                                          Icons.brightness_6_outlined),
                                      onPressed: () {
                                        setState(() {
                                          _currentPage = BrightnessWidget(
                                            controller: AppBrightness.instance,
                                            onNightModeChanged: () =>
                                                epubPlayerKey.currentState
                                                    ?.refreshReadingTheme(),
                                          );
                                        });
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(EvaIcons.headphones),
                                      onPressed: ttsHandler,
                                    ),
                                  ],
                                ),
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

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Hero(
        tag: widget.heroTag ??
            (Prefs().openBookAnimation ? _book.coverFullPath : heroTag),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            height: MediaQuery.of(context).size.height,
            width: MediaQuery.of(context).size.width,
            child: Scaffold(
              key: _scaffoldKey,
              resizeToAvoidBottomInset: false,
              onDrawerChanged: (open) {
                _readerDrawerOpen = open;
                if (!open) _requestReaderFocus();
              },
              drawer: PointerInterceptor(
                child: Drawer(
                  width: math.min(
                    MediaQuery.of(context).size.width * 0.8,
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
                            if (!Prefs().showMenuOnHover) return;
                            var y = detail.position.dy;
                            if (y < 30 ||
                                y > MediaQuery.of(context).size.height - 30) {
                              showOrHideAppBarAndBottomBar(true);
                            }
                          },
                          child: Focus(
                            focusNode: _readerFocusNode,
                            onKeyEvent: _handleReaderKeyEvent,
                            child: Stack(
                              children: [
                                FocusScope(
                                  node: _readerWebViewFocusScope,
                                  child: EpubPlayer(
                                    key: epubPlayerKey,
                                    book: _book,
                                    cfi: widget.cfi,
                                    showOrHideAppBarAndBottomBar:
                                        showOrHideAppBarAndBottomBar,
                                    onLoadEnd: onLoadEnd,
                                    initialThemes: widget.initialThemes,
                                    updateParent: updateState,
                                  ),
                                ),
                                if (AnxPlatform.isMobile && _quickMarkEnabled)
                                  Positioned(
                                      top: 8,
                                      right: 12,
                                      child: PointerInterceptor(
                                          child: SafeArea(
                                              child: QuickMarkToggle(
                                                  enabled: true,
                                                  showExit: true,
                                                  showMenu:
                                                      Prefs().quickMarkShowMenu,
                                                  onToggleMenu:
                                                      _toggleQuickMarkMenu,
                                                  onPressed: _changingQuickMark
                                                      ? null
                                                      : _toggleQuickMark)))),
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
                  // TTS floating action button: always in the tree when toolbar
                  // is hidden; TtsFab handles its own show/hide internally so
                  // its State (expanded flag) is never destroyed mid-session.
                  if (bottomBarOffstage)
                    const Positioned(
                      right: 16,
                      bottom: 24,
                      child: TtsFab(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
