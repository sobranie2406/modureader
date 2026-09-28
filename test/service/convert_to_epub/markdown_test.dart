import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/book_formats.dart';
import 'package:anx_reader/service/convert_to_epub/markdown/convert_from_markdown.dart';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

Archive book(String source, {String title = '示例'}) => ZipDecoder()
    .decodeBytes(markdownToEpub(source, fallbackTitle: title), verify: true);
String text(Archive archive, String name) =>
    utf8.decode(archive.findFile(name)!.content as List<int>);
XmlDocument xml(Archive archive, String name) =>
    XmlDocument.parse(text(archive, name));
List<String> chapters(Archive archive) => archive.files
    .where((f) => f.name.startsWith('OEBPS/xhtml/'))
    .map((f) => f.name)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MD and Markdown are supported shared book formats', () {
    expect(allowBookExtensions, containsAll(['md', 'markdown', 'txt', 'epub']));
    expect(isMarkdownExtension('MARKDOWN'), isTrue);
    expect(isMarkdownExtension('MD'), isTrue);
    expect(isMarkdownExtension('txt'), isFalse);
  });

  test('EPUB has valid XML, required metadata, ordered spine and navigation',
      () {
    final archive = book('# 书名 & 内容\n\n开篇。\n\n## 第一章\n\n正文\n\n### 小节\n\n结束');
    expect(archive.files.first.name, 'mimetype');
    expect(text(archive, 'mimetype'), 'application/epub+zip');
    for (final file in archive.files
        .where((f) => RegExp(r'\.(xml|opf|xhtml)$').hasMatch(f.name))) {
      expect(() => xml(archive, file.name), returnsNormally, reason: file.name);
    }
    final opf = xml(archive, 'OEBPS/content.opf');
    expect(opf.findAllElements('dc:title').single.innerText, '书名 & 内容');
    expect(opf.findAllElements('itemref').map((e) => e.getAttribute('idref')),
        ['c0', 'c1', 'c2']);
    final nav = xml(archive, 'OEBPS/nav.xhtml');
    expect(nav.findAllElements('a').map((e) => e.innerText),
        ['书名 & 内容', '第一章', '小节']);
    expect(nav.findAllElements('ol'), hasLength(3));
    for (final item in opf.findAllElements('item')) {
      expect(archive.findFile('OEBPS/${item.getAttribute('href')}'), isNotNull);
    }
  });

  test('renders GFM tables, code, quotes, lists and emphasis', () {
    final archive = book('''# 标题

**粗体** *斜体* ~~删除~~

> 引用

- 条目
- 第二项

3. 编号

| 左列 | 右列 |
| :--- | ---: |
| 一 | 二 |

```html
<script>只作为代码</script>
# 不是目录
```
''');
    final chapter = xml(archive, chapters(archive).single);
    for (final tag in [
      'strong',
      'em',
      'del',
      'blockquote',
      'ul',
      'ol',
      'table',
      'pre',
      'code'
    ]) {
      expect(chapter.findAllElements(tag), isNotEmpty, reason: tag);
    }
    expect(chapter.findAllElements('ol').single.getAttribute('start'), '3');
    expect(chapter.findAllElements('code').single.innerText,
        contains('<script>只作为代码</script>'));
    expect(chapter.findAllElements('script'), isEmpty);
  });

  test('setext headings, Unicode, BOM, CRLF and introductory text survive', () {
    final archive = book(
        '\uFEFF前言\r\n\r\n标题\r\n====\r\n\r\n文字 café 😀\r\n\r\n小节\r\n----\r\n\r\n完');
    expect(chapters(archive), hasLength(3));
    expect(xml(archive, chapters(archive)[1]).innerText, contains('café 😀'));
    expect(xml(archive, chapters(archive).first).innerText, contains('前言'));
  });

  test(
      'heading fragment links cross chapter boundaries and duplicates are unique',
      () {
    final archive = book(
        '# Start\n\n[go](#next) [again](#next-2)\n\n## Next\n\nfirst\n\n## Next\n\nsecond');
    final first = xml(archive, chapters(archive).first);
    expect(first.findAllElements('a').map((e) => e.getAttribute('href')),
        ['1.xhtml#next', '2.xhtml#next-2']);
    final ids = chapters(archive)
        .expand(
            (name) => xml(archive, name).descendants.whereType<XmlElement>())
        .map((e) => e.getAttribute('id'))
        .whereType<String>()
        .toList();
    expect(ids.toSet().length, ids.length);
  });

  test('reference links defined later still resolve after chapter splitting',
      () {
    final archive = book(
        '# One\n\n[reference][book]\n\n# Two\n\n[book]: https://example.com');
    expect(
        xml(archive, chapters(archive).first)
            .findAllElements('a')
            .single
            .getAttribute('href'),
        'https://example.com');
  });

  test('raw HTML cannot inject scripts, frames, styles or dangerous links', () {
    final archive = book('''# Safe

<script>alert(1)</script>
<iframe src="https://tracker.invalid"></iframe>
<style>body{display:none}</style>

<p onclick="alert(1)" style="display:none">正文 <a href="javascript:alert(1)">危险</a><a href="file:///secret">本机</a><a href="modu:settings">设置</a></p>

[safe](https://example.com) [email](mailto:test@example.com)
''');
    final content = xml(archive, chapters(archive).single);
    expect(content.innerText, contains('正文'));
    for (final e in content.descendants.whereType<XmlElement>()) {
      expect(['script', 'iframe', 'style'], isNot(contains(e.name.local)));
      expect(e.attributes.any((a) => a.name.local.startsWith('on')), isFalse);
      final href = e.getAttribute('href');
      if (href != null) {
        expect(href, isNot(matches(r'^(javascript|file|modu):')));
      }
    }
  });

  test('external and local images do not trigger network or local-file access',
      () {
    final archive = book(
        '![远程](https://example.com/image.jpg)\n\n![本地](../../secret.png)\n\n![本机](file:///private/image.png)');
    final content = xml(archive, chapters(archive).single);
    expect(content.findAllElements('img'), isEmpty);
    expect(content.innerText, contains('[本地]'));
    expect(content.findAllElements('a').single.getAttribute('href'),
        'https://example.com/image.jpg');
  });

  test('embedded raster images are packaged and declared in manifest', () {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a6VQAAAAASUVORK5CYII=';
    final archive = book('![像素](data:image/png;base64,$png)');
    expect(archive.findFile('OEBPS/images/0.png')!.content, base64.decode(png));
    expect(
        xml(archive, chapters(archive).single)
            .findAllElements('img')
            .single
            .getAttribute('src'),
        '../images/0.png');
    expect(
        xml(archive, 'OEBPS/content.opf')
            .findAllElements('item')
            .any((e) => e.getAttribute('media-type') == 'image/png'),
        isTrue);
  });

  test(
      'no heading falls back to filename and long prose splits at block boundary',
      () {
    final archive = book('${'正文。' * 7000}\n\n最后一段', title: '无标题 & 名称');
    expect(chapters(archive), hasLength(2));
    expect(
        xml(archive, 'OEBPS/content.opf')
            .findAllElements('dc:title')
            .single
            .innerText,
        '无标题 & 名称');
    expect(xml(archive, chapters(archive).last).innerText, contains('最后一段'));
  });

  test('empty or script-only input is rejected', () {
    expect(() => book(' \n\t'), throwsFormatException);
    expect(() => book('<script>hidden</script>'), throwsFormatException);
  });

  test(
      'same title conversions use distinct paths and do not modify input files',
      () async {
    final dir = await Directory.systemTemp.createTemp('modu-markdown-test-');
    addTearDown(() => dir.delete(recursive: true));
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => dir.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final input =
        await File('${dir.path}/book.MD').writeAsString('# ../../同名\n\n正文');
    final outputs = await Future.wait(
        [convertFromMarkdown(input), convertFromMarkdown(input)]);
    expect(outputs[0].path, isNot(outputs[1].path));
    expect(await input.readAsString(), '# ../../同名\n\n正文');
    for (final output in outputs) {
      expect(output.parent.path, dir.path);
      expect(
          ZipDecoder()
              .decodeBytes(await output.readAsBytes())
              .findFile('OEBPS/content.opf'),
          isNotNull);
    }
  });
}
