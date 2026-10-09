import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/service/book_formats.dart';
import 'package:anx_reader/service/convert_to_epub/umd/convert_from_umd.dart';
import 'package:anx_reader/service/sync/converted_book_checksum.dart';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

List<int> word(int n) =>
    (ByteData(4)..setUint32(0, n, Endian.little)).buffer.asUint8List();
List<int> utf16(String s) => [
      for (final c in s.codeUnits) ...[c & 255, c >> 8]
    ];
List<int> field(int id, List<int> data) =>
    [0x23, id & 255, id >> 8, 0, data.length + 5, ...data];
List<int> block(int id, List<int> data) =>
    [0x24, ...word(id), ...word(data.length + 9), ...data];
final cover = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3ioAAAAASUVORK5CYII=');
const bodies = [
  '开篇😀\u2029<script>原文</script>\u2029',
  '**非 Markdown**\u2029完。'
];

Uint8List fixture(
    {int type = 1,
    int? length,
    List<int>? offsets,
    List<int>? ids,
    List<int>? content,
    bool brokenDeflate = false}) {
  final text = content ?? utf16(bodies.join());
  final data = <int>[
    ...word(0xde9a9b89),
    ...field(1, [type, 0, 0]),
    ...field(2, utf16('测试 & 书')),
    ...field(3, utf16('作者')),
    ...field(11, word(length ?? text.length)),
    ...field(0x83, word(100)),
    ...block(100, [
      for (final n in offsets ?? [0, utf16(bodies.first).length]) ...word(n)
    ]),
    ...field(0x84, word(101)),
    ...block(101, [
      for (final s in ['一', '二']) ...[utf16(s).length, ...utf16(s)]
    ]),
    // Split on an odd byte: decode only after all chunks have been joined.
    ...block(201, brokenDeflate ? [0, 1, 2] : zlib.encode(text.sublist(0, 3))),
    ...block(202, zlib.encode(text.sublist(3))),
    ...field(0x81, word(102)),
    ...block(102, [
      for (final id in ids ?? [202, 201]) ...word(id)
    ]),
    ...field(0x82, [1, ...word(103)]),
    ...block(103, cover),
  ];
  data.addAll(field(12, word(data.length + 9)));
  data.addAll(field(0x87, [0, 0]));
  data.addAll(field(0x87, [1, 0]));
  return Uint8List.fromList(data);
}

XmlDocument xml(Archive a, String name) =>
    XmlDocument.parse(utf8.decode(a.findFile(name)!.content as List<int>));
Archive convert(Uint8List bytes) => ZipDecoder()
    .decodeBytes(umdToEpub(bytes, fallbackTitle: 'Fallback'), verify: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('UMD is accepted by the shared import allowlist', () {
    expect(allowBookExtensions, contains('umd'));
  });
  test('text, chapter order, metadata, cover and literal markup survive', () {
    final a = convert(fixture());
    for (final f in a.files
        .where((f) => RegExp(r'\.(xml|opf|xhtml)$').hasMatch(f.name))) {
      xml(a, f.name);
    }
    final opf = xml(a, 'OEBPS/content.opf');
    expect(opf.findAllElements('dc:title').single.innerText, '测试 & 书');
    expect(opf.findAllElements('dc:creator').single.innerText, '作者');
    expect(opf.findAllElements('itemref').map((e) => e.getAttribute('idref')),
        ['c0', 'c1']);
    final image = opf
        .findAllElements('item')
        .singleWhere((e) => e.getAttribute('properties') == 'cover-image');
    expect(a.findFile('OEBPS/${image.getAttribute('href')}')!.content, cover);
    for (var i = 0; i < bodies.length; i++) {
      final chapter = xml(a, 'OEBPS/xhtml/$i.xhtml');
      expect(chapter.findAllElements('p').map((e) => e.innerText).join('\n'),
          bodies[i].replaceAll('\u2029', '\n'));
      expect(chapter.findAllElements('script'), isEmpty);
      expect(chapter.findAllElements('strong'), isEmpty);
    }
  });
  test('rejects comic UMD with an explicit explanation', () {
    expect(
        () => convert(fixture(type: 2)),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('image/comic'))));
  });
  test('accepts only zero-filled final 32 KiB padding', () {
    final text = utf16(bodies.join());
    final padded = Uint8List(32768)..setAll(0, text);
    final a = convert(fixture(content: padded, length: text.length));
    expect(
        xml(a, 'OEBPS/xhtml/1.xhtml')
            .findAllElements('p')
            .map((e) => e.innerText)
            .join('\n'),
        bodies.last.replaceAll('\u2029', '\n'));
    padded[text.length] = 1;
    expect(() => convert(fixture(content: padded, length: text.length)),
        throwsFormatException);
  });
  final invalid = <String, Uint8List Function()>{
    'bad magic': () => fixture()..[0] = 0,
    'truncated block': () => Uint8List.fromList(fixture().sublist(0, 100)),
    'missing reference': () => fixture(ids: [999, 201]),
    'repeated content id': () => fixture(ids: [201, 201]),
    'duplicate block': () => Uint8List.fromList([
          ...fixture(),
          ...block(201, [0])
        ]),
    'duplicate metadata': () =>
        Uint8List.fromList([...fixture(), ...field(2, utf16('Other'))]),
    'chapter count mismatch': () => fixture(offsets: [0]),
    'chapter byte alignment': () => fixture(offsets: [0, 3]),
    'chapter beyond text': () => fixture(offsets: [0, 10000]),
    'invalid UTF16': () => fixture(content: [0, 0xd8, 0, 0], offsets: [0, 4]),
    'truncated decoded text': () => fixture(length: 10000),
    'inflation beyond declared size': () => fixture(length: 4, offsets: [0, 2]),
    'text memory limit': () => fixture(length: 34 * 1024 * 1024),
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key}',
        () => expect(() => convert(entry.value()), throwsFormatException));
  }
  test(
      'rejects invalid deflate',
      () => expect(() => convert(fixture(brokenDeflate: true)),
          throwsA(isA<Exception>())));

  test('parallel imports preserve source and downloadable format provenance',
      () async {
    final dir = await Directory.systemTemp.createTemp('modu-umd-test-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => dir.path);
    try {
      final source = await File('${dir.path}/test.umd').writeAsBytes(fixture());
      final outputs =
          await Future.wait([convertFromUmd(source), convertFromUmd(source)]);
      expect(outputs[0].path, isNot(outputs[1].path));
      expect(await source.readAsBytes(), fixture());
      for (final output in outputs) {
        expect(await convertedBookSourceFormat(output.path), 'UMD');
      }
    } finally {
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null);
      await dir.delete(recursive: true);
    }
  });

  // Local opt-in only: never commit or print the user's book contents.
  const sample = String.fromEnvironment('UMD_SAMPLE');
  test('real local UMD: every original text byte survives conversion',
      () async {
    final source = await File(sample).readAsBytes();
    final a = convert(source);
    final view = ByteData.sublistView(source);
    final chunks = <List<int>>[];
    var chapters = 0;
    var declaredTextLength = 0;
    for (var p = 4; p < source.length;) {
      if (source[p] == 0x23) {
        if (view.getUint16(p + 1, Endian.little) == 11) {
          declaredTextLength = view.getUint32(p + 5, Endian.little);
        }
        p += source[p + 4];
      } else {
        final size = view.getUint32(p + 5, Endian.little);
        final data = source.sublist(p + 9, p + size);
        // Independent sample oracle: discover valid deflate blocks directly.
        if (data.length > 2 && data[0] == 0x78) {
          try {
            chunks.add(zlib.decode(data));
          } on Exception {/* non-text block */}
        }
        p += size;
      }
    }
    final original = Uint8List.fromList(chunks.expand((e) => e).toList());
    expect(original.skip(declaredTextLength).every((b) => b == 0), isTrue);
    final units = ByteData.sublistView(original, 0, declaredTextLength);
    final expected = String.fromCharCodes([
      for (var i = 0; i < declaredTextLength; i += 2)
        units.getUint16(i, Endian.little)
    ])
        .replaceAll('\u2029', '\n')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final actual = StringBuffer();
    for (final f in a.files.where((f) => f.name.startsWith('OEBPS/xhtml/'))) {
      chapters++;
      actual.write(xml(a, f.name)
          .findAllElements('p')
          .map((p) => p.innerText)
          .join('\n'));
    }
    // A failure must not dump private text in test logs.
    expect(actual.toString() == expected, isTrue,
        reason: 'Exact original body comparison');
    expect(await File(sample).readAsBytes(), source);
    final opf = xml(a, 'OEBPS/content.opf');
    expect(
        opf
            .findAllElements('item')
            .where((e) => e.getAttribute('properties') == 'cover-image'),
        hasLength(1));
    // ignore: avoid_print
    print(
        'UMD sample verified: input=${source.length} bytes, chapters=$chapters, text=${expected.length} UTF16 units; cover retained; body exact.');
  }, skip: sample.isEmpty);
}
