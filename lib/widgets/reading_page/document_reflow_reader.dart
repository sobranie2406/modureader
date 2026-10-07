import 'package:anx_reader/utils/app_motion.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/service/book_player/reader_word_selection.dart';
import 'package:anx_reader/page/settings_page/ocr_model.dart';
import 'package:anx_reader/service/ocr/document_reflow_store.dart';
import 'package:anx_reader/service/ocr/document_text_style.dart';
import 'package:anx_reader/service/ocr/local_ocr_service.dart';
import 'package:anx_reader/service/ocr/ocr_model_store.dart';
import 'package:anx_reader/service/ocr/ocr_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'document_text_style_dialog.dart';

typedef ReflowSelection = Future<void> Function(DocumentReflowAnchor anchor,
    String text, String contextText, Rect globalRect, List<int> annotationIds);

/// A reading surface in the reader's body, not a dialog or another book.
/// The source WebView stays mounted underneath to retain original-page state.
class DocumentReflowReader extends StatefulWidget {
  const DocumentReflowReader(
      {super.key,
      required this.store,
      required this.info,
      required this.extractText,
      required this.render,
      required this.cancelRender,
      required this.onClose,
      required this.onPageChanged,
      required this.onSelection,
      required this.clearMenu,
      this.selectionInvalidated,
      required this.loadNotes,
      required this.initialStyle,
      required this.saveStyle,
      this.forceOcr = false,
      this.anchor,
      this.modelStore,
      this.recognize});
  final DocumentReflowStore store;
  final Future<Map<String, dynamic>> Function(int?) info;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) extractText,
      render;
  final VoidCallback cancelRender, onClose, clearMenu;
  final VoidCallback? selectionInvalidated;
  final Future<void> Function(int) onPageChanged;
  final ReflowSelection onSelection;
  final Future<List<BookNote>> Function() loadNotes;
  final DocumentTextStyle initialStyle;
  final Future<void> Function(DocumentTextStyle) saveStyle;
  final bool forceOcr;
  final DocumentReflowAnchor? anchor;
  final OcrModelStore? modelStore;
  final Future<String> Function(
      Uint8List, OcrCancellation, void Function(int, int))? recognize;
  @override
  State<DocumentReflowReader> createState() => DocumentReflowReaderState();
}

class DocumentReflowReaderState extends State<DocumentReflowReader> {
  final _controller = _ReflowTextController();
  final _scroll = ScrollController();
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
  late bool _forceOcr = widget.anchor?.ocr ?? widget.forceOcr;
  DocumentReflowPage? _page;
  int _total = 0, _generation = 0;
  int? _requestedPage;
  Future<void>? _pendingLoad;
  bool _busy = false, _needsModel = false;
  String? _error, _shownSelection;
  TextSelection _observedSelection = const TextSelection.collapsed(offset: -1);
  Timer? _selectionTimer;
  Timer? _mouseLongPressTimer;
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
    _controller.addListener(_selectionChanged);
    unawaited(_load(widget.anchor?.page, anchor: widget.anchor));
  }

  @override
  void dispose() {
    _generation++;
    _selectionTimer?.cancel();
    _mouseLongPressTimer?.cancel();
    _cancel?.cancel();
    widget.cancelRender();
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
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
    final selection = _controller.selection;
    if (selection == _observedSelection) return;
    _observedSelection = selection;
    _selectionEpoch++;
    _shownSelection = null;
    if (_selectionSession &&
        !(_pointerOrigin != null && _pointerKind == PointerDeviceKind.mouse)) {
      _queueSelection();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          selection != _controller.selection ||
          _shownSelection != null) {
        return;
      }
      (widget.selectionInvalidated ?? widget.clearMenu)();
    });
  }

  void clearSelection() {
    _resetSelectionGesture();
    _editable?.hideToolbar();
    _shownSelection = null;
    _controller.selection = TextSelection.collapsed(
        offset: _controller.selection.extentOffset
            .clamp(0, _controller.text.length));
  }

  Future<void> navigate(DocumentReflowAnchor anchor) async {
    if (_busy) {
      _cancel?.cancel();
      widget.cancelRender();
    }
    _forceOcr = anchor.ocr;
    await _load(anchor.page, anchor: anchor);
  }

  Future<void> setMode(bool ocr) async {
    if (_busy) return;
    setState(() => _forceOcr = ocr);
    await _load(_page?.page);
  }

  Future<void> turn(int direction) async {
    if (_busy || _page == null) return;
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
    final target = _page!.page + direction;
    if (target >= 0 && target < _total) await _load(target);
  }

  void cancelLoading() {
    _cancel?.cancel();
    widget.cancelRender();
  }

  Future<void> turnOriginalPage(int direction) async {
    if (_busy || _page == null) return;
    final target = _page!.page + direction;
    if (target >= 0 && target < _total) await _load(target);
  }

  // Selection-toolbar narration reads the selected reflow text, never the
  // hidden original-page DOM. Empty next/previous ends that excerpt cleanly.
  String speechText(String? value) {
    final anchor = value == null ? null : DocumentReflowAnchor.parse(value);
    if (_page == null) return '';
    return anchor != null && anchor.matches(_page!)
        ? _page!.text.substring(anchor.start, anchor.end)
        : _page!.text;
  }

  Future<void> _load(int? target, {DocumentReflowAnchor? anchor}) async {
    while (_pendingLoad != null) {
      cancelLoading();
      await _pendingLoad;
    }
    if (!mounted) return;
    final pending = _performLoad(target, anchor: anchor);
    _pendingLoad = pending;
    try {
      await pending;
    } finally {
      if (identical(_pendingLoad, pending)) _pendingLoad = null;
    }
  }

  Future<void> _performLoad(int? target, {DocumentReflowAnchor? anchor}) async {
    _resetSelectionGesture();
    final generation = ++_generation, cancel = OcrCancellation();
    _cancel?.cancel();
    _cancel = cancel;
    widget.clearMenu();
    setState(() {
      _busy = true;
      _error = null;
      _needsModel = false;
      _progress = null;
    });
    final model = widget.modelStore ??
        OcrModelStore(model: OcrModels.byId(Prefs().ocrModelId));
    bool active() => mounted && generation == _generation && !cancel.cancelled;
    void check() {
      cancel.check();
      if (!active()) throw StateError('Reader changed');
    }

    try {
      final info = await widget.info(target);
      check();
      final page = (info['page'] as num).toInt(),
          total = (info['total'] as num).toInt();
      _requestedPage = page;
      if (page < 0 ||
          page >= total ||
          (target != null && page != target) ||
          info['imageOnly'] == false) {
        throw const FormatException('Invalid image page');
      }
      // Bounds are original-page coordinates resolved by the same crop logic
      // as the PDF/image reader. No region picker for either reflow command.
      final sourceRegion = info['region'] as Map? ??
          const {'x': 0, 'y': 0, 'width': 1, 'height': 1};
      final region = <String, double>{};
      for (final name in ['x', 'y', 'width', 'height']) {
        final value = sourceRegion[name];
        if (value is! num || !value.isFinite) {
          throw const FormatException('Invalid reflow bounds');
        }
        region[name] = value.toDouble();
      }
      if (region['x']! < 0 ||
          region['y']! < 0 ||
          region['width']! <= 0 ||
          region['height']! <= 0 ||
          region['x']! + region['width']! > 1 + 1e-9 ||
          region['y']! + region['height']! > 1 + 1e-9) {
        throw const FormatException('Invalid reflow bounds');
      }
      final hideWatermarks = info['hideWatermarks'] == true;
      final profile =
          'reflow-v2:${_forceOcr ? 'ocr' : 'text'}:${model.model.id}:${model.model.revision}:${jsonEncode(region)}:$hideWatermarks';
      var result = anchor == null
          ? await widget.store.read(page, profile)
          : await widget.store.readAnchor(anchor);
      check();
      if (result == null) {
        var text = '', usedOcr = false;
        final request = <String, dynamic>{
          'page': page,
          'region': region,
          'hideWatermarks': hideWatermarks,
        };
        if (!_forceOcr) {
          text = (await widget.extractText(request))['text']?.toString() ?? '';
          check();
        }
        if (text.trim().isEmpty) {
          if (!await model.available()) {
            check();
            setState(() => _needsModel = true);
            return;
          }
          check();
          usedOcr = true;
          final image = await widget.render(
              {...request, 'width': 2048, 'height': 2048, 'rotation': 0});
          check();
          const prefix = 'data:image/png;base64,';
          final data = image['dataUrl'];
          if (data is! String ||
              !data.startsWith(prefix) ||
              data.length > 16000000) {
            throw const FormatException('Invalid page image');
          }
          void progress(int n, int total) {
            if (active()) {
              setState(() => _progress = total > 0 ? n / total : null);
            }
          }

          final bytes = base64Decode(data.substring(prefix.length));
          text = await (widget.recognize?.call(bytes, cancel, progress) ??
              LocalOcrService()
                  .recognize(bytes, model, cancel, progress: progress));
          check();
        }
        if (text.trim().isEmpty || text.length > 1000000) {
          throw const FormatException('No usable text');
        }
        result = DocumentReflowPage(page: page, ocr: usedOcr, rawText: text);
        await widget.store.save(result, profile);
        check();
      }
      final notes = await widget.loadNotes();
      check();
      // Commit page and reader progress together only after successful loading.
      await widget.onPageChanged(page);
      check();
      _page = result;
      _total = total;
      _notes = notes;
      _controller.text = result.text;
      _controller.setMarks(result, notes);
      _shownSelection = null;
      setState(() {
        if (anchor != null && !anchor.matches(result!)) {
          _error = t('已返回原书页码，但重排文字版本不同，未强行定位标注。',
              'Returned to the source page. Text has changed; the annotation was not applied to a different passage.');
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!active()) return;
        if (_scroll.hasClients) _scroll.jumpTo(0);
        if (anchor != null && anchor.matches(result!)) {
          _controller.selection =
              TextSelection(baseOffset: anchor.start, extentOffset: anchor.end);
          _textState?.bringIntoView(TextPosition(offset: anchor.start));
        }
      });
    } catch (_) {
      if (active()) {
        setState(() => _error = t('本页重排失败，已保留原阅读位置。请重试或返回原页。',
            'Could not reflow this page. Your position is unchanged. Retry or return to the original.'));
      }
    } finally {
      if (widget.modelStore == null) model.close();
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _progress = null;
        });
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

  Future<void> _styleSettings() async {
    widget.clearMenu();
    clearSelection();
    final value = await showDialog<DocumentTextStyle>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (_) =>
            DocumentTextStyleDialog(initial: _style, save: widget.saveStyle));
    if (mounted && value != null) setState(() => _style = value);
  }

  void _resetSelectionGesture() {
    _selectionTimer?.cancel();
    _mouseLongPressTimer?.cancel();
    _selectionEpoch++;
    _expandingEpoch = null;
    _selectionSession = false;
    _expandInitialSelection = false;
    _pointerOrigin = null;
  }

  void _selectionPointerDown(PointerDownEvent event) {
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
            _controller.value.copyWith(
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
    _pointerOrigin = null;
    _queueSelection();
  }

  void _queueSelection() {
    _selectionTimer?.cancel();
    _selectionTimer = Timer(const Duration(milliseconds: 80), () {
      unawaited(_settleSelection());
    });
  }

  Future<void> _settleSelection() async {
    final selection = _controller.selection, page = _page;
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
      final text = _controller.text;
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
          selection != _controller.selection) return;
      // Never shrink a native word/drag range into a smaller token.
      if (bounds != null &&
          bounds[0] <= selection.start &&
          bounds[1] >= selection.end &&
          bounds[0] < bounds[1]) {
        final expanded = selection.baseOffset <= selection.extentOffset
            ? TextSelection(baseOffset: bounds[0], extentOffset: bounds[1])
            : TextSelection(baseOffset: bounds[1], extentOffset: bounds[0]);
        state.userUpdateTextEditingValue(
            _controller.value.copyWith(selection: expanded),
            _pointerKind == PointerDeviceKind.mouse
                ? SelectionChangedCause.tap
                : SelectionChangedCause.longPress);
        _selectionTimer?.cancel();
      }
    }
    // Wait for the expanded range's layout before reading global anchors.
    final settled = _controller.selection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _generation ||
          settled != _controller.selection) return;
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
    final selection = _controller.selection, page = _page;
    if (page == null || !selection.isValid || selection.isCollapsed) {
      return;
    }
    final anchor = DocumentReflowAnchor(
        page.page, page.ocr, page.revision, selection.start, selection.end);
    final id = anchor.encode();
    final primary = state.contextMenuAnchors.primaryAnchor;
    final secondary = state.contextMenuAnchors.secondaryAnchor ?? primary;
    if (_shownSelection != id) {
      _shownSelection = id;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted ||
            _controller.selection != selection ||
            _page != page ||
            _shownSelection != id) {
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
        final contextText = page.text.substring(
            (selection.start - 800).clamp(0, page.text.length),
            (selection.end + 800).clamp(0, page.text.length));
        await widget.onSelection(anchor, selection.textInside(page.text),
            contextText, Rect.fromPoints(primary, secondary).inflate(4), ids);
      });
    }
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    Color parse(String value, Color fallback) =>
        Color(int.tryParse(value.replaceFirst('#', ''), radix: 16) ??
            fallback.toARGB32());
    final theme = Prefs().readTheme;
    final background = Prefs().eInkMode
        ? Colors.white
        : parse(theme.backgroundColor, Theme.of(context).colorScheme.surface);
    final foreground = Prefs().eInkMode
        ? Colors.black
        : parse(theme.textColor, Theme.of(context).colorScheme.onSurface);
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) widget.onClose();
        },
        child: Material(
            color: background,
            child: SafeArea(
                child: Column(children: [
              Row(children: [
                TextButton.icon(
                    key: const ValueKey('reflow-original'),
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.arrow_back),
                    label: Text(t('原页', 'Original'))),
                Expanded(
                    child: DropdownButtonHideUnderline(
                        child: DropdownButton<bool>(
                            key: const ValueKey('reflow-mode'),
                            value: _forceOcr,
                            isExpanded: true,
                            items: [
                              DropdownMenuItem(
                                  value: false,
                                  child: Text(t('文字重排', 'Reflow text'))),
                              DropdownMenuItem(
                                  value: true,
                                  child: Text(t('OCR 重排', 'OCR reflow')))
                            ],
                            onChanged: _busy
                                ? null
                                : (value) {
                                    if (value != null && value != _forceOcr) {
                                      setState(() => _forceOcr = value);
                                      unawaited(_load(_page?.page));
                                    }
                                  }))),
                IconButton(
                    tooltip: t('文字样式', 'Text style'),
                    onPressed: _styleSettings,
                    icon: const Icon(Icons.settings)),
              ]),
              if (_busy)
                EinkStaticIndicator(
                    child: LinearProgressIndicator(value: _progress)),
              Expanded(
                  child: _page == null
                      ? Center(
                          child: _busy
                              ? const EinkStaticIndicator(
                                  child: CircularProgressIndicator())
                              : Text(t('等待本页文字', 'Waiting for page text'),
                                  style: TextStyle(color: foreground)))
                      : SingleChildScrollView(
                          controller: _scroll,
                          padding: EdgeInsets.symmetric(
                              horizontal: _style.margin, vertical: 16),
                          child: Listener(
                              onPointerDown: _selectionPointerDown,
                              onPointerMove: _selectionPointerMove,
                              onPointerUp: _selectionPointerUp,
                              onPointerCancel: (_) => _resetSelectionGesture(),
                              child: KeyedSubtree(
                                  key: _textFieldKey,
                                  child: TextField(
                                    key: const ValueKey('reflow-text'),
                                    controller: _controller,
                                    focusNode: _focus,
                                    readOnly: true,
                                    maxLines: null,
                                    showCursor: false,
                                    enableSuggestions: false,
                                    style: _style.textStyle
                                        .copyWith(color: foreground),
                                    textAlign: _style.alignment,
                                    decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        isCollapsed: true,
                                        contentPadding: EdgeInsets.zero),
                                    contextMenuBuilder: _selectionMenu,
                                    onTapOutside: (_) {},
                                  ))))),
              if (_needsModel || _error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                        _error ??
                            t('本页需要 OCR，请先在模型设置中下载模型。识别在本机完成。',
                                'This page needs OCR. Download a model in settings; recognition runs locally.'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: foreground))),
              Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  children: [
                    IconButton(
                        key: const ValueKey('reflow-previous'),
                        tooltip: t('上一原页', 'Previous original page'),
                        onPressed: !_busy && _page != null && _page!.page > 0
                            ? () => _load(_page!.page - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left)),
                    Text('${(_page?.page ?? 0) + 1} / $_total',
                        style: TextStyle(color: foreground)),
                    IconButton(
                        key: const ValueKey('reflow-next'),
                        tooltip: t('下一原页', 'Next original page'),
                        onPressed:
                            !_busy && _page != null && _page!.page + 1 < _total
                                ? () => _load(_page!.page + 1)
                                : null,
                        icon: const Icon(Icons.chevron_right)),
                    if (_busy)
                      TextButton(
                          onPressed: () {
                            _cancel?.cancel();
                            widget.cancelRender();
                          },
                          child: Text(t('停止', 'Stop'))),
                    if (_needsModel && !_busy)
                      TextButton(
                          onPressed: _settings,
                          child: Text(t('OCR 模型设置', 'OCR model settings'))),
                    if (!_busy && (_error != null || _page == null))
                      TextButton(
                          onPressed: () => _load(_requestedPage ??
                              _page?.page ??
                              widget.anchor?.page),
                          child: Text(t('重试', 'Retry'))),
                  ]),
            ]))));
  }
}

class _ReflowTextController extends TextEditingController {
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
      for (final mark in marks) ...[mark.$1.start, mark.$1.end]
    }.toList()
      ..sort();
    return TextSpan(style: style, children: [
      for (var i = 0; i < edges.length - 1; i++)
        TextSpan(
            text: text.substring(edges[i], edges[i + 1]),
            style: _styleAt(edges[i], marks))
    ]);
  }

  TextStyle? _styleAt(
      int offset, List<(DocumentReflowAnchor, BookNote)> marks) {
    Color? background, underline;
    for (final (anchor, note) in marks) {
      if (offset < anchor.start || offset >= anchor.end) continue;
      final color = Color(
          int.tryParse('ff${note.color.replaceFirst('#', '')}', radix: 16) ??
              0xffffff00);
      if (note.type == 'highlight') background = color.withValues(alpha: .35);
      if (note.type == 'underline') underline = color;
    }
    return TextStyle(
        backgroundColor: background,
        decoration: underline == null ? null : TextDecoration.underline,
        decorationColor: underline);
  }
}
