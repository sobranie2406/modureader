import 'dart:async';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/service/notes/export_notes.dart';
import 'package:anx_reader/service/notes/reading_link.dart';
import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as markdown;

const hash = '0123456789abcdef0123456789abcdef';
const cfi = 'epubcfi(/6/4[chapter]!/4/2/1:8)';
Book book() => Book.mock().copyWith(
    title: '书名 &【测试】',
    author: '作者',
    md5: hash,
    createTime: DateTime.utc(2026, 9, 28),
    filePath: '/private/books/do-not-export.epub');
BookNote note() => BookNote(
    bookId: 1,
    content: '第一段\n第二行\n\n第二段',
    cfi: cfi,
    chapter: '第一章',
    type: 'highlight',
    color: 'ffff00',
    readerNote: '我的笔记',
    createTime: DateTime(2026, 9, 22, 10),
    updateTime: DateTime(2026, 9, 23, 11, 5));

Future<void> drain() => Future<void>.delayed(Duration.zero);

void main() {
  test('Unicode, reserved URL characters and range CFI round-trip', () {
    final original = book()..title = '书名?# /&【】中文';
    const range = 'epubcfi(/6/4[part^,one]!/4/2,/1:0,/1:12)';
    final raw = ReadingLink.forBook(original, range)!;
    final decoded = ReadingLink.parse(raw);
    expect(decoded.title, original.title);
    expect(decoded.author, original.author);
    expect(decoded.cfi, range);
    expect(decoded.md5, hash);
    expect(raw, isNot(contains('/private')));
    expect(Uri.parse(raw).queryParameters.containsKey('id'), false);
  });

  test('Same file on another device matches despite local ID/title changes',
      () {
    final link = ReadingLink.parse(ReadingLink.forBook(book(), cfi)!);
    final remote =
        book().copyWith(id: 87, title: '改名', md5: hash.toUpperCase());
    expect(link.matches([remote]), [remote]);
  });

  test('Deleted books and replaced editions never match by title alone', () {
    final link = ReadingLink.parse(ReadingLink.forBook(book(), cfi)!);
    expect(
        link.matches([
          book().copyWith(isDeleted: true),
          book().copyWith(md5: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
        ]),
        isEmpty);
  });

  test('Hashless legacy records require title, author and creation time', () {
    final original = book()..md5 = null;
    final link = ReadingLink.parse(ReadingLink.forBook(original, cfi)!);
    final same = original.copyWith(id: 999);
    expect(link.md5, isNull);
    expect(
        link.matches([
          same,
          same.copyWith(title: '别的书'),
          same.copyWith(author: '另一位作者'),
          same.copyWith(createTime: DateTime(2025))
        ]),
        [same]);
  });

  test('Duplicate copies remain available for explicit selection', () {
    final link = ReadingLink.parse(ReadingLink.forBook(book(), cfi)!);
    expect(link.matches([book(), book().copyWith(id: 2)]), hasLength(2));
  });

  test('Reject malformed or foreign links', () {
    final valid = ReadingLink.forBook(book(), cfi)!;
    for (final raw in [
      valid.replaceFirst('modu:', 'https:'),
      valid.replaceFirst('read?', 'read/path?'),
      valid.replaceFirst('read?', 'read:90?'),
      valid.replaceFirst('read?', 'user@read?'),
      '$valid#fragment',
      '$valid&v=1',
      valid.replaceFirst('v=1', 'v=2'),
      valid.replaceFirst(hash, 'not-a-hash'),
      'modu://read',
      '${valid}x${'a' * 40000}'
    ]) {
      expect(() => ReadingLink.parse(raw), throwsFormatException);
    }
  });

  test('Do not generate dead links for missing or excessive CFI', () {
    for (final value in [
      '',
      '/6/4',
      'javascript:alert(1)',
      'epubcfi(\n)',
      'epubcfi(${'a' * 8192})'
    ]) {
      expect(ReadingLink.forBook(book(), value), isNull);
    }
  });

  test('Every Markdown excerpt paragraph is linked; notes/time preserved', () {
    final raw = ReadingLink.forBook(book(), cfi)!;
    final exported = formatNotesMarkdown([note()], book: book());
    expect(exported, contains('原文：【['));
    expect(exported, contains('<mark>我的笔记</mark>'));
    expect(exported, contains('最后修改：2026年9月23日11点05分'));
    expect('【'.allMatches(exported).length, 1);
    expect('】'.allMatches(exported).length, 1);
    final html = markdown.markdownToHtml(exported);
    expect('<a href='.allMatches(html).length, 3);
    expect(html, contains('href="$raw"'));
    expect(html, contains('返回默读原文</a>'));
  });

  test('Literal excerpt cannot inject new Markdown links or scripts', () {
    final entry = note()
      ..content = '[evil](javascript:alert(1)) <script>x</script>';
    final html =
        markdown.markdownToHtml(formatNotesMarkdown([entry], book: book()));
    expect(html, isNot(contains('href="javascript:')));
    expect(html, isNot(contains('<script>')));
    expect('<a href='.allMatches(html).length, 2);
  });

  test('Note-only entries still have a return link', () {
    final exported = formatNotesMarkdown([note()..content = ''], book: book());
    expect(exported, contains('[返回默读原文](<modu://read?'));
    expect(exported, isNot(contains('原文：')));
  });

  test('Legacy note without CFI retains text without fake hyperlinks', () {
    final exported = formatNotesMarkdown([note()..cfi = ''], book: book());
    expect(exported, contains('第一段'));
    expect(exported, isNot(contains('modu://')));
  });

  test('Plain text/copy exports include labelled links and note timestamps',
      () {
    final exported = formatNotesText([note()], book: book());
    expect(exported, contains('原文：【第一段'));
    expect(exported, contains('返回原文: ${ReadingLink.forBook(book(), cfi)}'));
    expect(exported, contains('2026年9月23日11点05分'));
  });

  test('CSV stores full link in a separate column with exact round-trip', () {
    final rows = const CsvToListConverter()
        .convert(formatNotesCsv([note()], book: book()));
    expect(rows.first.last, 'Open in Modu');
    expect(rows[1].last, ReadingLink.forBook(book(), cfi));
    expect(ReadingLink.parse(rows[1].last as String).cfi, cfi);
  });

  test('Cold-start links wait for a ready handler', () async {
    final inbox = ReadingLinkInbox();
    final seen = <String>[];
    inbox.add('modu://read?one');
    await drain();
    expect(seen, isEmpty);
    inbox.attach((raw) async {
      seen.add(raw);
    });
    await drain();
    expect(seen, ['modu://read?one']);
  });

  test('Busy delivery is serial, deduplicated and latest pending wins',
      () async {
    final inbox = ReadingLinkInbox();
    final seen = <String>[];
    final busy = Completer<void>();
    inbox.attach((raw) async {
      seen.add(raw);
      if (seen.length == 1) await busy.future;
    });
    inbox.add('modu://read?one');
    inbox.add('modu://read?one');
    inbox.add('modu://read?two');
    inbox.add('modu://read?three');
    expect(seen, ['modu://read?one']);
    busy.complete();
    await drain();
    expect(seen, ['modu://read?one', 'modu://read?three']);
  });

  test('A repeated user click after delivery opens again', () async {
    final inbox = ReadingLinkInbox();
    int count = 0;
    inbox.attach((_) async {
      count++;
    });
    inbox.add('modu://read?one');
    await drain();
    inbox.add('modu://read?one');
    await drain();
    expect(count, 2);
  });

  test('Settings links and arbitrary URLs do not reach reading navigation',
      () async {
    final inbox = ReadingLinkInbox();
    final seen = <String>[];
    inbox.attach((raw) async {
      seen.add(raw);
    });
    for (final raw in [
      'modu:settings-data',
      'https://example.com',
      'file:///test'
    ]) {
      inbox.add(raw);
    }
    await drain();
    expect(seen, isEmpty);
  });

  test('Failure and detach do not block subsequent links', () async {
    final inbox = ReadingLinkInbox();
    inbox.attach((_) async {
      throw StateError('failed');
    });
    inbox.add('modu://read?one');
    await drain();
    inbox.detach();
    inbox.add('modu://read?two');
    final seen = <String>[];
    inbox.attach((raw) async {
      seen.add(raw);
    });
    await drain();
    expect(seen, ['modu://read?two']);
  });
}
