import 'dart:io';
import 'package:anx_reader/service/book_player/reader_background_response.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/book_player/reader_file_access.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;

class Server {
  static final Server _singleton = Server._internal();

  factory Server() {
    return _singleton;
  }

  Server._internal();

  HttpServer? _server;

  Future start() async {
    if (_server != null) {
      AnxLog.info(
        'Server: Existing instance detected on port ${_server?.port}, restarting',
      );
      await stop();
    }

    // Do not log capability URLs or book filenames.
    final handler = const shelf.Pipeline().addHandler(_handleRequests);

    int port = Prefs().lastServerPort;

    try {
      _server = await io.serve(handler, '127.0.0.1', port);
    } catch (e, s) {
      AnxLog.warning(
          'Server: Failed to bind to port $port, trying random port $e', s);
      _server = await io.serve(handler, '127.0.0.1', 0);
    }

    Prefs().lastServerPort = _server!.port;
    AnxLog.info(
        'Server: Serving at http://${_server?.address.host}:${_server?.port}');
  }

  int get port {
    return _server!.port;
  }

  Future stop() async {
    if (_server == null) {
      return;
    }
    final stoppedPort = _server!.port;
    await _server?.close(force: true);
    _server = null;
    AnxLog.info('Server: Server stopped (port $stoppedPort)');
  }

  Future<String> _loadAsset(String path) async {
    return await rootBundle.loadString(path);
  }

  final _files = ReaderFileAccess();

  String setTempFile(File file) {
    return 'book/${_files.register(file, reuse: false)}';
  }

  String bookUrl(File file) =>
      'http://127.0.0.1:$port/book/${_files.register(file)}';

  void releaseTempFile(String route) =>
      _files.revoke(route.substring('book/'.length));

  Future<shelf.Response> _handleRequests(shelf.Request request) async {
    final uriPath = request.requestedUri.path;
    final origin = request.headers['origin'];
    if (request.requestedUri.host != '127.0.0.1' ||
        (origin != null && origin != 'http://127.0.0.1:$port') ||
        request.headers['sec-fetch-site'] == 'cross-site') {
      return shelf.Response.forbidden('Origin not allowed');
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      return shelf.Response(405);
    }
    if (uriPath.split('/').any((part) => part == '..' || part == '.')) {
      return shelf.Response.notFound('Not found');
    }

    if (uriPath.startsWith('/book/')) {
      return _handleBookRequest(request);
    } else if (uriPath.startsWith('/js/')) {
      String content = await _loadAsset('assets/js/${path.basename(uriPath)}');
      return shelf.Response.ok(
        content,
        headers: {'Content-Type': 'application/javascript'},
      );
    } else if (uriPath.startsWith('/fonts/')) {
      Directory fontDir = getFontDir();
      final file = ReaderFileAccess.within(fontDir, path.basename(uriPath));
      if (file == null) {
        return shelf.Response.notFound('Font not found');
      }
      return shelf.Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': 'font/opentype',
          'cache-control': 'public, max-age=31536000',
        },
      );
    } else if (uriPath.startsWith('/foliate-js/')) {
      if (uriPath.endsWith('.epub')) {
        final file =
            await rootBundle.load('assets/foliate-js/${uriPath.substring(12)}');
        return shelf.Response.ok(
          file.buffer.asUint8List(),
          headers: {
            'Content-Type': 'application/epub+zip',
          },
        );
      }
      String content =
          await _loadAsset('assets/foliate-js/${uriPath.substring(12)}');

      // Determine content type based on file extension
      String contentType;
      if (uriPath.endsWith('.html')) {
        contentType = 'text/html';
      } else if (uriPath.endsWith('.css')) {
        contentType = 'text/css';
      } else if (uriPath.endsWith('.js')) {
        contentType = 'application/javascript';
      } else if (uriPath.endsWith('.json')) {
        contentType = 'application/json';
      } else {
        contentType = 'application/octet-stream';
      }

      return shelf.Response.ok(
        content,
        headers: {
          'Content-Type': contentType,
        },
      );
    } else if (uriPath.startsWith('/bgimg/')) {
      return await _handleBgimgRequest(request);
    } else {
      return shelf.Response.notFound('Not found');
    }
  }

  shelf.Response _handleBookRequest(shelf.Request request) {
    final file = _files.resolve(request.url.path.substring(5));
    if (file == null) {
      return shelf.Response.notFound('Book not found');
    }
    final headers = {
      'Content-Type': path.extension(file.path).toLowerCase() == '.pdf'
          ? 'application/pdf'
          : 'application/octet-stream',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    };
    return shelf.Response.ok(file.openRead(), headers: headers);
  }

  Future<shelf.Response> _handleBgimgRequest(shelf.Request request) async {
    return readerBackgroundResponse(request.requestedUri,
        directory: getBgimgDir(), assets: rootBundle);
  }
}
