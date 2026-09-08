import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/models/book_note.dart';

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
  }) {
    final operation = _tail.then((_) async {
      if (text.trim().isEmpty ||
          text.length > 100000 ||
          !cfi.startsWith('epubcfi(') ||
          !cfi.endsWith(')')) {
        throw const FormatException('Invalid quick mark');
      }
      final safeColor =
          RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(color)
              ? color
              : 'ffd54f';
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
                !mergedText.contains(source['text'] as String)) break;
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
            if (merged != null)
              return QuickMarkResult(
                  merged, sources.map((s) => s.cfi).toList());
          }
        }
      }
      final existing = await dao.selectBookNoteByCfiAndBookId(cfi, bookId);
      if (existing.isNotEmpty) return QuickMarkResult(existing.last);
      final now = DateTime.now();
      final note = BookNote(
          bookId: bookId,
          content: text,
          cfi: cfi,
          chapter: chapter,
          type: 'highlight',
          color: safeColor,
          createTime: now,
          updateTime: now);
      note.setId(await dao.save(note));
      return QuickMarkResult(note);
    });
    _tail = operation.then<void>((_) {},
        onError: (Object error, StackTrace stack) {});
    return operation;
  }
}
