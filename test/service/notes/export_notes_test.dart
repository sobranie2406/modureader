import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/service/notes/export_notes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:csv/csv.dart';

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
  test('Markdown brackets excerpts and highlights only reader notes', () {
    final entry = note()..content = '第一段\r\n第二行\r\n\r\n第二段';
    final result = formatNotesMarkdown([entry], title: '书名', author: '作者');
    expect(result, startsWith('# 书名\n\n*作者*\n\n## 第一章\n'));
    expect(result, contains('原文：【第一段  \n第二行  \n\n第二段】'));
    expect(result, contains('**笔记**\n\n<mark>我的理解<br>第二行笔记</mark>'));
    expect(result, contains('**最后修改：2026年9月22日16点08分**\n\n---'));
    expect(result, isNot(contains('<mark>第一段')));
  });

  test('Markdown bracket style keeps all excerpt paragraphs in one pair', () {
    final entry = note()..content = '第一段\n第二行\n\n第二段';
    final result = formatNotesMarkdown([entry]);
    expect(result, contains('【第一段  \n第二行  \n\n第二段】'));
    expect('【'.allMatches(result).length, 1);
    expect('】'.allMatches(result).length, 1);
    expect(result, contains('**笔记**\n\n<mark>我的理解<br>第二行笔记</mark>'));
    expect(result, contains('最后修改：2026年9月22日16点08分'));
  });

  test(
      'Markdown preserves literal user text without HTML or Markdown injection',
      () {
    final entry = note(text: '</mark><script>alert("x")</script>\n\n另一段')
      ..chapter = '章节\n# 意外标题'
      ..content = '[文字](https://example.test)\n<img src=x>\n# 标题';
    final result = formatNotesMarkdown([entry], title: '*书名*');
    expect(result, contains(r'# \*书名\*'));
    expect(result, contains(r'## 章节 \# 意外标题'));
    expect(result, contains(r'\[文字\]\(https://example\.test\)'));
    expect(result, contains('&lt;img src'));
    expect(result, isNot(contains('<script>')));
    expect(result, isNot(contains('<img')));
    expect(
        formatNotesMarkdown([entry]), contains('</mark>\n\n<mark>另一段</mark>'));
  });

  test('Markdown creation and legacy timestamps never use export time', () {
    final time = DateTime(2026, 9, 22, 9, 3);
    final unchanged = note(created: time, updated: time);
    final legacy = BookNote.fromDb({
      'book_id': 1,
      'reader_note': '旧笔记',
      'create_time': '2026-09-22T09:03:00',
      'update_time': null
    });
    for (final entry in [unchanged, legacy]) {
      final result = formatNotesMarkdown([entry]);
      expect(result, contains('创建时间：2026年9月22日9点03分'));
      expect(result, isNot(contains('最后修改')));
    }
    expect(
        formatNotesMarkdown([
          BookNote.fromDb({'book_id': 1})
        ]),
        contains('时间未知'));
  });

  test('Markdown merged entries each retain their own note and timestamp', () {
    final entries = [
      note(text: '笔记一'),
      note(text: '笔记二'),
      note(chapter: '第二章')
    ];
    final result = formatNotesMarkdown(entries, mergeChapterHeadings: true);
    expect('## 第一章'.allMatches(result).length, 1);
    expect('**笔记**'.allMatches(result).length, 3);
    expect('最后修改'.allMatches(result).length, 3);
    expect(result.indexOf('笔记一'), lessThan(result.indexOf('笔记二')));
    expect('## 第一章'.allMatches(formatNotesMarkdown(entries)).length, 2);
  });

  test('Markdown highlight-only and note-only entries remain explicit', () {
    for (final comment in [null, '', ' \n ']) {
      final result = formatNotesMarkdown([note(text: comment)]);
      expect(result, contains('原文：【书中的原文】'));
      expect(result, isNot(contains('**笔记**')));
      expect(result, isNot(contains('<mark>')));
      expect(result, contains('最后修改'));
    }
    final result = formatNotesMarkdown([note()..content = ''], chinese: false);
    expect(result, contains('**Note**'));
    expect(result, isNot(contains('Excerpt:')));
    expect(result, contains('Last modified: 2026-09-22 16:08'));
    expect(formatNotesMarkdown([]), '');
  });

  test('TXT separates multiline reader notes and uses last modification time',
      () {
    final result = formatNotesText([note()]);
    expect(
        result,
        contains('原文：【书中的原文】\n\n--- 笔记 ---\n我的理解\n第二行笔记\n'
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
      expect(result, isNot(contains('--- 笔记 ---')));
      expect(result, contains('原文：【书中的原文】'));
      expect(result, contains('最后修改'));
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
    expect(result, contains('Excerpt: 【书中的原文】'));
  });

  test('plain exports bracket multiple paragraphs without enclosing notes', () {
    final result = formatNotesText([note()..content = '原文一\n\n原文二']);
    expect(result, contains('原文：【原文一\n\n原文二】\n\n--- 笔记 ---'));
    expect(result, isNot(contains('【我的理解')));
    final commentOnly = formatNotesText([note()..content = '']);
    expect(commentOnly, isNot(contains('原文：【】')));
    expect(commentOnly, contains('我的理解'));
  });

  test('CSV uses labelled brackets, handles quotes/newlines and keeps columns',
      () {
    final entry = note()..content = '第一段,"引用"\n\n第二段';
    final csv = formatNotesCsv([entry], title: '书名', author: '作者');
    final rows =
        const CsvToListConverter(shouldParseNumbers: false).convert(csv);
    expect(rows[1][3], '原文：【第一段,"引用"\n\n第二段】');
    expect(rows[1][4], '我的理解\n第二行笔记');
    expect(rows[1][9], '最后修改：2026年9月22日16点08分');
    expect(rows[1].length, rows[0].length);
  });

  test('CSV missing legacy timestamps stay empty instead of export time', () {
    final entry = BookNote.fromDb({'book_id': 1, 'content': '旧摘录'});
    final rows = const CsvToListConverter().convert(formatNotesCsv([entry]));
    expect(rows[1][3], '原文：【旧摘录】');
    expect(rows[1][7], '');
    expect(rows[1][8], '');
    expect(rows[1][9], '时间未知');
  });
}
