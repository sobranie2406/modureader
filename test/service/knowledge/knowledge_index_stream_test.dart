import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/service/knowledge/knowledge_index_stream.dart';
import 'package:anx_reader/service/sync/knowledge_index_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File input;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-index-stream-');
    input = File('${root.path}/index.json');
  });
  tearDown(() async => root.delete(recursive: true));

  Map<String, dynamic> fixture({String text = '中文'}) => {
        'bookId': '7',
        'contentHash': 'content',
        'sourceFingerprint': 'source',
        'chunks': [
          {
            'id': '7:0',
            'bookId': '7',
            'chapterId': '1',
            'text': text,
            'startOffset': 0
          }
        ],
        'vectors': [
          {
            'chunkId': '7:0',
            'vector': [0.5, 0.8]
          }
        ],
        'embeddingMode': 'local',
        'embeddingModelId': 'fixture',
        'embeddingDimensions': 2,
      };
  Future<Map<String, dynamic>> export() => transferKnowledgeIndex(
      input: input,
      output: File('${root.path}/out.json'),
      bookSha: 'hash',
      localId: '7',
      fingerprint: 'source',
      importing: false);

  test('compact and formatted legacy JSON, UTF-8 and escaped chunk boundaries',
      () async {
    final text = ('中文\n"\\[]{}😀\t' * 10000);
    final raw = fixture(text: text);
    for (final encoder in [
      const JsonEncoder(),
      const JsonEncoder.withIndent('  ')
    ]) {
      await input.writeAsString(encoder.convert(raw));
      expect((await export())['vectorCount'], 1);
      final loaded =
          await FileKnowledgeIndexStore(input, sourceFingerprint: 'source')
              .load('7');
      expect(loaded!.chunks.single.text, text);
      expect(loaded.vectors.single.vector, [0.5, 0.8]);
      final payload =
          jsonDecode(await File('${root.path}/out.json').readAsString());
      expect(payload['index']['chunks'][0]['text'], text);
      expect(payload['index']['sourceFingerprint'], isNull);
    }
  });
  test('streaming parser rejects truncation, duplicate keys and trailing data',
      () async {
    for (final raw in [
      '{"chunks":[}',
      '{"chunks":[{},]}',
      '{"chunks":[],}',
      '{"bookId":"7","bookId":"8"}',
      '{"chunks":[],"chunks":[]}',
      '{"chunks":[{"text":"unfinished}',
      '{} true',
      '{"x":NaN}',
    ]) {
      await input.writeAsString(raw);
      await expectLater(
          KnowledgeJsonReader(input).read().toList(), throwsFormatException,
          reason: raw);
    }
  });
  test('record, nesting and file size limits remain enforced', () async {
    await input.writeAsString(
        jsonEncode({'x': 'x' * (maxKnowledgeRecordCharacters + 1)}));
    await expectLater(
        KnowledgeJsonReader(input).read().drain<void>(), throwsFormatException);
    await input.writeAsString('{"x":${'[' * 33}0${']' * 33}}');
    await expectLater(
        KnowledgeJsonReader(input).read().drain<void>(), throwsFormatException);
    final file = await input.open(mode: FileMode.write);
    await file.truncate(maxKnowledgeIndexBytes + 1);
    await file.close();
    await expectLater(
        KnowledgeJsonReader(input).read().drain<void>(), throwsFormatException);
  });
  test('records cannot bypass identities, completeness or vector metadata',
      () async {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (v) => v['chunks'][0]['bookId'] = 'other',
      (v) => v['chunks'][0]['startOffset'] = -1,
      (v) => v['chunks'].add(v['chunks'][0]),
      (v) => v['vectors'][0]['chunkId'] = 'unknown',
      (v) => v['vectors'].add(v['vectors'][0]),
      (v) => v['embeddingDimensions'] = 3,
      (v) => v['embeddingModelId'] = '',
      (v) => v['embeddingMode'] = 'unknown',
    ]) {
      final raw = fixture();
      mutate(raw);
      await input.writeAsString(jsonEncode(raw));
      await expectLater(export(), throwsFormatException);
    }
    await input
        .writeAsString(jsonEncode(fixture()).replaceFirst('0.5', '1e999'));
    await expectLater(export(), throwsFormatException);
  });
}
