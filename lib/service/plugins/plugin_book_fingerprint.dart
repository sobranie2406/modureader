import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// KOReader's binary document identity, from the readable original file.
Future<String> partialBookMd5(File file) async {
  final before = await file.stat();
  if (before.type != FileSystemEntityType.file || before.size == 0) {
    throw const FileSystemException('Book file is unavailable');
  }
  final samples = BytesBuilder(copy: false);
  // KOReader samples 1 KiB at byte 0, then at 1 KiB, 4 KiB, 16 KiB, …,
  // through 1 GiB. The last sample can be shorter than a KiB.
  for (var offset = 0;
      offset <= (1 << 30) && offset < before.size;
      offset = offset == 0 ? 1024 : offset * 4) {
    final end = min(offset + 1024, before.size);
    final prior = samples.length;
    await for (final bytes in file.openRead(offset, end)) {
      samples.add(bytes);
    }
    if (samples.length - prior != end - offset) {
      throw const FileSystemException('Book file changed while reading');
    }
  }
  final after = await file.stat();
  if (after.type != before.type ||
      after.size != before.size ||
      after.modified != before.modified ||
      after.changed != before.changed) {
    throw const FileSystemException('Book file changed while reading');
  }
  return md5.convert(samples.takeBytes()).toString();
}
