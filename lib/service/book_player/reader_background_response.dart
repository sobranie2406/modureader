import 'dart:io';

import 'package:anx_reader/service/book_player/reader_file_access.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';

/// Serve only background images, preserving AssetBundle byte views (which need
/// not span their backing buffer). Kept separate so platform buffers can be
/// exercised without starting a WebView or touching the user's data directory.
Future<Response> readerBackgroundResponse(
  Uri uri, {
  required Directory directory,
  required AssetBundle assets,
}) async {
  final segments = uri.pathSegments; // Already percent-decoded exactly once.
  if (segments.length < 3 ||
      segments.first != 'bgimg' ||
      segments.any((s) =>
          s.isEmpty ||
          s == '.' ||
          s == '..' ||
          s.contains('/') ||
          s.contains('\\'))) {
    return Response.notFound('Bgimg not found');
  }
  final name = segments.skip(2).join('/');
  final contentType = switch (path.extension(name).toLowerCase()) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.png' => 'image/png',
    '.webp' => 'image/webp',
    '.gif' => 'image/gif',
    '.bmp' => 'image/bmp',
    '.avif' => 'image/avif',
    _ => null,
  };
  if (contentType == null) return Response.notFound('Bgimg not found');

  try {
    final Uint8List bytes;
    if (segments[1] == 'assets' && name.startsWith('assets/images/bgimg/')) {
      final data = await assets.load(name);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } else if (segments[1] == 'local' && segments.length == 3) {
      final file = ReaderFileAccess.within(directory, name);
      if (file == null) return Response.notFound('Bgimg not found');
      bytes = await file.readAsBytes();
    } else {
      return Response.notFound('Bgimg not found');
    }
    return Response.ok(bytes, headers: {
      // A paired night image can have a different encoding from the day file,
      // even though the existing importer gives them the same extension.
      'Content-Type': _imageContentType(bytes) ?? contentType,
      // A day/night swap may change bytes without changing the filename.
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
  } on FileSystemException {
    return Response.notFound('Bgimg not found');
  } on FlutterError {
    return Response.notFound('Bgimg not found');
  }
}

String? _imageContentType(Uint8List bytes) {
  bool startsWith(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (startsWith([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return 'image/png';
  }
  if (startsWith([0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (startsWith([0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (startsWith([0x52, 0x49, 0x46, 0x46]) &&
      startsWith([0x57, 0x45, 0x42, 0x50], 8)) {
    return 'image/webp';
  }
  if (startsWith([0x42, 0x4d])) return 'image/bmp';
  return null;
}
