import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/service/knowledge/knowledge_index_stream.dart';

/// Rewrite and validate one record at a time. Retain only chunk identities and
/// a vector-seen bitmap, not book text or vectors. Temporary output must never
/// become active until this function returns successfully.
Future<Map<String, dynamic>> transferKnowledgeIndex({
  required File input,
  required File output,
  required String bookSha,
  required String localId,
  required String fingerprint,
  required bool importing,
}) async {
  final identity = 'sha256:$bookSha';
  final expectedId = importing ? identity : localId;
  final targetId = importing ? localId : identity;
  final fields = <String, dynamic>{};
  final envelope = <String, dynamic>{};
  final positions = <String, int>{};
  final arrays = <String>{};
  Uint8List? seenVectors;
  var vectors = 0;
  int? dimension;
  var arrayCount = 0;
  var fieldCount = 0;
  var chunksEnded = false;
  var outputBytes = 0;
  final sink = await output.open(mode: FileMode.write);
  Future<void> write(String text) async {
    final bytes = utf8.encode(text);
    outputBytes += bytes.length;
    if (outputBytes > maxKnowledgeIndexBytes) {
      throw const FormatException('向量索引超过安全同步大小限制（1 GiB）');
    }
    await sink.writeFrom(bytes);
  }

  Future<void> field(String key, dynamic value) => write(
      '${fieldCount++ == 0 ? '' : ','}${jsonEncode(key)}:${jsonEncode(value)}');
  try {
    await write(importing
        ? '{'
        : '{"schema":1,"bookSha256":${jsonEncode(bookSha)},"index":{');
    await for (final event
        in KnowledgeJsonReader(input).read(envelope: importing)) {
      switch (event.kind) {
        case 'envelope':
          if (!['schema', 'bookSha256'].contains(event.key)) {
            throw const FormatException('向量索引格式无效');
          }
          envelope[event.key] = event.value;
        case 'field':
          if (![
            'bookId',
            'contentHash',
            'sourceFingerprint',
            'embeddingMode',
            'embeddingModelId',
            'embeddingDimensions',
          ].contains(event.key)) {
            throw const FormatException('向量索引字段无效');
          }
          if (jsonEncode(event.value).length > 4096) {
            throw const FormatException('向量索引模型元数据无效');
          }
          fields[event.key] = event.value;
          if (event.key == 'sourceFingerprint') continue;
          await field(
              event.key, event.key == 'bookId' ? targetId : event.value);
        case 'start':
          arrays.add(event.key);
          if (event.key == 'vectors') {
            if (!chunksEnded) throw const FormatException('向量索引片段顺序无效');
            seenVectors = Uint8List(positions.length);
          }
          arrayCount = 0;
          await write('${fieldCount++ == 0 ? '' : ','}"${event.key}":[\n');
        case 'item':
          final raw = event.value;
          if (raw is! Map<String, dynamic>) {
            throw const FormatException('向量索引记录无效');
          }
          Map<String, dynamic> mapped;
          if (event.key == 'chunks') {
            final id = raw['id'];
            final startOffset = raw['startOffset'] ?? 0;
            if (id is! String ||
                id.length > 4096 ||
                positions.containsKey(id) ||
                raw['bookId'] != expectedId ||
                raw['chapterId'] is! String ||
                raw['text'] is! String ||
                startOffset is! int ||
                startOffset < 0 ||
                positions.length >= 250000) {
              throw const FormatException('向量索引书籍或片段无效');
            }
            final position = positions.length;
            positions[id] = position;
            mapped = {
              'id': '$targetId:$position',
              'bookId': targetId,
              'chapterId': raw['chapterId'],
              'text': raw['text'],
              'startOffset': startOffset,
            };
          } else {
            final position = positions[raw['chunkId']];
            final vector = raw['vector'];
            if (position == null ||
                seenVectors![position] != 0 ||
                vector is! List ||
                vector.isEmpty ||
                vector.length > 8192 ||
                (dimension != null && vector.length != dimension) ||
                vector.any((v) => v is! num || !v.isFinite)) {
              throw const FormatException('向量索引向量无效');
            }
            dimension = vector.length;
            seenVectors[position] = 1;
            vectors++;
            mapped = {'chunkId': '$targetId:$position', 'vector': vector};
          }
          await write('${arrayCount++ == 0 ? '' : ','}${jsonEncode(mapped)}\n');
        case 'end':
          if (event.key == 'chunks') chunksEnded = true;
          await write(']');
      }
    }
    if (importing &&
        (envelope['schema'] != 1 || envelope['bookSha256'] != bookSha)) {
      throw const FormatException('向量索引格式或书籍身份不匹配');
    }
    if (fields['bookId'] != expectedId ||
        fields['contentHash'] is! String ||
        !arrays.containsAll(['chunks', 'vectors']) ||
        positions.isEmpty ||
        (vectors > 0 && vectors != positions.length) ||
        (importing && vectors == 0) ||
        (vectors > 0 &&
            (!['local', 'remote'].contains(fields['embeddingMode']) ||
                fields['embeddingModelId'] is! String ||
                (fields['embeddingModelId'] as String).trim().isEmpty ||
                fields['embeddingDimensions'] is! int ||
                fields['embeddingDimensions'] != dimension))) {
      throw const FormatException('向量索引书籍、片段或模型元数据无效');
    }
    if (importing) await field('sourceFingerprint', fingerprint);
    await write(importing ? '}' : '}}');
    await sink.flush();
    return {
      ...fields,
      'chunkCount': positions.length,
      'vectorCount': vectors,
      'matchesSource': importing || fields['sourceFingerprint'] == fingerprint,
    };
  } finally {
    await sink.close();
  }
}
