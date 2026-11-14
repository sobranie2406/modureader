import 'package:modu_reader/dao/book_note.dart';
import 'package:modu_reader/models/book_note.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';

class QuickMarkResult {
  const QuickMarkResult(this.note, [this.replacedCfis = const []]);
  final BookNote note;
  final List<String> replacedCfis;
  Map<String, dynamic> toJson() => {
        'annotation': note.toJson(),
        'replacedCfis': replacedCfis,
      };
}

/// Serialize quick strokes and preserve an existing note at the same location.
class QuickMarkService {
  QuickMarkService(this.dao);
  final BookNoteDao dao;
  Future<void> _tail = Future.value();
  Future<void> flush() => _tail;

  Future<BookNote> save({
    required int bookId,
    required String cfi,
    required String text,
    required String chapter,
    required String color,
  }) async =>
      (await saveStroke(
              bookId: bookId,
              cfi: cfi,
              text: text,
              chapter: chapter,
              color: color))
          .note;

  Future<QuickMarkResult> saveStroke({
    required int bookId,
    required String cfi,
    required String text,
    required String chapter,
    required String color,
    Map? merge,
  }) =>
      _queued(() async {
        if (text.trim().isEmpty ||
            text.length > 100000 ||
            !cfi.startsWith('epubcfi(') ||
            !cfi.endsWith(')')) {
          throw const FormatException('Invalid quick mark');
        }
        final safeColor = _safeColor(color);
        if (merge != null &&
            merge['cfi'] is String &&
            merge['text'] is String &&
            merge['sources'] is List) {
          final mergedCfi = merge['cfi'] as String;
          final mergedText = merge['text'] as String;
          final rawSources = merge['sources'] as List;
          final sources = <({int id, String cfi, String text})>[];
          // One EPUB CFI range belongs to a single spine document. Do not create
          // an invalid cross-chapter range which cannot render after reopening.
          String spine(String value) => value.split('!').first;
          final valid = mergedCfi.startsWith('epubcfi(') &&
              mergedCfi.endsWith(')') &&
              spine(mergedCfi) == spine(cfi) &&
              mergedText.trim().isNotEmpty &&
              mergedText.length <= 100000 &&
              mergedText.contains(text) &&
              rawSources.isNotEmpty &&
              rawSources.length <= 128;
          if (valid) {
            for (final source in rawSources) {
              if (source is! Map ||
                  source['id'] is! int ||
                  source['cfi'] is! String ||
                  source['text'] is! String ||
                  spine(source['cfi'] as String) != spine(cfi) ||
                  !mergedText.contains(source['text'] as String)) {
                break;
              }
              sources.add((
                id: source['id'] as int,
                cfi: source['cfi'] as String,
                text: source['text'] as String
              ));
            }
            if (sources.length == rawSources.length) {
              final merged = await dao.mergeQuickMarks(
                  bookId: bookId,
                  cfi: mergedCfi,
                  text: mergedText,
                  color: safeColor,
                  sources: sources);
              if (merged != null) {
                return QuickMarkResult(
                    merged, sources.map((s) => s.cfi).toList());
              }
            }
          }
        }
        return _saveHighlight(bookId, cfi, text, chapter, safeColor);
      });

  Future<QuickMarkResult> saveReflowStroke({
    required int bookId,
    required DocumentReflowAnchor anchor,
    required DocumentReflowPage page,
    required String chapter,
    required String color,
  }) =>
      _queued(() async {
        if (anchor.original ||
            DocumentReflowAnchor.parse(anchor.encode()) == null ||
            !anchor.matches(page) ||
            anchor.ocr != page.ocr ||
            page.text.length > 1000000) {
          throw const FormatException('Invalid reflow quick mark');
        }
        final text = page.text.substring(anchor.start, anchor.end);
        if (text.trim().isEmpty || text.length > 100000) {
          throw const FormatException('Invalid reflow quick mark');
        }
        final cfi = page.anchor(anchor.start, anchor.end).encode();
        if (DocumentReflowAnchor.parse(cfi) == null) {
          throw const FormatException('Invalid reflow quick mark');
        }
        final safeColor = _safeColor(color);
        final candidates = <({BookNote note, DocumentReflowAnchor anchor})>[];
        for (final note in await dao.selectBookNotesByBookId(bookId)) {
          if (note.bookId != bookId) continue;
          if (note.cfi == cfi) return QuickMarkResult(note);
          final saved = DocumentReflowAnchor.parse(note.cfi);
          if (saved == null ||
              saved.original ||
              !saved.matches(page) ||
              saved.ocr != page.ocr ||
              note.content != page.text.substring(saved.start, saved.end)) {
            continue;
          }
          if (saved.start == anchor.start && saved.end == anchor.end) {
            return QuickMarkResult(note);
          }
          if (note.id != null &&
              note.type == 'highlight' &&
              note.color.toLowerCase() == safeColor.toLowerCase() &&
              !(note.readerNote?.trim().isNotEmpty ?? false)) {
            candidates.add((note: note, anchor: saved));
          }
        }
        var start = anchor.start, end = anchor.end;
        final connected = <({BookNote note, DocumentReflowAnchor anchor})>[];
        final sourceIds = <int>{};
        var expanded = true;
        while (expanded) {
          expanded = false;
          for (final candidate in candidates) {
            if (sourceIds.contains(candidate.note.id) ||
                candidate.anchor.end < start ||
                candidate.anchor.start > end) {
              continue;
            }
            connected.add(candidate);
            sourceIds.add(candidate.note.id!);
            start =
                candidate.anchor.start < start ? candidate.anchor.start : start;
            end = candidate.anchor.end > end ? candidate.anchor.end : end;
            expanded = true;
            if (connected.length > 128 || end - start > 100000) {
              return _saveHighlight(bookId, cfi, text, chapter, safeColor);
            }
          }
        }
        if (connected.isNotEmpty) {
          connected.sort((a, b) {
            final order = a.anchor.start.compareTo(b.anchor.start);
            return order != 0 ? order : a.note.id!.compareTo(b.note.id!);
          });
          final mergedCfi = page.anchor(start, end).encode();
          if (DocumentReflowAnchor.parse(mergedCfi) != null) {
            final merged = await dao.mergeQuickMarks(
                bookId: bookId,
                cfi: mergedCfi,
                text: page.text.substring(start, end),
                color: safeColor,
                sources: [
                  for (final source in connected)
                    (
                      id: source.note.id!,
                      cfi: source.note.cfi,
                      text: source.note.content
                    )
                ]);
            if (merged != null) {
              return QuickMarkResult(
                  merged, connected.map((source) => source.note.cfi).toList());
            }
          }
        }
        return _saveHighlight(bookId, cfi, text, chapter, safeColor);
      });

  String _safeColor(String color) =>
      RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(color)
          ? color
          : 'ffd54f';

  Future<QuickMarkResult> _saveHighlight(
      int bookId, String cfi, String text, String chapter, String color) async {
    final existing = await dao.selectBookNoteByCfiAndBookId(cfi, bookId);
    if (existing.isNotEmpty) return QuickMarkResult(existing.last);
    final now = DateTime.now();
    final note = BookNote(
        bookId: bookId,
        content: text,
        cfi: cfi,
        chapter: chapter,
        type: 'highlight',
        color: color,
        createTime: now,
        updateTime: now);
    note.setId(await dao.save(note));
    return QuickMarkResult(note);
  }

  Future<QuickMarkResult> _queued(Future<QuickMarkResult> Function() save) {
    final operation = _tail.then((_) => save());
    _tail = operation.then<void>((_) {},
        onError: (Object error, StackTrace stack) {});
    return operation;
  }
}
