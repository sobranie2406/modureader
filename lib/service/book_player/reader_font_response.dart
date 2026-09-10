import 'dart:io';

import 'package:anx_reader/service/book_player/reader_file_access.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';

/// A filename is one URL segment, not an already-escaped URL or a path.
String readerFontUrl(String filename, int port) => Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: port,
      pathSegments: ['fonts', filename],
    ).toString().replaceAll("'", '%27'); // Also safe inside CSS url('...').

Future<Response> readerFontResponse(Uri uri,
    {required Directory directory}) async {
  // Decode exactly once. Uri.path is still escaped (e.g. %20 and %E4%B8%AD).
  final segments = uri.pathSegments;
  if (segments.length != 2 ||
      segments.first != 'fonts' ||
      segments.any((part) =>
          part.isEmpty ||
          part == '.' ||
          part == '..' ||
          part.contains('/') ||
          part.contains('\\') ||
          part.contains('\u0000'))) {
    return Response.notFound('Font not found');
  }
  final type = switch (path.extension(segments.last).toLowerCase()) {
    '.ttf' => 'font/ttf',
    '.otf' => 'font/otf',
    _ => null,
  };
  if (type == null) return Response.notFound('Font not found');
  try {
    final file = ReaderFileAccess.within(directory, segments.last);
    if (file == null) return Response.notFound('Font not found');
    // Stream large CJK fonts instead of allocating another full copy per page.
    return Response.ok(file.openRead(), headers: {
      'Content-Type': type,
      // Reimporting a file under the same name must not reuse old font bytes.
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
  } on FileSystemException {
    return Response.notFound('Font not found');
  }
}
