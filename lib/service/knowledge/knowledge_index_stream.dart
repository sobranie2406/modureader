import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';

const maxKnowledgeIndexBytes = 1024 * 1024 * 1024;
const maxKnowledgeRecordCharacters = 2 * 1024 * 1024;

/// A field, an array boundary, or one array entry. Works with both the original
/// compact JSON and the line-oriented JSON written by FileKnowledgeIndexStore.
class KnowledgeJsonEvent {
  const KnowledgeJsonEvent(this.kind, this.key, [this.value]);
  final String kind;
  final String key;
  final dynamic value;
}

/// Bounded JSON cursor. Scans synchronously inside each UTF-8 stream chunk;
/// awaits only on IO, never once per character. Only one record is decoded at
/// a time, so a gigabyte of vectors does not produce a gigabyte JSON string or
/// a second complete decoded object tree.
class KnowledgeJsonReader {
  KnowledgeJsonReader(File file,
      {int maxBytes = maxKnowledgeIndexBytes,
      void Function(List<int>)? onBytes})
      : _chunks = StreamIterator(
            _boundedBytes(file, maxBytes, onBytes).transform(utf8.decoder));

  final StreamIterator<String> _chunks;
  String _buffer = '';
  int _offset = 0;
  bool _ended = false;

  static Stream<List<int>> _boundedBytes(
      File file, int maxBytes, void Function(List<int>)? onBytes) async* {
    if (await file.length() > maxBytes) {
      throw const FormatException('向量索引超过安全同步大小限制（1 GiB）');
    }
    var received = 0;
    await for (final bytes in file.openRead()) {
      received += bytes.length;
      if (received > maxBytes) {
        throw const FormatException('向量索引超过安全同步大小限制（1 GiB）');
      }
      onBytes?.call(bytes);
      yield bytes;
    }
  }

  Future<bool> _fill() async {
    while (_offset == _buffer.length && !_ended) {
      if (await _chunks.moveNext()) {
        _buffer = _chunks.current;
        _offset = 0;
      } else {
        _ended = true;
      }
    }
    return _offset < _buffer.length;
  }

  bool _space(int c) => c == 32 || c == 10 || c == 13 || c == 9;

  Future<int?> peek() async {
    while (await _fill()) {
      while (_offset < _buffer.length) {
        final c = _buffer.codeUnitAt(_offset);
        if (!_space(c)) return c;
        _offset++;
      }
    }
    return null;
  }

  Future<void> expect(int character) async {
    if (await peek() != character) {
      throw const FormatException('向量索引 JSON 格式无效或被截断');
    }
    _offset++;
  }

  Future<dynamic> value() async {
    final first = await peek();
    if (first == null || [44, 58, 93, 125].contains(first)) {
      throw const FormatException('向量索引 JSON 缺少值');
    }
    final structured = first == 123 || first == 91;
    final quoted = first == 34;
    var depth = 0;
    var inString = false;
    var escaped = false;
    var length = 0;
    final text = StringBuffer();
    while (await _fill()) {
      final start = _offset;
      var complete = false;
      while (_offset < _buffer.length) {
        final c = _buffer.codeUnitAt(_offset);
        if (!structured &&
            !quoted &&
            (_space(c) || c == 44 || c == 93 || c == 125)) {
          complete = true;
          break;
        }
        _offset++;
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (c == 92) {
            escaped = true;
          } else if (c == 34) {
            inString = false;
            if (quoted) complete = true;
          }
        } else if (c == 34) {
          inString = true;
        } else if (c == 123 || c == 91) {
          depth++;
          if (depth > 32) throw const FormatException('向量索引 JSON 嵌套过深');
        } else if (c == 125 || c == 93) {
          depth--;
          if (structured && depth == 0) complete = true;
        }
        if (complete) break;
      }
      length += _offset - start;
      if (length > maxKnowledgeRecordCharacters) {
        throw const FormatException('向量索引单条记录过大');
      }
      text.write(_buffer.substring(start, _offset));
      if (complete) return jsonDecode(text.toString());
    }
    // jsonDecode also rejects unfinished strings/containers.
    return jsonDecode(text.toString());
  }

  Future<String> _key(Set<String> seen) async {
    final key = await value();
    if (key is! String ||
        key.length > 128 ||
        seen.length >= 16 ||
        !seen.add(key)) {
      throw const FormatException('向量索引字段重复或无效');
    }
    await expect(58);
    return key;
  }

  Stream<KnowledgeJsonEvent> _index() async* {
    await expect(123);
    final seen = <String>{};
    if (await peek() != 125) {
      while (true) {
        final key = await _key(seen);
        if (key == 'chunks' || key == 'vectors') {
          await expect(91);
          yield KnowledgeJsonEvent('start', key);
          if (await peek() != 93) {
            while (true) {
              yield KnowledgeJsonEvent('item', key, await value());
              if (await peek() == 93) break;
              await expect(44);
            }
          }
          await expect(93);
          yield KnowledgeJsonEvent('end', key);
        } else {
          yield KnowledgeJsonEvent('field', key, await value());
        }
        if (await peek() == 125) break;
        await expect(44);
      }
    }
    await expect(125);
  }

  Stream<KnowledgeJsonEvent> read({bool envelope = false}) async* {
    try {
      if (envelope) {
        await expect(123);
        final seen = <String>{};
        while (true) {
          final key = await _key(seen);
          if (key == 'index') {
            yield* _index();
          } else {
            yield KnowledgeJsonEvent('envelope', key, await value());
          }
          if (await peek() == 125) break;
          await expect(44);
        }
        await expect(125);
        if (!seen.contains('index')) {
          throw const FormatException('向量索引缺少 index');
        }
      } else {
        yield* _index();
      }
      if (await peek() != null) {
        throw const FormatException('向量索引 JSON 有多余内容');
      }
    } finally {
      await _chunks.cancel();
    }
  }
}

class _MetadataDigest implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Verify a copied/legacy index without allocating its text/vector snapshot.
/// One record is decoded at a time; only IDs and small metadata are retained.
Future<Map<String, dynamic>?> readKnowledgeIndexMetadata(
    File file, String bookId) {
  final path = file.path;
  return Isolate.run(() async {
    final input = File(path);
    final digest = _MetadataDigest();
    final bytes = sha256.startChunkedConversion(digest);
    try {
      final before = await input.stat();
      if (before.type != FileSystemEntityType.file) return null;
      final fields = <String, dynamic>{};
      final ids = <String>{};
      final seen = <String>{};
      final arrays = <String>{};
      var chunksEnded = false;
      int? dimension;
      await for (final event
          in KnowledgeJsonReader(input, onBytes: bytes.add).read()) {
        switch (event.kind) {
          case 'field':
            if (![
                  'bookId',
                  'contentHash',
                  'sourceFingerprint',
                  'embeddingMode',
                  'embeddingModelId',
                  'embeddingDimensions'
                ].contains(event.key) ||
                jsonEncode(event.value).length > 4096) {
              return null;
            }
            fields[event.key] = event.value;
          case 'start':
            arrays.add(event.key);
            if (event.key == 'vectors' && !chunksEnded) return null;
          case 'end':
            if (event.key == 'chunks') chunksEnded = true;
          case 'item':
            final item = event.value;
            if (item is! Map<String, dynamic>) return null;
            if (event.key == 'chunks') {
              final id = item['id'], offset = item['startOffset'] ?? 0;
              if (id is! String ||
                  id.length > 4096 ||
                  !ids.add(id) ||
                  ids.length > 250000 ||
                  item['bookId'] != bookId ||
                  item['chapterId'] is! String ||
                  item['text'] is! String ||
                  offset is! int ||
                  offset < 0) {
                return null;
              }
            } else {
              final id = item['chunkId'], vector = item['vector'];
              if (id is! String ||
                  !ids.contains(id) ||
                  !seen.add(id) ||
                  vector is! List ||
                  vector.isEmpty ||
                  vector.length > 8192 ||
                  (dimension != null && vector.length != dimension) ||
                  vector.any((v) => v is! num || !v.isFinite)) {
                return null;
              }
              dimension = vector.length;
            }
        }
      }
      if (fields['bookId'] != bookId ||
          fields['contentHash'] is! String ||
          fields['sourceFingerprint'] != null &&
              fields['sourceFingerprint'] is! String ||
          !arrays.containsAll(['chunks', 'vectors']) ||
          ids.isEmpty ||
          (seen.isNotEmpty && seen.length != ids.length) ||
          (fields['embeddingDimensions'] != null &&
              fields['embeddingDimensions'] != dimension) ||
          (fields['embeddingMode'] != null &&
              (!['builtin', 'local', 'remote']
                      .contains(fields['embeddingMode']) ||
                  seen.length != ids.length ||
                  fields['embeddingModelId'] is! String ||
                  (fields['embeddingModelId'] as String).trim().isEmpty))) {
        return null;
      }
      final after = await input.stat();
      if (before.size != after.size ||
          before.modified != after.modified ||
          before.changed != after.changed) {
        return null;
      }
      bytes.close();
      return {
        ...fields,
        'chunkCount': ids.length,
        'vectorCount': seen.length,
        'size': after.size,
        'modified': after.modified.microsecondsSinceEpoch,
        'changed': after.changed.microsecondsSinceEpoch,
        'indexSha256': digest.value!.toString()
      };
    } on Object {
      return null;
    }
  });
}
