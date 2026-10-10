import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'local_dictionary.dart';

/// A per-window, loopback-only origin serving just one imported dictionary.
/// It never shares the reader server, filesystem routes or application bridge.
class DictionaryDocument {
  DictionaryDocument._(this._server, this._store, this._entry);
  final HttpServer _server;
  final LocalDictionaryStore _store;
  final DictionaryEntry _entry;
  final _token = const Uuid().v4();
  Uri get uri =>
      Uri.parse('http://127.0.0.1:${_server.port}/$_token/index.html');

  static Future<DictionaryDocument> open(
      LocalDictionaryStore store, DictionaryEntry entry) async {
    if (entry.dictionaryId == null || entry.html == null) {
      throw const DictionaryFailure('resource');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final document = DictionaryDocument._(server, store, entry);
    server.listen(document._serve);
    return document;
  }

  bool allows(Uri? url) =>
      url != null &&
      url.scheme == uri.scheme &&
      url.host == uri.host &&
      url.port == uri.port &&
      url.userInfo.isEmpty &&
      url.path == uri.path &&
      url.query.isEmpty;

  Future<void> close() async {
    await _server.close(force: true);
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final prefix = '/$_token/';
      if (!{'GET', 'HEAD'}.contains(request.method) ||
          request.headers.value(HttpHeaders.hostHeader) != uri.authority ||
          !request.uri.path.startsWith(prefix)) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      // HTTP CSP sandbox is intentional: the sandbox directive is ignored in meta.
      final origin = '${uri.origin}$prefix';
      response.headers.set(
          'Content-Security-Policy',
          "sandbox allow-scripts; default-src 'none'; script-src 'unsafe-inline' $origin; "
              "style-src 'unsafe-inline' $origin; img-src $origin data:; "
              "media-src $origin data: blob:; font-src $origin data:; connect-src 'none'; "
              "frame-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'");
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set('Referrer-Policy', 'no-referrer');
      response.headers.set('Cache-Control', 'no-store');
      response.headers.set(
          'Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
      final name =
          dictionaryResourcePath(request.uri.path.substring(prefix.length));
      List<int>? bytes;
      if (name == 'index.html') {
        response.headers.contentType = ContentType.html;
        bytes = utf8.encode(dictionaryDocumentHtml(_entry.html!));
      } else {
        final mime =
            dictionaryResourceTypes[p.posix.extension(name).toLowerCase()];
        if (mime == null) {
          response.statusCode = HttpStatus.notFound;
          return;
        }
        bytes = await _store.resource(_entry.dictionaryId!, name);
        response.headers.set(HttpHeaders.contentTypeHeader, mime);
        // Opaque sandbox origins need CORS for fonts and some media engines.
        response.headers.set('Access-Control-Allow-Origin', '*');
      }
      if (bytes == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final length = bytes.length;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
        final start = match == null ? -1 : int.tryParse(match[1]!) ?? -1;
        final end = match == null || match[2]!.isEmpty
            ? length - 1
            : int.tryParse(match[2]!) ?? -1;
        if (start < 0 || start >= length || end < start || end >= length) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          response.headers.set('Content-Range', 'bytes */$length');
          return;
        }
        response.statusCode = HttpStatus.partialContent;
        response.headers.set('Content-Range', 'bytes $start-$end/$length');
        bytes = bytes.sublist(start, end + 1);
      }
      response.headers.set('Accept-Ranges', 'bytes');
      response.contentLength = bytes.length;
      if (request.method != 'HEAD') response.add(bytes);
    } catch (_) {
      response.statusCode = HttpStatus.notFound;
    } finally {
      await response.close();
    }
  }
}

String dictionaryDocumentHtml(String source) {
  final document = html.parse(source);
  for (final node in document
      .querySelectorAll('base,meta[http-equiv],iframe,object,embed')) {
    node.remove();
  }
  // MDict resource keys use Windows separators and often start at the root.
  for (final node in document.querySelectorAll('[src],[href]')) {
    for (final attr in ['src', 'href']) {
      final value = node.attributes[attr];
      if (value == null) continue;
      if (value.startsWith('sound://') && node.localName == 'a') {
        final audio = Element.tag('audio')
          ..attributes['controls'] = ''
          ..attributes['preload'] = 'none'
          ..attributes['src'] = value
              .substring(8)
              .replaceAll('\\', '/')
              .replaceFirst(RegExp(r'^/+'), '');
        node.replaceWith(audio);
      } else if (!value.startsWith('//') &&
          Uri.tryParse(value)?.hasScheme == false) {
        node.attributes[attr] =
            value.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
      }
    }
  }
  document.head!.append(Element.tag('meta')
    ..attributes.addAll({
      'name': 'viewport',
      'content': 'width=device-width, initial-scale=1'
    }));
  document.head!.append(Element.tag('style')
    ..text = 'html,body{height:auto!important;min-height:0!important;margin:0!important;'
        'padding:0!important}body{display:flow-root;font:14px/1.4 system-ui,sans-serif;'
        'overflow-wrap:anywhere;color-scheme:light dark}'
        'p{margin-block:.3em}h1,h2,h3,h4{margin-block:.4em;font-size:1.15em}'
        'img,audio,video{max-width:100%}img{height:auto}');
  return '<!doctype html>${document.documentElement!.outerHtml}';
}
