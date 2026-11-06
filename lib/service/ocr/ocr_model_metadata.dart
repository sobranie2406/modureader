import 'dart:convert';
import 'dart:typed_data';
import 'package:yaml/yaml.dart';

/// Apple ONNX bindings do not expose metadata. Read only the pinned model's
/// ModelProto.metadata_props (14); skip tensor/graph payloads without copying.
List<String> ocrAlphabet(Uint8List model) {
  if (model.length > 16 * 1024 * 1024) {
    throw const FormatException('Model too large');
  }
  final reader = _ProtoReader(model);
  while (!reader.done) {
    final tag = reader.varint();
    if (tag == (14 << 3 | 2)) {
      final entry = _ProtoReader(reader.bytes());
      String? key, value;
      while (!entry.done) {
        final field = entry.varint();
        if (field == 10) {
          key = utf8.decode(entry.bytes());
        } else if (field == 18) {
          value = utf8.decode(entry.bytes());
        } else {
          entry.skip(field & 7);
        }
      }
      if (key == 'character' && value != null) {
        final chars = value.split('\n');
        // Some upstream English alphabets terminate with a newline.
        // Keep the actual space entry: the exported CTC includes an added space.
        while (chars.isNotEmpty && chars.last.isEmpty) {
          chars.removeLast();
        }
        if (chars.length < 10 ||
            chars.length > 22000 ||
            chars.any((c) => c.isEmpty)) {
          throw const FormatException('Invalid OCR alphabet');
        }
        return ['', ...chars, ' '];
      }
    } else {
      reader.skip(tag & 7);
    }
  }
  throw const FormatException('OCR alphabet missing');
}

class _ProtoReader {
  _ProtoReader(this.data);
  final Uint8List data;
  int offset = 0;
  bool get done => offset == data.length;
  int varint() {
    var value = 0;
    for (var shift = 0; shift < 63; shift += 7) {
      if (offset >= data.length) throw const FormatException('Truncated model');
      final byte = data[offset++];
      value |= (byte & 127) << shift;
      if (byte < 128) return value;
    }
    throw const FormatException('Invalid model integer');
  }

  void advance(int n) {
    if (n < 0 || offset + n > data.length) {
      throw const FormatException('Truncated model');
    }
    offset += n;
  }

  Uint8List bytes() {
    final length = varint(), start = offset;
    advance(length);
    return Uint8List.sublistView(data, start, offset);
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        advance(8);
      case 2:
        advance(varint());
      case 5:
        advance(4);
      default:
        throw const FormatException('Invalid model field');
    }
  }
}

/// Official V6 exports keep their alphabet in the accompanying inference YAML.
/// Read the small, hash-verified sidecar instead of copying the large model.
List<String> ocrAlphabetFromConfig(String config) {
  if (utf8.encode(config).length > 512 * 1024) {
    throw const FormatException('OCR config too large');
  }
  final data = loadYaml(config);
  final post = data is Map ? data['PostProcess'] : null;
  final chars = post is Map ? post['character_dict'] : null;
  if (post is! Map ||
      post['name'] != 'CTCLabelDecode' ||
      chars is! List ||
      chars.length < 10 ||
      chars.length > 22000 ||
      chars.any((c) => c is! String || c.isEmpty)) {
    throw const FormatException('Invalid OCR alphabet');
  }
  return ['', ...chars.cast<String>(), ' '];
}
