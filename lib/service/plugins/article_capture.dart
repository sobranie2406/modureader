import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:modu_reader/models/plugin_network.dart';
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

/// Manual, native-only page acquisition. Website code and subresources never run.
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
  static const maxBytes = 2 * 1024 * 1024;
  static int _active = 0;

  Future<CapturedArticle> fetch(String url,
      {required PluginCancelToken cancel}) async {
    if (_active >= 2) throw const ArticleCaptureFailure('busy');
    _active++;
    HttpClient? client;
    Isolate? parser;
    var stopped = false, finished = false;
    final interrupted = Completer<CapturedArticle>();
    interrupted.future.ignore();
    void abort(String code) {
      if (finished || stopped) return;
      stopped = true;
      client?.close(force: true);
      parser?.kill(priority: Isolate.immediate);
      interrupted.completeError(ArticleCaptureFailure(code));
    }

    void check() {
      if (stopped || cancel.isCancelled) {
        throw const ArticleCaptureFailure('cancelled');
      }
    }

    cancel.whenCancelled(() => abort('cancelled'));
    final timer = Timer(timeout, () => abort('timeout'));
    Future<CapturedArticle> acquire() async {
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
        final article = await _extractOffThread(
            (text, uri.toString(), mime == 'text/plain'), (isolate) {
          parser = isolate;
          if (stopped) isolate.kill(priority: Isolate.immediate);
        });
        check();
        return article;
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
      parser?.kill(priority: Isolate.immediate);
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

void _parseArticle((SendPort, String, String, bool) input) {
  try {
    input.$1.send(
        extractArticle(input.$2, Uri.parse(input.$3), plainText: input.$4));
  } on ArticleCaptureFailure catch (error) {
    input.$1.send(error.code);
  } catch (_) {
    input.$1.send('format');
  }
}

Future<CapturedArticle> _extractOffThread(
    (String, String, bool) input, void Function(Isolate) onStarted) async {
  final port = ReceivePort();
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn(
        _parseArticle, (port.sendPort, input.$1, input.$2, input.$3),
        onExit: port.sendPort, onError: port.sendPort);
    onStarted(isolate);
    final result = await port.first;
    if (result is CapturedArticle) return result;
    throw ArticleCaptureFailure(result is String ? result : 'format');
  } finally {
    isolate?.kill(priority: Isolate.immediate);
    port.close();
  }
}

String _plain(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
String _escape(String value) =>
    value.replaceAllMapped(RegExp(r'[\\`*_{}\[\]<>#]'), (m) => '\\${m[0]}');

Uri? _link(String? value, Uri source) {
  if (value == null ||
      value.length > 4096 ||
      value.contains(RegExp(r'[\x00-\x20\x7f]'))) {
    return null;
  }
  Uri uri;
  try {
    uri = source.resolve(value);
  } on FormatException {
    return null;
  }
  if (!const ['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

/// Parse offline with the installed HTML parser; no DOM is mounted or executed.
CapturedArticle extractArticle(String source, Uri url,
    {bool plainText = false}) {
  if (utf8.encode(source).length > ArticleCaptureService.maxBytes * 2) {
    throw const ArticleCaptureFailure('size');
  }
  String title;
  String body;
  if (plainText) {
    title = url.pathSegments.where((v) => v.isNotEmpty).lastOrNull ?? url.host;
    body = source.split(RegExp(r'\r?\n')).map(_escape).join('\n');
  } else {
    final document = html.parse(source);
    final elements = <dom.Element>[];
    void count(dom.Node node, int depth) {
      if (depth > 128 || elements.length > 20000) {
        throw const ArticleCaptureFailure('size');
      }
      if (node is dom.Element) elements.add(node);
      for (final child in node.nodes) {
        count(child, depth + 1);
      }
    }

    count(document, 0);
    final preferredTitle = document
        .querySelector('meta[property="og:title"]')
        ?.attributes['content'];
    final fallbackTitle = document.querySelector('h1')?.text ??
        document.querySelector('title')?.text ??
        url.host;
    final unwanted = RegExp(
        r'(^|[\s_-])(ads?|advert\w*|adsbygoogle|banner|cookie\w*|comments?|related|recommend\w*|social|share|sidebar|menu|navigation|推荐|评论|广告)([\s_-]|$)',
        caseSensitive: false);
    for (final element in elements) {
      if (const {
            'script',
            'style',
            'noscript',
            'nav',
            'header',
            'footer',
            'aside',
            'form',
            'iframe',
            'object',
            'embed',
            'svg',
            'canvas',
            'video',
            'audio',
            'button',
            'input',
            'select',
            'textarea',
            'template'
          }.contains(element.localName) ||
          element.attributes.containsKey('hidden') ||
          element.attributes['aria-hidden'] == 'true' ||
          RegExp(r'(display\s*:\s*none|visibility\s*:\s*hidden)',
                  caseSensitive: false)
              .hasMatch(element.attributes['style'] ?? '') ||
          unwanted.hasMatch('${element.id} ${element.className}')) {
        element.remove();
      }
    }
    final root = document.body;
    if (root == null) throw const ArticleCaptureFailure('empty');
    final metrics = <dom.Element, (int, int)>{};
    (int, int) measure(dom.Node node) {
      if (node is dom.Text) return (_plain(node.data).length, 0);
      var text = 0, links = 0;
      for (final child in node.nodes) {
        final size = measure(child);
        text += size.$1;
        links += size.$2;
      }
      if (node is dom.Element) {
        if (node.localName == 'a') links = text;
        metrics[node] = (text, links);
      }
      return (text, links);
    }

    measure(root);
    final scores = <dom.Element, double>{root: 0};
    for (final entry in metrics.entries) {
      final element = entry.key, length = entry.value.$1;
      if (const {'article', 'main'}.contains(element.localName) ||
          element.attributes['role'] == 'main') {
        scores[element] = (scores[element] ?? 0) + 20;
      }
      if (const {'p', 'pre', 'blockquote', 'td'}.contains(element.localName) &&
          length >= 25) {
        final score = 1.0 + math.min(length / 100, 8);
        final parent = element.parent;
        if (parent != null) scores[parent] = (scores[parent] ?? 0) + score;
        final grandparent = parent?.parent;
        if (grandparent != null) {
          scores[grandparent] = (scores[grandparent] ?? 0) + score / 2;
        }
      }
    }
    dom.Element? selected;
    var best = -1.0;
    for (final entry in scores.entries) {
      final size = metrics[entry.key];
      if (size == null || size.$1 < 40) continue;
      final density = size.$2 / size.$1;
      if (density > .5) continue;
      final score = (entry.value + math.min(size.$1 / 200, 20)) * (1 - density);
      if (score > best) {
        best = score;
        selected = entry.key;
      }
    }
    if (selected == null) throw const ArticleCaptureFailure('empty');
    title = _plain(
        preferredTitle ?? selected.querySelector('h1')?.text ?? fallbackTitle);
    for (final heading in selected.querySelectorAll('h1')) {
      if (_plain(heading.text) == title) heading.remove();
    }
    body = _ArticleMarkdown(url).block(selected).trim();
  }
  title = _plain(title);
  if (title.isEmpty) title = url.host;
  if (title.length > 200) title = title.substring(0, 200);
  if (_plain(body).length < 40) throw const ArticleCaptureFailure('empty');
  final markdown =
      '# ${_escape(title)}\n\n[${_escape(url.host)}](<${url.toString()}>)\n\n$body\n';
  if (utf8.encode(markdown).length > 512 * 1024) {
    throw const ArticleCaptureFailure('size');
  }
  return CapturedArticle(title, url, markdown);
}

class _ArticleMarkdown {
  _ArticleMarkdown(this.url);
  final Uri url;

  String inline(dom.Node node) {
    if (node is dom.Text) {
      return _escape(node.data.replaceAll(RegExp(r'\s+'), ' '));
    }
    if (node is! dom.Element) return '';
    final content = node.nodes.map(inline).join();
    switch (node.localName) {
      case 'br':
        return '  \n';
      case 'strong':
      case 'b':
        return '**$content**';
      case 'em':
      case 'i':
        return '*$content*';
      case 's':
      case 'del':
        return '~~$content~~';
      case 'code':
        final fence = '`' *
            (RegExp(r'`+')
                    .allMatches(node.text)
                    .fold(0, (n, m) => math.max(n, m[0]!.length)) +
                1);
        return '$fence ${node.text.replaceAll('\n', ' ')} $fence';
      case 'a':
        final target = _link(node.attributes['href'], url);
        final label = _escape(_plain(node.text.isNotEmpty
            ? node.text
            : node.querySelector('img')?.attributes['alt'] ?? 'Link'));
        return target == null ? label : '[$label](<$target>)';
      case 'img':
        final target =
            _link(node.attributes['src'] ?? node.attributes['data-src'], url);
        final label = _escape(_plain(node.attributes['alt'] ?? 'Image'));
        return target == null ? label : '[$label](<$target>)';
      default:
        return content;
    }
  }

  String block(dom.Node node) {
    if (node is dom.Text) {
      return _plain(node.data).isEmpty ? '' : '${inline(node)}\n\n';
    }
    if (node is! dom.Element) return '';
    final tag = node.localName;
    if (RegExp(r'^h[1-6]$').hasMatch(tag ?? '')) {
      return '${'#' * int.parse(tag!.substring(1))} ${inline(node).trim()}\n\n';
    }
    if (tag == 'p') return '${inline(node).trim()}\n\n';
    if (tag == 'hr') return '---\n\n';
    if (tag == 'pre') {
      final text = node.text.trimRight();
      final width = math.max(
          3,
          RegExp(r'`+')
                  .allMatches(text)
                  .fold(0, (n, m) => math.max(n, m[0]!.length)) +
              1);
      final fence = '`' * width;
      return '$fence\n$text\n$fence\n\n';
    }
    if (tag == 'blockquote') {
      return '${node.nodes.map(block).join().trim().split('\n').map((v) => '> $v').join('\n')}\n\n';
    }
    if (tag == 'ul' || tag == 'ol') {
      var number = int.tryParse(node.attributes['start'] ?? '') ?? 1;
      final lines = <String>[];
      for (final item in node.children.where((v) => v.localName == 'li')) {
        final content = item.nodes
            .map((child) => child is dom.Element &&
                    const {'ul', 'ol', 'p'}.contains(child.localName)
                ? '\n${block(child)}'
                : inline(child))
            .join()
            .trim();
        final parts = content.split('\n');
        final marker = tag == 'ol' ? '${number++}.' : '-';
        lines.add('$marker ${parts.first}');
        final indent = ' ' * (marker.length + 1);
        lines.addAll(parts.skip(1).map((line) => '$indent$line'));
      }
      return '${lines.join('\n')}\n\n';
    }
    if (tag == 'table') {
      final rows = node
          .querySelectorAll('tr')
          .map((row) => row.children
              .where((cell) => const {'th', 'td'}.contains(cell.localName))
              .map((cell) =>
                  inline(cell).replaceAll('|', r'\|').replaceAll('\n', ' '))
              .toList())
          .where((row) => row.isNotEmpty)
          .toList();
      if (rows.isEmpty) return '';
      final width = rows.map((row) => row.length).reduce(math.max);
      String line(List<String> cells) =>
          '| ${List.generate(width, (i) => i < cells.length ? cells[i] : '').join(' | ')} |';
      return '${line(rows.first)}\n${line(List.filled(width, '---'))}\n${rows.skip(1).map(line).join('\n')}\n\n';
    }
    if (const {'a', 'img', 'strong', 'em', 'b', 'i', 'code', 'span'}
        .contains(tag)) {
      return inline(node);
    }
    return node.nodes.map(block).join();
  }
}
