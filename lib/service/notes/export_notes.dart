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

  final groups = _groupNotesByChapter(notesList, mergeChapterHeadings);

  switch (exportType) {
    case ExportType.copy:
      var notes = '${book.title}\n\t${book.author}\n\n';
      notes += groups.map(_formatPlainGroup).join('\n\n');

      await Clipboard.setData(ClipboardData(text: notes));
      AnxToast.show(L10n.of(context).notesPageCopied);
      break;

    case ExportType.md:
      var notes = '# ${book.title}\n\n *${book.author}*\n\n';
      notes += groups.map(_formatMarkdownGroup).join('');

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
      List<List<dynamic>> list = List.from([
        [
          'Book',
          'Author',
          'Chapter',
          'Content',
          'Reader Note',
          'Type',
          'Color',
          'Create Time',
          'Update Time'
        ],
        ...notesList.map((note) {
          return List.from([
            book.title,
            book.author,
            note.chapter,
            note.content,
            note.readerNote,
            note.type,
            '#${note.color}',
            note.createTime!.toIso8601String(),
            note.updateTime.toIso8601String(),
          ]);
        })
      ]);

      final string = const ListToCsvConverter().convert(list);

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

/// Pure TXT formatting, shared by all platforms without changing MD/CSV/copy.
String formatNotesText(List<BookNote> notes,
    {bool mergeChapterHeadings = false, bool chinese = true}) {
  return _groupNotesByChapter(notes, mergeChapterHeadings)
      .map((group) =>
          _formatPlainGroup(group, annotateReaderNotes: true, chinese: chinese))
      .join('\n\n');
}

String _noteTimeLabel(BookNote note, bool chinese) {
  // Legacy rows without update_time are hydrated with DateTime.now(). Do not
  // export that synthetic value as though the user just edited the note.
  final saved = note.persistedValues;
  final updated = saved != null && saved['update_time'] == null
      ? null
      : note.updateTime;
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

String _formatPlainGroup(_ChapterGroup group,
    {bool annotateReaderNotes = false, bool chinese = true}) {
  final buffer = StringBuffer();
  if (group.chapter.isNotEmpty) {
    buffer.writeln(group.chapter);
  }
  for (final note in group.notes) {
    if (note.content.isNotEmpty) {
      buffer.writeln('\t${note.content}');
    }
    if (note.readerNote != null && note.readerNote!.isNotEmpty) {
      if (annotateReaderNotes) {
        if (note.readerNote!.trim().isNotEmpty) {
          buffer.writeln();
          buffer.writeln(chinese ? '--- 笔记 ---' : '--- Note ---');
          buffer.writeln(note.readerNote);
          buffer.writeln('--- ${_noteTimeLabel(note, chinese)} ---');
        }
      } else {
        buffer.writeln('\t\t${note.readerNote}');
      }
    }
    buffer.writeln();
  }
  return buffer.toString().trim();
}

String _formatMarkdownGroup(_ChapterGroup group) {
  final buffer = StringBuffer();
  buffer.writeln('## ${group.chapter}\n');
  for (final note in group.notes) {
    if (note.content.isNotEmpty) {
      buffer.writeln('> ${note.content}\n');
    }
    if (note.readerNote != null && note.readerNote!.isNotEmpty) {
      buffer.writeln('${note.readerNote}\n');
    }
    buffer.writeln();
  }
  return buffer.toString();
}
