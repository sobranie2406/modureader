import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:modu_reader/models/plugin_network.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_network_guard.dart';

class ArticleCaptureFailure implements Exception {
  const ArticleCaptureFailure(this.code);
  final String code;
  @override
  String toString() => 'ArticleCaptureFailure($code)';
}

class CapturedArticle {
  const CapturedArticle(this.title, this.sourceUrl, this.markdown);
  final String title;
  final Uri sourceUrl;
  final String markdown;
}

class ArticleCaptureDocument {
  const ArticleCaptureDocument(this.content, this.sourceUrl,
      {required this.plainText});
  final String content;
  final Uri sourceUrl;
  final bool plainText;
}

/// Downloads and decodes only; extraction belongs to the installed plugin.
class ArticleCaptureService {
  ArticleCaptureService(
      {PluginNetworkGuard? guard,
      HttpClient Function()? clientFactory,
      this.timeout = const Duration(seconds: 15)})
      : _guard = guard ?? PluginNetworkGuard(),
        _clientFactory = clientFactory ?? HttpClient.new;

  final PluginNetworkGuard _guard;
  final HttpClient Function() _clientFactory;
  final Duration timeout;
  static const maxBytes = PluginLimits.maxArticleHtmlBytes;
  static int _active = 0;

  Future<ArticleCaptureDocument> fetchDocument(String url,
      {required PluginCancelToken cancel}) async {
    if (_active >= 2) throw const ArticleCaptureFailure('busy');
    _active++;
    HttpClient? client;
    var stopped = false, finished = false;
    final interrupted = Completer<ArticleCaptureDocument>();
    interrupted.future.ignore();
    void abort(String code) {
      if (finished || stopped) return;
      stopped = true;
      client?.close(force: true);
      interrupted.completeError(ArticleCaptureFailure(code));
    }

    void check() {
      if (stopped || cancel.isCancelled) {
        throw const ArticleCaptureFailure('cancelled');
      }
    }

    cancel.whenCancelled(() => abort('cancelled'));
    final timer = Timer(timeout, () => abort('timeout'));
    Future<ArticleCaptureDocument> acquire() async {
      var uri = _pageUri(url);
      for (var redirects = 0;; redirects++) {
        check();
        final host = PluginAllowlist.validate(uri.host, 'article host');
        final target = await _guard.validate(
            network: PluginNetwork(
                domains: [host],
                timeoutMs: 15000,
                maxResponseBytes: maxBytes,
                requestsPerLookup: 1),
            uri: uri,
            headers: const {});
        check();
        final current = client = _clientFactory();
        current.findProxy = (_) => 'DIRECT';
        current.connectionFactory = (address, proxyHost, proxyPort) =>
            connectPluginTls(
                target: target,
                timeout: timeout,
                isCancelled: () => stopped || cancel.isCancelled);
        final request = await current.getUrl(uri);
        check();
        request.followRedirects = false;
        request.persistentConnection = false;
        request.cookies.clear();
        request.headers.set(
            HttpHeaders.userAgentHeader, 'ModuReader (manual article capture)');
        request.headers.set(HttpHeaders.acceptHeader,
            'text/html,application/xhtml+xml,text/plain');
        final response = await request.close();
        check();
        if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          current.close(force: true);
          if (redirects >= 3 || location == null || location.length > 4096) {
            throw const ArticleCaptureFailure('redirect');
          }
          uri = _pageUri(uri.resolve(location).toString());
          continue;
        }
        if (response.statusCode != 200) {
          throw const ArticleCaptureFailure('network');
        }
        final type = response.headers.contentType;
        final mime = type?.mimeType.toLowerCase();
        if (!const ['text/html', 'application/xhtml+xml', 'text/plain']
            .contains(mime)) {
          throw const ArticleCaptureFailure('format');
        }
        if (response.contentLength > maxBytes) {
          throw const ArticleCaptureFailure('size');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          check();
          if (bytes.length + chunk.length > maxBytes) {
            throw const ArticleCaptureFailure('size');
          }
          bytes.add(chunk);
        }
        current.close(force: true);
        check();
        final data = bytes.takeBytes();
        var charset = type?.charset;
        if (charset == null && mime != 'text/plain') {
          final prefix = latin1.decode(data.take(4096).toList());
          charset = RegExp(r'''charset\s*=\s*["']?\s*([A-Za-z0-9._-]+)''',
                  caseSensitive: false)
              .firstMatch(prefix)
              ?.group(1);
        }
        final encoding =
            charset == null ? utf8 : Charset.getByName(charset.toLowerCase());
        if (encoding == null) throw const ArticleCaptureFailure('format');
        final text = encoding.decode(data);
        if (utf8.encode(text).length > maxBytes) {
          throw const ArticleCaptureFailure('size');
        }
        check();
        return ArticleCaptureDocument(text, uri,
            plainText: mime == 'text/plain');
      }
    }

    try {
      return await Future.any([acquire(), interrupted.future]);
    } on ArticleCaptureFailure {
      rethrow;
    } on FormatException {
      throw const ArticleCaptureFailure('format');
    } catch (_) {
      throw const ArticleCaptureFailure('network');
    } finally {
      finished = true;
      timer.cancel();
      client?.close(force: true);
      _active--;
    }
  }
}

Uri _pageUri(String value) {
  if (value.length > 4096 || value.contains(RegExp(r'[\x00-\x20\x7f]'))) {
    throw const ArticleCaptureFailure('url');
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443) {
    throw const ArticleCaptureFailure('url');
  }
  return uri.removeFragment();
}
