import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/service/notes/export_notes.dart';
import 'package:flutter_test/flutter_test.dart';

BookNote note(
        {String? text = '我的理解\n第二行笔记',
        String chapter = '第一章',
        DateTime? created,
        DateTime? updated}) =>
    BookNote(
      bookId: 1,
      content: '书中的原文',
      cfi: '',
      chapter: chapter,
      type: 'highlight',
      color: 'ffff00',
      readerNote: text,
      createTime: created ?? DateTime(2026, 9, 20, 10),
      updateTime: updated ?? DateTime(2026, 9, 22, 16, 8),
    );

void main() {
  test('TXT separates multiline reader notes and uses last modification time',
      () {
    final result = formatNotesText([note()]);
    expect(
        result,
        contains('书中的原文\n\n--- 笔记 ---\n我的理解\n第二行笔记\n'
            '--- 最后修改：2026年9月22日16点08分 ---'));
    expect(result, startsWith('第一章\n'));
  });

  test('unmodified note is labelled with its creation time', () {
    final time = DateTime(2026, 9, 22, 9, 3);
    expect(formatNotesText([note(created: time, updated: time)]),
        contains('--- 创建时间：2026年9月22日9点03分 ---'));
  });

  test('UTC timestamps are exported in local time', () {
    final utc = DateTime.utc(2026, 9, 22, 23, 5);
    final local = utc.toLocal();
    expect(
        formatNotesText([note(updated: utc)]),
        contains('${local.year}年${local.month}月${local.day}日${local.hour}点'
            '${local.minute.toString().padLeft(2, '0')}分'));
  });

  test('old rows use creation time, not hydration time, or report unknown', () {
    for (final created in ['2026-09-22T09:03:00', null]) {
      final legacy = BookNote.fromDb({
        'book_id': 1,
        'reader_note': '旧笔记',
        'create_time': created,
        'update_time': null,
      });
      final text = formatNotesText([legacy]);
      expect(text, contains(created == null ? '时间未知' : '创建时间：2026年9月22日9点03分'));
      expect(text, isNot(contains('最后修改')));
    }
  });

  test('highlight-only entries do not acquire empty note blocks', () {
    for (final text in [null, '', ' \n ']) {
      final result = formatNotesText([note(text: text)]);
      expect(result, contains('书中的原文'));
      expect(result, isNot(contains('---')));
    }
    expect(formatNotesText([]), '');
  });

  test('chapter merging preserves order and timestamps for each note', () {
    final notes = [
      note(text: '笔记一'),
      note(text: '笔记二'),
      note(text: '笔记三', chapter: '第二章')
    ];
    final merged = formatNotesText(notes, mergeChapterHeadings: true);
    expect('第一章'.allMatches(merged).length, 1);
    expect('--- 笔记 ---'.allMatches(merged).length, 3);
    expect('最后修改'.allMatches(merged).length, 3);
    expect(merged.indexOf('笔记一'), lessThan(merged.indexOf('笔记二')));
    expect(merged.indexOf('笔记二'), lessThan(merged.indexOf('第二章')));
    expect('第一章'.allMatches(formatNotesText(notes)).length, 2);
  });

  test('non-Chinese exports retain explicit labels', () {
    final result = formatNotesText([note()], chinese: false);
    expect(result, contains('--- Note ---'));
    expect(result, contains('Last modified: 2026-09-22 16:08'));
  });
}
