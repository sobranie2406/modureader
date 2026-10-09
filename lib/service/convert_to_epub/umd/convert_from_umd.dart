import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/service/convert_to_epub/markdown/convert_from_markdown.dart';
import 'package:anx_reader/service/convert_to_epub/section.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

const _maxFile = 64 * 1024 * 1024;
const _maxText = 32 * 1024 * 1024;

Future<File> convertFromUmd(File file) async {
  if (await file.length() > _maxFile) {
    throw const FormatException('UMD file exceeds 64 MiB / UMD 文件超过 64 MiB');
  }
  final bytes = await compute(
      _convertFile, (file.path, path.basenameWithoutExtension(file.path)));
  final temp = await getAnxTempDir();
  final output = File(path.join(temp.path, 'umd-${const Uuid().v4()}.epub'));
  try {
    return await output.writeAsBytes(bytes, flush: true);
  } catch (_) {
    if (await output.exists()) await output.delete();
    rethrow;
  }
}

List<int> _convertFile((String, String) input) {
  final file = File(input.$1);
  if (file.lengthSync() > _maxFile) {
    throw const FormatException('UMD too large');
  }
  return umdToEpub(file.readAsBytesSync(), fallbackTitle: input.$2);
}

/// UMD framing: little-endian # command records and $ data records.
/// Format references (independent implementation, no native dependency):
/// https://github.com/linpinger/golib/blob/main/ebook/UMDReader.go
/// https://github.com/rhythmkay/UMDParser/blob/master/UMDParser/umd/UMDParser.m
List<int> umdToEpub(Uint8List bytes, {required String fallbackTitle}) {
  Never invalid() => throw const FormatException(
      'Invalid or incomplete text UMD / UMD 文件损坏、不完整或不是支持的文字格式');
  if (bytes.length < 12 || bytes.length > _maxFile) invalid();
  final reader = ByteData.sublistView(bytes);
  if (reader.getUint32(0, Endian.little) != 0xde9a9b89) invalid();
  final fields = <int, Uint8List>{};
  final blocks = <int, Uint8List>{};
  var position = 4, records = 0;
  while (position < bytes.length) {
    if (++records > 100000) invalid();
    final marker = bytes[position];
    if (marker == 0x23) {
      if (position + 5 > bytes.length) invalid();
      final id = reader.getUint16(position + 1, Endian.little);
      final length = bytes[position + 4];
      if (length < 5 || position + length > bytes.length) invalid();
      // Page-layout/index extensions may repeat, semantic fields may not.
      if (const {1, 2, 3, 11, 12, 0x81, 0x82, 0x83, 0x84}.contains(id)) {
        if (fields.containsKey(id)) invalid();
        fields[id] =
            Uint8List.sublistView(bytes, position + 5, position + length);
      }
      position += length;
    } else if (marker == 0x24) {
      if (position + 9 > bytes.length) invalid();
      final id = reader.getUint32(position + 1, Endian.little);
      final length = reader.getUint32(position + 5, Endian.little);
      if (length < 9 ||
          position + length > bytes.length ||
          blocks.containsKey(id)) {
        invalid();
      }
      blocks[id] =
          Uint8List.sublistView(bytes, position + 9, position + length);
      position += length;
    } else {
      invalid();
    }
  }
  final type = fields[1];
  if (type == null || type.length != 3) invalid();
  if (type[0] != 1) {
    throw const FormatException(
        'Only text UMD is supported; image/comic UMD is not supported yet / 暂仅支持文字 UMD，不支持图片或漫画型 UMD');
  }
  int number(Uint8List? data) {
    if (data == null || data.length != 4) invalid();
    return ByteData.sublistView(data).getUint32(0, Endian.little);
  }

  Uint8List linked(int field) {
    final data = blocks[number(fields[field])];
    if (data == null) invalid();
    return data;
  }

  List<int> numbers(Uint8List data) {
    if (data.isEmpty || data.length % 4 != 0 || data.length > 80000) invalid();
    final view = ByteData.sublistView(data);
    return [
      for (var i = 0; i < data.length; i += 4) view.getUint32(i, Endian.little)
    ];
  }

  final textLength = number(fields[11]);
  if (textLength == 0 || textLength > _maxText || textLength.isOdd) invalid();
  final declaredFileLength = number(fields[12]);
  // Some writers append page/index extensions after the end record.
  if (declaredFileLength < 12 || declaredFileLength > bytes.length) invalid();
  final offsets = numbers(linked(0x83));
  final titles = <String>[];
  final titleData = linked(0x84);
  for (var pos = 0; pos < titleData.length;) {
    final length = titleData[pos++];
    if (pos + length > titleData.length || titles.length >= 20000) invalid();
    titles.add(_utf16(Uint8List.sublistView(titleData, pos, pos + length)));
    pos += length;
  }
  if (titles.length != offsets.length || offsets.first != 0) invalid();
  for (var i = 0; i < offsets.length; i++) {
    if (offsets[i].isOdd ||
        offsets[i] > textLength ||
        (i > 0 && offsets[i] < offsets[i - 1])) {
      invalid();
    }
  }
  final contentIds = numbers(linked(0x81)).toSet();
  if (contentIds.length * 4 != linked(0x81).length ||
      contentIds.any((id) => !blocks.containsKey(id))) {
    invalid();
  }
  // Some writers pad the last 32 KiB text block with NUL bytes.
  final paddedLength = ((textLength + 32767) ~/ 32768) * 32768;
  final sink = _TextSink(paddedLength);
  // The index can be reversed by UMD writers. Content follows physical order.
  for (final entry in blocks.entries) {
    if (!contentIds.contains(entry.key)) continue;
    final inflater =
        ZLibDecoder().startChunkedConversion(ByteConversionSink.from(sink));
    inflater.add(entry.value);
    inflater.close();
  }
  final expanded = sink.bytes.takeBytes();
  if (expanded.length != textLength && expanded.length != paddedLength) {
    invalid();
  }
  if (expanded.skip(textLength).any((byte) => byte != 0)) invalid();
  final text = Uint8List.sublistView(expanded, 0, textLength);
  final sections = <Section>[];
  for (var i = 0; i < offsets.length; i++) {
    final end = i + 1 < offsets.length ? offsets[i + 1] : textLength;
    sections.add(Section(
        titles[i],
        _utf16(Uint8List.sublistView(text, offsets[i], end))
            .replaceAll('\u2029', '\n')
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n'),
        1));
  }
  Uint8List? cover;
  String? coverType;
  final coverField = fields[0x82];
  if (coverField != null) {
    if (coverField.length != 5 || coverField[0] != 1) invalid();
    cover = blocks[number(Uint8List.sublistView(coverField, 1))];
    if (cover == null || cover.length > 8 * 1024 * 1024) invalid();
    if (cover.length >= 3 &&
        cover[0] == 0xff &&
        cover[1] == 0xd8 &&
        cover[2] == 0xff) {
      coverType = 'image/jpeg';
    } else if (cover.length >= 8 &&
        listEquals(cover.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10])) {
      coverType = 'image/png';
    } else {
      invalid();
    }
  }
  final title = fields[2] == null ? '' : _utf16(fields[2]!).trim();
  return umdTextToEpub(
      title: title.isEmpty ? fallbackTitle : title,
      author: fields[3] == null ? 'Unknown' : _utf16(fields[3]!),
      sections: sections,
      sourceDigest: sha256.convert(bytes).toString(),
      cover: cover,
      coverType: coverType);
}

String _utf16(Uint8List bytes) {
  if (bytes.length.isOdd) throw const FormatException('Invalid UMD UTF-16');
  final data = ByteData.sublistView(bytes);
  final units = <int>[];
  for (var i = 0; i < bytes.length; i += 2) {
    final unit = data.getUint16(i, Endian.little);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (i + 4 > bytes.length) {
        throw const FormatException('Invalid UMD surrogate');
      }
      final low = data.getUint16(i + 2, Endian.little);
      if (low < 0xdc00 || low > 0xdfff) {
        throw const FormatException('Invalid UMD surrogate');
      }
      units.addAll([unit, low]);
      i += 2;
    } else {
      if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException('Invalid UMD surrogate');
      }
      units.add(unit);
    }
  }
  return String.fromCharCodes(units);
}

class _TextSink implements Sink<List<int>> {
  _TextSink(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw const FormatException(
          'UMD decompressed text exceeds declared length');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
