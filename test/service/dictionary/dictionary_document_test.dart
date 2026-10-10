import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/service/dictionary/dictionary_document.dart';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'local_dictionary_test.dart' show mdx;

void main() {
  late Directory temp;
  late LocalDictionaryStore store;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('modu-dict-media-');
    store = LocalDictionaryStore(p.join(temp.path, 'db'));
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('old text-only databases stay readable without migration or HTML',
      () async {
    final main = mdx(temp, definitions: {'sample': '<p>旧词条</p>'});
    await store.importFiles([main], 'Old');
    final id = (await store.list()).single.id;
    final db = sqlite3.open(p.join(store.root, '$id.sqlite'));
    try {
      db.execute('ALTER TABLE entries DROP COLUMN html');
      db.execute('DROP TABLE resources');
    } finally {
      db.dispose();
    }
    final entry = (await store.lookup('sample')).single;
    expect(entry.definition, '旧词条');
    expect(entry.html, isNull);
    expect(await store.resource(id, 'pic.png'), isNull);
  });

  test(
      'MDX raw HTML and MDD image/audio/script resources survive import and redirects',
      () async {
    const markup =
        '<p>释义</p><img src="pic.png"><a href="sound://voice.wav">播放</a><script src="main.js"></script>';
    final main =
        mdx(temp, definitions: {'sample': markup, 'alias': '@@@LINK=sample'});
    final resources = mdx(temp, utf16: true, resources: {
      r'\pic.png': [137, 80, 78, 71],
      r'\voice.wav': [82, 73, 70, 70],
      r'\main.js': utf8.encode('document.body.append("动态释义");'),
    });
    await store.importFiles([main, resources], 'Media');
    final entry = (await store.lookup('alias')).single;
    expect(entry.html, markup);
    expect(entry.definition, contains('释义'));
    expect(await store.resource(entry.dictionaryId!, 'pic.png'),
        [137, 80, 78, 71]);
    expect(await store.resource(entry.dictionaryId!, 'missing.png'), isNull);
    expect(() => dictionaryResourcePath('../secret'),
        throwsA(isA<DictionaryFailure>()));
  });

  test(
      'ZIP preserves nested loose CSS/images; failed resource import is atomic',
      () async {
    final file = mdx(temp, definitions: {'sample': '<img src="img/pic.png">'});
    final zip = Archive()
      ..addFile(ArchiveFile('dict/demo.mdx', File(file).lengthSync(),
          File(file).readAsBytesSync()))
      ..addFile(ArchiveFile('dict/img/pic.png', 4, [1, 2, 3, 4]))
      ..addFile(ArchiveFile('dict/css/main.css', 6, utf8.encode('p{a:b}')));
    final path = File(p.join(temp.path, 'test.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(zip)!);
    await store.importFiles([path.path], 'ZIP');
    final id = (await store.list()).single.id;
    expect(await store.resource(id, 'img/pic.png'), [1, 2, 3, 4]);
    final bad = mdx(temp, utf16: true, resources: {
      '../escape.png': [1]
    });
    await expectLater(store.importFiles([file, bad], 'Bad'),
        throwsA(isA<DictionaryFailure>()));
    expect(await store.list(), hasLength(1));
    expect(await store.resource(id, 'img/pic.png'), [1, 2, 3, 4]);
  });

  test(
      'loopback document isolates requests, CSP, resource ranges and missing media',
      () async {
    final main = mdx(temp, definitions: {
      'sample':
          '<script>document.body.append("dynamic")</script><img src="pic.png">'
    });
    final media = mdx(temp, utf16: true, resources: {
      'pic.png': [1, 2, 3, 4]
    });
    await store.importFiles([main, media], 'Media');
    final document = await DictionaryDocument.open(
        store, (await store.lookup('sample')).single);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await document.close();
    });
    final response = await (await client.getUrl(document.uri)).close();
    final csp = response.headers.value('Content-Security-Policy')!;
    expect(csp, contains('sandbox allow-scripts;'));
    expect(csp, isNot(contains('allow-same-origin')));
    expect(csp, contains("connect-src 'none'"));
    expect(await utf8.decoder.bind(response).join(),
        contains('document.body.append'));
    expect(document.allows(document.uri.replace(fragment: 'part')), true);
    expect(document.allows(Uri.parse('https://example.org/')), false);
    expect(document.allows(document.uri.resolve('pic.png')), false);
    final req = await client.getUrl(document.uri.resolve('pic.png'));
    req.headers.set('Range', 'bytes=1-2');
    final pic = await req.close();
    expect(pic.statusCode, 206);
    expect(await pic.expand((bytes) => bytes).toList(), [2, 3]);
    for (final uri in [
      document.uri.resolve('missing.png'),
      document.uri.resolve('../secret')
    ]) {
      final missing = await (await client.getUrl(uri)).close();
      expect(missing.statusCode, 404);
      await missing.drain<void>();
    }
  });

  test(
      'render document preserves scripts but strips nested browsing and normalizes audio',
      () {
    final doc = dictionaryDocumentHtml(
        '<base href="https://evil.test"><iframe src="file:///secret"></iframe>'
        '<a href="sound://voice.wav">play</a><img src="\\img\\pic.png">'
        '<script>document.body.append("dynamic")</script>');
    expect(doc, contains('<audio controls="" preload="none" src="voice.wav">'));
    expect(doc, contains('src="img/pic.png"'));
    expect(doc, contains('document.body.append'));
    expect(doc, isNot(contains('<base')));
    expect(doc, isNot(contains('<iframe')));
    expect(doc, contains('min-height:0!important'));
    expect(doc, contains('margin:0!important'));
    expect(doc, contains('p{margin-block:.3em}'));
  });
}
