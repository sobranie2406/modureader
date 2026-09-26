import 'dart:convert';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/utils/convert_string_to_uint8list.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:csv/csv.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:anx_reader/utils/toast/common.dart';

enum ExportType { copy, md, txt, csv }

Future<void> exportNotes(
  Book book,
  List<BookNote> notesList,
  ExportType exportType, {
  bool mergeChapterHeadings = false,
}) async {
  BuildContext context = navigatorKey.currentContext!;
  if (notesList.isEmpty) {
    return;
  }

  final chinese = Localizations.localeOf(context).languageCode == 'zh';

  switch (exportType) {
    case ExportType.copy:
      var notes = '${book.title}\n\t${book.author}\n\n';
      notes += formatNotesText(notesList,
          mergeChapterHeadings: mergeChapterHeadings, chinese: chinese);

      await Clipboard.setData(ClipboardData(text: notes));
      AnxToast.show(L10n.of(context).notesPageCopied);
      break;

    case ExportType.md:
      final notes = formatNotesMarkdown(notesList,
          title: book.title,
          author: book.author,
          mergeChapterHeadings: mergeChapterHeadings,
          chinese: Localizations.localeOf(context).languageCode == 'zh');

      String? filePath = await saveFileToDownload(
          bytes: convertStringToUint8List(notes),
          fileName: '${book.title.replaceAll('\n', ' ')}.md',
          mimeType: 'text/markdown');

      if (filePath != null) {
        AnxToast.show('${L10n.of(context).notesPageExportedTo} $filePath');
      }
      break;

    case ExportType.txt:
      final notes = formatNotesText(notesList,
          mergeChapterHeadings: mergeChapterHeadings,
          chinese: Localizations.localeOf(context).languageCode == 'zh');
      String? filePath = await saveFileToDownload(
          bytes: convertStringToUint8List(notes),
          fileName: '${book.title}.txt',
          mimeType: 'text/plain');
      if (filePath != null) {
        AnxToast.show('${L10n.of(context).notesPageExportedTo} $filePath');
      }
      break;

    case ExportType.csv:
      final string = formatNotesCsv(notesList,
          title: book.title, author: book.author, chinese: chinese);

      String? filePath = await saveFileToDownload(
          bytes: Uint8List.fromList(gbk.encode(string)),
          fileName: '${book.title}.csv',
          mimeType: 'text/csv');
      if (filePath != null) {
        AnxToast.show('${L10n.of(context).notesPageExportedTo} $filePath');
      }
      break;
  }
}

class _ChapterGroup {
  final String chapter;
  final List<BookNote> notes;

  _ChapterGroup(this.chapter, this.notes);
}

List<_ChapterGroup> _groupNotesByChapter(
    List<BookNote> notes, bool mergeChapters) {
  if (!mergeChapters) {
    return notes.map((note) => _ChapterGroup(note.chapter, [note])).toList();
  }

  final groups = <_ChapterGroup>[];
  if (notes.isEmpty) return groups;

  String currentChapter = notes.first.chapter;
  List<BookNote> currentNotes = [];

  void pushGroup() {
    groups
        .add(_ChapterGroup(currentChapter, List<BookNote>.from(currentNotes)));
  }

  for (final note in notes) {
    if (currentNotes.isEmpty) {
      currentChapter = note.chapter;
      currentNotes.add(note);
      continue;
    }

    if (note.chapter == currentChapter) {
      currentNotes.add(note);
    } else {
      pushGroup();
      currentChapter = note.chapter;
      currentNotes = [note];
    }
  }

  if (currentNotes.isNotEmpty) {
    pushGroup();
  }

  return groups;
}

/// Plain exports and clipboard share explicit excerpt, note and time labels.
String formatNotesText(List<BookNote> notes,
    {bool mergeChapterHeadings = false, bool chinese = true}) {
  return _groupNotesByChapter(notes, mergeChapterHeadings)
      .map((group) => _formatPlainGroup(group, chinese: chinese))
      .join('\n\n');
}

String _noteTimeLabel(BookNote note, bool chinese) {
  // Legacy rows without update_time are hydrated with DateTime.now(). Do not
  // export that synthetic value as though the user just edited the note.
  final updated = _persistedUpdateTime(note);
  final created = note.createTime;
  final modified =
      updated != null && (created == null || updated.isAfter(created));
  final time = (modified ? updated : created ?? updated)?.toLocal();
  if (time == null) return chinese ? '时间未知' : 'Time unknown';
  final label = chinese
      ? (modified ? '最后修改' : '创建时间')
      : (modified ? 'Last modified' : 'Created');
  final minute = time.minute.toString().padLeft(2, '0');
  final date = chinese
      ? '${time.year}年${time.month}月${time.day}日${time.hour}点$minute分'
      : '${time.year}-${time.month.toString().padLeft(2, '0')}-'
          '${time.day.toString().padLeft(2, '0')} '
          '${time.hour.toString().padLeft(2, '0')}:$minute';
  return chinese ? '$label：$date' : '$label: $date';
}

String _formatPlainGroup(_ChapterGroup group, {bool chinese = true}) {
  final buffer = StringBuffer();
  if (group.chapter.isNotEmpty) {
    buffer.writeln(group.chapter);
  }
  for (final note in group.notes) {
    if (note.content.trim().isNotEmpty) {
      buffer.writeln(_labelledExcerpt(note.content, chinese));
    }
    if (note.readerNote?.trim().isNotEmpty ?? false) {
      buffer.writeln();
      buffer.writeln(chinese ? '--- 笔记 ---' : '--- Note ---');
      buffer.writeln(note.readerNote);
    }
    buffer.writeln('--- ${_noteTimeLabel(note, chinese)} ---');
    buffer.writeln();
  }
  return buffer.toString().trim();
}

String _labelledExcerpt(String text, bool chinese) =>
    text.trim().isEmpty ? '' : '${chinese ? '原文：' : 'Excerpt: '}【$text】';

DateTime? _persistedUpdateTime(BookNote note) =>
    note.persistedValues != null && note.persistedValues!['update_time'] == null
        ? null
        : note.updateTime;

String formatNotesCsv(List<BookNote> notes,
        {String title = '', String author = '', bool chinese = true}) =>
    const ListToCsvConverter().convert([
      [
        'Book',
        'Author',
        'Chapter',
        'Content',
        'Reader Note',
        'Type',
        'Color',
        'Create Time',
        'Update Time',
        'Note Time'
      ],
      for (final note in notes)
        [
          title,
          author,
          note.chapter,
          _labelledExcerpt(note.content, chinese),
          note.readerNote,
          note.type,
          '#${note.color}',
          note.createTime?.toIso8601String() ?? '',
          _persistedUpdateTime(note)?.toIso8601String() ?? '',
          _noteTimeLabel(note, chinese)
        ],
    ]);

/// Export literal excerpts, not executable HTML or source Markdown. Each entry
/// has its own persisted timestamp, including highlights without reader notes.
String formatNotesMarkdown(List<BookNote> notes,
    {String title = '',
    String author = '',
    bool mergeChapterHeadings = false,
    bool chinese = true}) {
  if (notes.isEmpty) return '';
  final buffer = StringBuffer();
  if (title.trim().isNotEmpty) {
    buffer.writeln(
        '# ${_escapeMarkdown(title.replaceAll(RegExp(r'[\r\n]+'), ' '))}\n');
  }
  if (author.trim().isNotEmpty) {
    buffer.writeln(
        '*${_escapeMarkdown(author.replaceAll(RegExp(r'[\r\n]+'), ' '))}*\n');
  }
  for (final group in _groupNotesByChapter(notes, mergeChapterHeadings)) {
    if (group.chapter.trim().isNotEmpty) {
      buffer.writeln(
          '## ${_escapeMarkdown(group.chapter.replaceAll(RegExp(r'[\r\n]+'), ' '))}\n');
    }
    for (final note in group.notes) {
      if (note.content.trim().isNotEmpty) {
        final text = _escapeMarkdown(_normalizeLines(note.content));
        // One bracket pair contains every paragraph, matching plain exports.
        buffer.writeln('${_labelledExcerpt(_markdownLines(text), chinese)}\n');
      }
      final comment = note.readerNote;
      if (comment != null && comment.trim().isNotEmpty) {
        buffer.writeln(chinese ? '**笔记**\n' : '**Note**\n');
        // HTML mark has wider support than non-standard ==highlight==.
        // Encode all user text so it cannot close the tag or inject HTML.
        final paragraphs =
            _normalizeLines(comment).split(RegExp(r'\n[ \t]*\n'));
        buffer.writeln(paragraphs
            .map((paragraph) =>
                '<mark>${const HtmlEscape().convert(paragraph).replaceAll('\n', '<br>')}</mark>')
            .join('\n\n'));
        buffer.writeln();
      }
      buffer.writeln('**${_noteTimeLabel(note, chinese)}**\n');
      buffer.writeln('---\n');
    }
  }
  return buffer.toString();
}

String _normalizeLines(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _markdownLines(String text) => text
    .split('\n')
    .map((line) => line.isEmpty ? '' : '$line  ')
    .join('\n')
    .trimRight();

String _escapeMarkdown(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAllMapped(
        RegExp(r'[\\`*_{}\[\]()#+.!|~=-]'), (match) => '\\${match[0]}');
