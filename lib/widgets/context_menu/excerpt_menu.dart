import 'package:anx_reader/utils/app_motion.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/page/settings_page/selection_toolbar.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/book_share/excerpt_share_service.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:anx_reader/widgets/context_menu/annotation_color_palette.dart';
import 'package:anx_reader/widgets/context_menu/selection_action_toolbar.dart';
import 'package:anx_reader/widgets/context_menu/selection_toolbar_labels.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_lookup.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:anx_reader/widgets/reading_page/selection_search_browser.dart';

class ExcerptMenu extends StatefulWidget {
  final String annoCfi;
  final String annoContent;
  final String? contextText;
  final int? id;
  final int? bookId;
  final List<int> annotationIds;
  final ValueChanged<bool>? onDeletionVisibilityChanged;
  final BookNoteDao? dao;
  final Future<void> Function(String cfi)? removeAnnotation;
  final Function() onClose;
  final bool footnote;
  final BoxDecoration decoration;
  final Function() toggleTranslationMenu;
  final void Function({bool? show}) toggleReaderNoteMenu;
  final Future<void> Function(int noteId) openReaderNoteMenu;
  final void Function(int noteId) onNoteCreated;
  final Axis axis;
  final bool reverse;
  final ModalRoute<dynamic>? parentRoute;

  const ExcerptMenu({
    super.key,
    required this.annoCfi,
    required this.annoContent,
    this.contextText,
    this.id,
    this.bookId,
    this.annotationIds = const [],
    this.onDeletionVisibilityChanged,
    this.dao,
    this.removeAnnotation,
    required this.onClose,
    required this.footnote,
    required this.decoration,
    required this.toggleTranslationMenu,
    required this.toggleReaderNoteMenu,
    required this.openReaderNoteMenu,
    required this.onNoteCreated,
    required this.axis,
    required this.reverse,
    this.parentRoute,
  });

  @override
  ExcerptMenuState createState() => ExcerptMenuState();
}

class ExcerptMenuState extends State<ExcerptMenu> {
  bool _deleting = false;
  bool _saving = false;
  int? noteId;
  BookNote? _currentNote;
  final Map<int, BookNote> _pendingDeletion = {};
  late String annoType;
  late String annoColor;
  BookNoteDao get _dao => widget.dao ?? bookNoteDao;
  int? get _bookId =>
      widget.bookId ?? epubPlayerKey.currentState?.widget.book.id;
  bool get _hasDeletionTarget =>
      noteId != null || widget.annotationIds.isNotEmpty;

  @override
  initState() {
    super.initState();
    noteId = widget.id;
    annoType = Prefs().annotationType;
    annoColor = Prefs().annotationColor;
    _initializeExistingNote();
  }

  Future<void> _initializeExistingNote() async {
    final existingId = widget.id;
    if (existingId == null) {
      return;
    }

    try {
      final note = await _dao.selectBookNoteById(existingId);
      if (!mounted) {
        return;
      }
      setState(() {
        _currentNote = note;
        noteId = note.id;
        annoType = note.type;
        annoColor = note.color;
      });
      if (!widget.footnote &&
          note.readerNote != null &&
          note.readerNote!.isNotEmpty) {
        await widget.openReaderNoteMenu(note.id!);
      }
    } catch (_) {
      // When the note cannot be loaded we keep the defaults from Prefs.
    }
  }

  Future<BookNote?> _fetchLatestNote() async {
    final existingId = noteId ?? widget.id;
    if (existingId == null) {
      final bookId = _bookId;
      if (bookId == null) return null;
      final notes =
          await _dao.selectBookNoteByCfiAndBookId(widget.annoCfi, bookId);
      return notes.isEmpty ? null : notes.last;
    }

    try {
      return await _dao.selectBookNoteById(existingId);
    } catch (_) {
      return null;
    }
  }

  Future<BookNote> _persistNote(
      {String? color, String? type, String? content}) async {
    final existingNote = await _fetchLatestNote() ?? _currentNote;
    final now = DateTime.now();

    final candidateContent =
        content ?? existingNote?.content ?? widget.annoContent;
    final resolvedContent = candidateContent.trim().isNotEmpty
        ? candidateContent
        : (existingNote?.content ?? widget.annoContent);
    final resolvedType = type ?? existingNote?.type ?? annoType;
    final resolvedColor = color ?? existingNote?.color ?? annoColor;

    final BookNote bookNote = BookNote(
      id: existingNote?.id ?? noteId ?? widget.id,
      bookId:
          existingNote?.bookId ?? epubPlayerKey.currentState!.widget.book.id,
      content: resolvedContent,
      cfi: existingNote?.cfi ?? widget.annoCfi,
      chapter: existingNote?.chapter ??
          epubPlayerKey.currentState!.selectionChapterTitle,
      type: resolvedType,
      color: resolvedColor,
      readerNote: existingNote?.readerNote,
      createTime: existingNote?.createTime ?? now,
      updateTime: now,
    );
    if (existingNote != null) bookNote.inheritVersion(existingNote);

    final id = await _dao.save(bookNote);
    bookNote.setId(id);
    widget.onNoteCreated(id);

    if (mounted) {
      setState(() {
        _currentNote = bookNote;
        noteId = id;
        annoType = resolvedType;
        annoColor = resolvedColor;
      });
    } else {
      _currentNote = bookNote;
      noteId = id;
      annoType = resolvedType;
      annoColor = resolvedColor;
    }

    return bookNote;
  }

  Future<List<BookNote>> _deletionTargets() async {
    // Keep removed DB rows until their overlays have also been cleared, so a
    // renderer failure can be retried without losing the original targets.
    if (_pendingDeletion.isNotEmpty) return _pendingDeletion.values.toList();
    final targets = <int, BookNote>{};
    final current = await _fetchLatestNote() ?? _currentNote;
    final ids = {
      ...widget.annotationIds,
      if (current?.id != null) current!.id!
    };
    for (final id in ids) {
      BookNote note;
      try {
        note = await _dao.selectBookNoteById(id);
      } on StateError {
        continue; // A remotely deleted or merged mark is no longer a target.
      }
      if (_bookId != null && note.bookId != _bookId) continue;
      if (note.type != 'highlight' && note.type != 'underline') continue;
      targets[id] = note;
      // Old imports/syncs may contain multiple records for the same range.
      // Include them in the confirmation instead of leaving a hidden copy
      // that reappears after the chapter is loaded again.
      for (final duplicate
          in await _dao.selectBookNoteByCfiAndBookId(note.cfi, note.bookId)) {
        if (duplicate.id != null &&
            (duplicate.type == 'highlight' || duplicate.type == 'underline')) {
          targets[duplicate.id!] = duplicate;
        }
      }
    }
    return targets.values.toList();
  }

  Future<void> deleteHandler() async {
    if (_deleting || _saving) return;
    setState(() => _deleting = true);
    widget.onDeletionVisibilityChanged?.call(true);
    try {
      final l10n = L10n.of(context);
      final targets = await _deletionTargets();
      if (!mounted) return;
      if (targets.isEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text(ModuStrings.text(context, '所选文字没有可删除的标记。',
                'There are no saved marks in this selection.'))));
        return;
      }
      final confirmed = await showDialog<bool>(
        animationStyle: AppMotion.style,
        context: context,
        builder: (context) => PointerInterceptor(
            child: AlertDialog(
          title: Text(l10n.contextMenuDelete),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ModuStrings.format(context, '删除选区涉及的 {count} 条完整标记及其批注？',
                    'Delete all {count} matching marks and their notes?',
                    values: {'count': targets.length})),
                for (final note in targets) ...[
                  const SizedBox(height: 12),
                  Text(note.content,
                      maxLines: 5, overflow: TextOverflow.ellipsis),
                  if (note.readerNote?.isNotEmpty ?? false)
                    Text(note.readerNote!,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              key: const ValueKey('annotation-confirm-delete'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.commonDelete),
            ),
          ],
        )),
      );
      if (confirmed != true || !mounted) return;

      _pendingDeletion.addEntries(targets.map((n) => MapEntry(n.id!, n)));
      for (final note in targets) {
        await _dao.deleteBookNoteById(note.id!);
      }
      for (final cfi in targets.map((note) => note.cfi).toSet()) {
        if (widget.removeAnnotation != null) {
          await widget.removeAnnotation!(cfi);
        } else {
          final player = epubPlayerKey.currentState;
          if (player == null) throw StateError('Reader no longer available');
          await player.removeAnnotation(cfi);
        }
        _pendingDeletion.removeWhere((_, note) => note.cfi == cfi);
      }
      if (mounted) widget.onClose();
    } catch (_) {
      if (mounted) {
        final l10n = L10n.of(context);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
            content: Text('${l10n.commonDelete}: ${l10n.commonFailed}')));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
      widget.onDeletionVisibilityChanged?.call(false);
    }
  }

  Future<void> onColorSelected(String color, {bool close = true}) async {
    if (_saving || _deleting) return;
    setState(() => _saving = true);
    Prefs().annotationColor = color;
    if (mounted) {
      setState(() {
        annoColor = color;
      });
    } else {
      annoColor = color;
    }
    try {
      final bookNote = await _persistNote(color: color);
      await epubPlayerKey.currentState!.addAnnotation(bookNote);
      if (close && mounted) widget.onClose();
    } on NoteConflictException {
      if (mounted) {
        AnxToast.show(NoteConflictException.message(
            Localizations.localeOf(context).languageCode == 'zh'));
      }
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> onTypeSelected(String type) async {
    if (_saving || _deleting) return;
    setState(() => _saving = true);
    Prefs().annotationType = type;
    if (mounted) {
      setState(() {
        annoType = type;
      });
    } else {
      annoType = type;
    }
    try {
      final bookNote = await _persistNote(type: type);
      await epubPlayerKey.currentState!.addAnnotation(bookNote);
    } on NoteConflictException {
      if (mounted) {
        AnxToast.show(NoteConflictException.message(
            Localizations.localeOf(context).languageCode == 'zh'));
      }
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget iconButton(
      {Key? key, required Icon icon, required VoidCallback? onPressed}) {
    return IconButton(
      key: key,
      padding: const EdgeInsets.all(2),
      constraints: const BoxConstraints(),
      style: const ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: icon,
      onPressed: onPressed,
    );
  }

  Future<void> _runAction(SelectionToolbarItem item) async {
    final popupContext = Navigator.of(context).context;
    final reader = readingPageKey.currentState;
    final text = widget.annoContent;
    switch (item.action) {
      case 'copy':
        final message = L10n.of(context).notesPageCopied;
        await Clipboard.setData(ClipboardData(text: text));
        AnxToast.show(message);
        if (mounted) widget.onClose();
        break;
      case 'search':
        widget.onClose();
        if (reader != null) {
          await reader.showSelectionSearch(text);
        } else if (popupContext.mounted) {
          await showSelectionSearchBrowser(popupContext, text: text);
        }
        break;
      case 'translate':
        widget.toggleTranslationMenu();
        break;
      case 'dictionary':
        widget.onClose();
        if (reader != null) {
          await reader.showSelectionDictionary(text);
        } else if (popupContext.mounted) {
          await showReaderPopup(popupContext,
              builder: (_) => DictionaryLookup(word: text));
        }
        break;
      case 'narrate':
        final cfi = widget.annoCfi;
        widget.onClose();
        final player = epubPlayerKey.currentState;
        if (player == null) return;
        await audioHandler.stop();
        if (!player.mounted || epubPlayerKey.currentState != player) return;
        await TtsHandler().init(
            () => player.initTts(fromCfi: cfi), player.ttsNext, player.ttsPrev);
        await audioHandler.play();
        break;
      case 'note':
        epubPlayerKey.currentState?.setSelectionClearLocked(true);
        await onColorSelected(annoColor, close: false);
        if (!mounted) return;
        final targetId = noteId ?? widget.id;
        if (targetId != null) {
          await widget.openReaderNoteMenu(targetId);
        } else {
          widget.toggleReaderNoteMenu(show: true);
        }
        break;
      case 'ai':
      case 'aiCommand':
        final prompt = item.prompt.isEmpty
            ? text
            : item.promptForSelection(text,
                locale: Localizations.localeOf(context));
        widget.onClose();
        await reader?.showAiChat(
          content: prompt,
          sourceText: text,
          sourceContext: item.scope == SelectionAiScope.context
              ? widget.contextText
              : null,
          selectionRequest: true,
          webSearch: item.webSearch,
          skillId: item.skillId,
          sendImmediate: item.prompt.isNotEmpty,
          newConversation: true,
          forcePopup: true,
        );
        break;
      case 'share':
        final player = epubPlayerKey.currentState;
        if (player == null) return;
        final book = player.book;
        final chapter = player.selectionChapterTitle;
        widget.onClose();
        if (!popupContext.mounted) return;
        ExcerptShareService.showShareExcerpt(
          context: popupContext,
          bookTitle: book.title,
          author: book.author,
          excerpt: text,
          chapter: chapter,
        );
        break;
    }
  }

  void _openSettings() {
    final popupContext = Navigator.of(context).context;
    widget.onClose();
    if (popupContext.mounted) showSelectionToolbarSettings(popupContext);
  }

  Widget _annotationAction(SelectionToolbarItem item, List<String> colors) {
    if (item.action == 'colors') {
      return Tooltip(
        message: selectionToolbarLabel(context, item),
        child: IgnorePointer(
          ignoring: _saving || _deleting,
          child: AnnotationColorPalette(
              axis: widget.axis,
              colors: colors,
              selectedColor: annoColor,
              onSelected: (color) => onColorSelected(color)),
        ),
      );
    }
    final type = item.action == 'highlight' ? 'highlight' : 'underline';
    return Tooltip(
      message: selectionToolbarLabel(context, item),
      child: iconButton(
        key: ValueKey('annotation-action-${item.action}'),
        icon: Icon(selectionToolbarIcon(item),
            color: item.action != 'delete' && annoType == type
                ? Color(int.parse('ff$annoColor', radix: 16))
                : null),
        onPressed: _saving || _deleting
            ? null
            : () {
                if (item.action == 'delete') {
                  deleteHandler();
                } else {
                  onTypeSelected(type);
                }
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Expanded(
        child: AnimatedBuilder(
            animation: Prefs(),
            builder: (context, _) {
              final config = Prefs().selectionToolbar;
              if (!config.enabled) return const SizedBox.shrink();
              final annotationItems = config.annotations
                  .where((i) =>
                      i.enabled && (i.action != 'delete' || _hasDeletionTarget))
                  .toList();
              return LayoutBuilder(builder: (context, constraints) {
                final extent = widget.axis == Axis.horizontal
                    ? constraints.maxWidth
                    : constraints.maxHeight;
                final menu = SelectionActionToolbar(
                  items: config.availableItems(
                      footnote: widget.footnote,
                      aiEnabled: EnvVar.enableAIFeature),
                  visibleCount: config.visibleCount,
                  axis: widget.axis,
                  maxExtent: extent,
                  onAction: _runAction,
                  onSettings: _openSettings,
                  parentRoute: widget.parentRoute,
                );
                return AxisFlex(
                  reverse: widget.reverse,
                  axis: flipAxis(widget.axis),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(decoration: widget.decoration, child: menu),
                    if (!widget.footnote && annotationItems.isNotEmpty) ...[
                      const SizedBox.square(dimension: 10),
                      SingleChildScrollView(
                        scrollDirection: widget.axis,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: widget.decoration,
                          child: AxisFlex(
                            axis: widget.axis,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final item in annotationItems)
                                _annotationAction(item, config.colors)
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              });
            }),
      );
}
