import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:archive/archive.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

List<int> number(int value, [int width = 4]) {
  final b = ByteData(width);
  if (width == 8) {
    b.setUint64(0, value);
  } else {
    b.setUint32(0, value);
  }
  return b.buffer.asUint8List();
}

List<String> star(Directory dir,
    {bool compressed = false,
    bool wide = false,
    bool badOffset = false,
    bool badCount = false,
    bool synonyms = true}) {
  final entries = {'apple': '苹果\n一种水果', '革命': '社会的根本变革'};
  final index = BytesBuilder(), data = BytesBuilder();
  for (final e in entries.entries) {
    final bytes = utf8.encode(e.value);
    index.add([
      ...utf8.encode(e.key),
      0,
      ...number(badOffset ? 999999 : data.length, wide ? 8 : 4),
      ...number(bytes.length)
    ]);
    data.add(bytes);
  }
  final idx = index.takeBytes(), dict = data.takeBytes();
  final ifo = File(p.join(dir.path, 'demo.ifo'))
    ..writeAsStringSync(
        "StarDict's dict ifo file\nversion=${wide ? '3.0.0' : '2.4.2'}\nbookname=Demo\nwordcount=${badCount ? 5 : 2}\nidxfilesize=${idx.length}\nsametypesequence=m\n${wide ? 'idxoffsetbits=64\n' : ''}${synonyms ? 'synwordcount=1\n' : ''}");
  final i = File(p.join(dir.path, compressed ? 'demo.idx.gz' : 'demo.idx'))
    ..writeAsBytesSync(compressed ? gzip.encode(idx) : idx);
  final d = File(p.join(dir.path, compressed ? 'demo.dict.dz' : 'demo.dict'))
    ..writeAsBytesSync(compressed ? gzip.encode(dict) : dict);
  final paths = [ifo.path, i.path, d.path];
  if (synonyms) {
    paths.add((File(p.join(dir.path, 'demo.syn'))
          ..writeAsBytesSync([...utf8.encode('apples'), 0, ...number(0)]))
        .path);
  }
  return paths;
}

// Small, original format fixtures, not redistributed commercial dictionary data.
String mdx(Directory dir,
    {int version = 2,
    bool compressed = true,
    bool utf16 = false,
    String encrypted = 'No'}) {
  final entries = {
    'apple': '<p>苹果</p><script>bad()</script><p>水果</p>',
    'apples': '@@@LINK=apple',
    'cycle': '@@@LINK=cycle'
  };
  List<int> encode(String s) =>
      utf16 ? const Utf16Encoder().encodeUtf16Le(s) : utf8.encode(s);
  final width = version < 2 ? 4 : 8;
  List<int> n(int v) => number(v, width);
  List<int> block(List<int> b, {bool? zip}) => [
        (zip ?? compressed) ? 2 : 0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        ...((zip ?? compressed) ? zlib.encode(b) : b)
      ];
  final keys = BytesBuilder(), records = BytesBuilder();
  for (final e in entries.entries) {
    keys.add([...n(records.length), ...encode(e.key), ...encode('\u0000')]);
    records.add([...encode(e.value), ...encode('\u0000')]);
  }
  final keyData = keys.takeBytes(), recordData = records.takeBytes();
  final keyBlock = block(keyData), recordBlock = block(recordData);
  final info = <int>[
    ...n(entries.length),
    ...(version < 2
        ? [0, 0]
        : [0, 0, ...encode('\u0000'), 0, 0, ...encode('\u0000')]),
    ...n(keyBlock.length),
    ...n(keyData.length)
  ];
  final keyInfo = version < 2 ? info : block(info, zip: true);
  final header = const Utf16Encoder().encodeUtf16Le(
      '<Dictionary GeneratedByEngineVersion="$version.0" Encoding="${utf16 ? 'UTF-16' : 'UTF-8'}" Encrypted="$encrypted"/>\u0000');
  final bytes = <int>[
    ...number(header.length),
    ...header,
    ...number(0),
    ...n(1),
    ...n(entries.length),
    if (version >= 2) ...n(info.length),
    ...n(keyInfo.length),
    ...n(keyBlock.length),
    if (version >= 2) ...number(0),
    ...keyInfo,
    ...keyBlock,
    ...n(1),
    ...n(entries.length),
    ...n(width * 2),
    ...n(recordBlock.length),
    ...n(recordBlock.length),
    ...n(recordData.length),
    ...recordBlock
  ];
  return (File(p.join(dir.path, 'demo.mdx'))..writeAsBytesSync(bytes)).path;
}

void main() {
  late Directory temp, sources;
  late LocalDictionaryStore store;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('modu-dictionary-test-');
    sources = Directory(p.join(temp.path, 'sources'))..createSync();
    store = LocalDictionaryStore(p.join(temp.path, 'dictionaries'));
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test(
      'empty by default; names, enablement, aliases and Chinese survive reload',
      () async {
    expect(await store.list(), isEmpty);
    final files = star(sources);
    await store.importFiles(files, '我的词典');
    expect((await store.lookup(' APPLE ')).single.definition, contains('苹果'));
    expect((await store.lookup('apples')).single.definition, contains('苹果'));
    expect((await store.lookup('革命')).single.word, '革命');
    expect(await store.lookup('app'), isEmpty);
    expect(await store.lookup("' OR 1=1 --"), isEmpty);
    final item = (await store.list()).single;
    expect(item.count, 3);
    await store.rename(item.id, '重命名');
    await store.enable(item.id, false);
    final reloaded = LocalDictionaryStore(store.root);
    expect((await reloaded.list()).single.name, '重命名');
    expect(await reloaded.lookup('apple'), isEmpty);
    await reloaded.enable(item.id, true);
    expect(await reloaded.lookup('apple'), hasLength(1));
    await reloaded.delete(item.id);
    expect(await reloaded.list(), isEmpty);
    expect(files.every((f) => File(f).existsSync()), isTrue);
  });
  for (final wide in [false, true]) {
    test('StarDict gzip/dictzip with ${wide ? 64 : 32}-bit offsets', () async {
      await store.importFiles(
          star(sources, compressed: true, wide: wide), 'Compressed');
      expect((await store.lookup('革命')).single.definition, '社会的根本变革');
    });
  }
  for (final version in [1, 2]) {
    for (final utf16 in [false, true]) {
      test(
          'MDX v$version ${utf16 ? 'UTF16' : 'UTF8'} lookup, links and safe text',
          () async {
        await store.importFiles([
          mdx(sources, version: version, utf16: utf16, compressed: version == 2)
        ], 'MDX');
        final body = (await store.lookup('apples')).single.definition;
        expect(body, contains('苹果'));
        expect(body, contains('水果'));
        expect(body, isNot(contains('bad')));
        expect(await store.lookup('cycle'), isEmpty);
      });
    }
  }
  test('ZIP dictionary import, CRC and nested paths', () async {
    final files = star(sources, compressed: true);
    final archive = Archive();
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      archive
          .addFile(ArchiveFile('demo/${p.basename(f)}', bytes.length, bytes));
    }
    final zip = File(p.join(temp.path, 'dictionary.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(archive)!);
    await store.importFiles([zip.path], 'ZIP');
    expect(await store.lookup('apple'), hasLength(1));
  });
  for (final condition in [
    'offset',
    'count',
    'companions',
    'mdx3',
    'encrypted',
    'broken'
  ]) {
    test('reject $condition atomically, preserving existing dictionaries',
        () async {
      await store.importFiles(star(sources), 'Existing');
      final files = switch (condition) {
        'offset' => star(sources, badOffset: true),
        'count' => star(sources, badCount: true),
        'companions' => [star(sources).first],
        'mdx3' => [mdx(sources, version: 3)],
        'encrypted' => [mdx(sources, encrypted: 'Yes')],
        _ => [
            (File(p.join(sources.path, 'broken.mdx'))
                  ..writeAsStringSync('broken'))
                .path
          ],
      };
      await expectLater(
          store.importFiles(files, 'Bad'), throwsA(isA<DictionaryFailure>()));
      expect(await store.list(), hasLength(1));
      expect(await store.lookup('apple'), hasLength(1));
      expect(Directory(store.root).listSync().whereType<Directory>(), isEmpty);
    });
  }
  test('ZIP traversal rejected without writing outside staging', () async {
    final archive = Archive()..addFile(ArchiveFile('../escape.ifo', 1, [65]));
    final zip = File(p.join(temp.path, 'bad.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(archive)!);
    await expectLater(store.importFiles([zip.path], 'Bad'),
        throwsA(isA<DictionaryFailure>()));
    expect(await store.list(), isEmpty);
    expect(File(p.join(store.root, 'escape.ifo')).existsSync(), isFalse);
  });
  test('cannot delete arbitrary source paths or use empty names', () async {
    await expectLater(
        store.delete('../sources'), throwsA(isA<DictionaryFailure>()));
    await expectLater(store.importFiles(star(sources), ' '),
        throwsA(isA<DictionaryFailure>()));
    expect(sources.existsSync(), isTrue);
  });
  test('ZIP CRC mismatch is rejected, not published', () async {
    final files = star(sources);
    final archive = Archive();
    for (final file in files) {
      final bytes = File(file).readAsBytesSync();
      archive.addFile(ArchiveFile(p.basename(file), bytes.length, bytes));
    }
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
    final view = ByteData.sublistView(bytes);
    for (var at = 0; at + 20 < bytes.length; at++) {
      if (view.getUint32(at, Endian.little) == 0x02014b50) {
        view.setUint32(at + 16, 0, Endian.little);
        break;
      }
    }
    final zip = File(p.join(temp.path, 'crc.zip'))..writeAsBytesSync(bytes);
    await expectLater(store.importFiles([zip.path], 'Bad CRC'),
        throwsA(isA<DictionaryFailure>()));
    expect(await store.list(), isEmpty);
  });
  test('multiple dictionaries contribute independent results', () async {
    await store.importFiles(star(sources), 'Star');
    await store.importFiles([mdx(sources)], 'MDX');
    expect((await store.lookup('apple')).map((e) => e.dictionary),
        ['MDX', 'Star']);
  });
  test('typed StarDict fields preserve phonetics, strip markup, skip binary',
      () {
    expect(
        starDictDefinition(
            Uint8List.fromList(
                [...utf8.encode('/a/'), 0, ...utf8.encode('<b>苹果</b>')]),
            'th'),
        '/a/\n苹果');
    expect(
        starDictDefinition(
            Uint8List.fromList(
                [87, ...number(3), 1, 2, 3, 109, ...utf8.encode('word'), 0]),
            null),
        'word');
    expect(() => starDictDefinition(Uint8List.fromList([109, 65]), null),
        throwsA(isA<DictionaryFailure>()));
    expect(
        dictionaryPlainText(
            '<style>huge</style><p>a</p><iframe>bad</iframe><img src="https://example.org/x"><p>b</p>'),
        'a\n\nb');
  });
}
