import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  KnowledgeJsonReader(File file, {int maxBytes = maxKnowledgeIndexBytes})
      : _chunks = StreamIterator(
            _boundedBytes(file, maxBytes).transform(utf8.decoder));

  final StreamIterator<String> _chunks;
  String _buffer = '';
  int _offset = 0;
  bool _ended = false;

  static Stream<List<int>> _boundedBytes(File file, int maxBytes) async* {
    if (await file.length() > maxBytes) {
      throw const FormatException('向量索引超过安全同步大小限制（1 GiB）');
    }
    var received = 0;
    await for (final bytes in file.openRead()) {
      received += bytes.length;
      if (received > maxBytes) {
        throw const FormatException('向量索引超过安全同步大小限制（1 GiB）');
      }
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
