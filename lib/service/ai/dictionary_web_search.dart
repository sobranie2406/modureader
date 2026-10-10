import 'dart:async';
import 'dart:convert';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

class DictionarySearchHit {
  const DictionarySearchHit(this.title, this.snippet, this.url);
  final String title;
  final String snippet;
  final Uri url;

  String get sourceName => url.host == 'baike.baidu.com'
      ? '百度百科'
      : url.host.endsWith('.wiktionary.org')
          ? '维基词典'
          : url.host.endsWith('.wikipedia.org')
              ? '维基百科'
              : url.host;

  Map<String, String> toJson() => {
        'title': title,
        'snippet': snippet,
        'url': url.toString(),
        'site': sourceName,
      };
}

class DictionarySearchResult {
  const DictionarySearchResult(this.hits, {this.hasFailures = false});
  final List<DictionarySearchHit> hits;
  final bool hasFailures;
}

/// Public MediaWiki APIs and Baidu Baike entries; no credentials or book
/// context are sent. Access challenges are failures, never dictionary content.
/// The search covers online dictionaries/encyclopedias, not the whole web.
class DictionaryWebSearch {
  DictionaryWebSearch({
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 12),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final http.Client Function() _clientFactory;
  final Duration timeout;

  Future<DictionarySearchResult> search(String term,
      {Future<void>? cancelled,
      Set<String> sites = const {'wiktionary', 'wikipedia', 'baidu'}}) async {
    term = term.trim();
    if (term.isEmpty || term.length > 500) {
      return const DictionarySearchResult([], hasFailures: true);
    }
    final client = _clientFactory();
    final finished = Completer<void>();
    if (cancelled != null) {
      unawaited(Future.any([cancelled, finished.future]).then((_) {
        if (!finished.isCompleted) {
          client.close();
        }
      }));
    }
    try {
      final language = RegExp(r'[\u3400-\u9fff]').hasMatch(term) ? 'zh' : 'en';
      final pending = Future.wait([
        for (final site in ['wiktionary', 'wikipedia'])
          if (sites.contains(site))
            _searchSite(client, '$language.$site.org', term).timeout(timeout,
                onTimeout: () =>
                    const DictionarySearchResult([], hasFailures: true)),
        if (sites.contains('baidu'))
          _searchBaiduBaike(client, term).timeout(timeout,
              onTimeout: () =>
                  const DictionarySearchResult([], hasFailures: true)),
      ]);
      final results = await Future.any([
        pending,
        if (cancelled != null)
          cancelled.then((_) => <DictionarySearchResult>[]),
      ]);
      return DictionarySearchResult(
        results.expand((r) => r.hits).toList(growable: false),
        hasFailures: results.any((r) => r.hasFailures),
      );
    } catch (_) {
      return const DictionarySearchResult([], hasFailures: true);
    } finally {
      finished.complete();
      client.close();
    }
  }

  Future<DictionarySearchResult> _searchBaiduBaike(
      http.Client client, String term) async {
    try {
      var uri = Uri(
          scheme: 'https',
          host: 'baike.baidu.com',
          pathSegments: ['item', term]);
      // Resolve a literal public entry. Never follow login/CAPTCHA redirects,
      // execute site scripts or use a different route to evade a challenge.
      for (var redirects = 0; redirects <= 2; redirects++) {
        final response = await client.send(http.Request('GET', uri)
          ..followRedirects = false
          ..headers['User-Agent'] =
              'ModuReader (dictionary lookup; https://github.com/sobranie2406/modureader)');
        if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
          await response.stream.listen((_) {}).cancel();
          final location = response.headers['location'];
          if (location == null || redirects == 2) break;
          final next = uri.resolve(location);
          if (!_isBaiduEntry(next)) break;
          uri = next;
          continue;
        }
        if (response.statusCode == 404) {
          await response.stream.listen((_) {}).cancel();
          return const DictionarySearchResult([]);
        }
        if (response.statusCode != 200) {
          await response.stream.listen((_) {}).cancel();
          break;
        }
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 2 * 1024 * 1024) {
            throw const FormatException('Baike response too large');
          }
          bytes.addAll(chunk);
        }
        final document = html.parse(utf8.decode(bytes));
        final pageTitle = document.querySelector('title')?.text.trim() ?? '';
        if (!pageTitle.endsWith('_百度百科') ||
            pageTitle.contains('安全验证') ||
            document.querySelector(
                    'script[src*="captcha"], script[src*="BiocFacade"]') !=
                null ||
            document
                .querySelectorAll('script')
                .any((script) => script.text.contains('BIOC_OPTIONS'))) {
          break;
        }
        final title = _plainText(
            pageTitle.substring(0, pageTitle.length - '_百度百科'.length), 200);
        final description = document
            .querySelector('meta[name="description"]')
            ?.attributes['content'];
        final summary = description ??
            document
                .querySelector('.lemma-summary, [class*="lemmaSummary"]')
                ?.text;
        if (title.isEmpty || summary == null) break;
        final snippet = _plainText(summary, 1500);
        if (snippet.isEmpty || snippet.startsWith('百度百科是一部')) break;
        final canonical =
            document.querySelector('link[rel="canonical"]')?.attributes['href'];
        final preferred = canonical == null ? uri : uri.resolve(canonical);
        final source = _isBaiduEntry(preferred) ? preferred : uri;
        return DictionarySearchResult([
          DictionarySearchHit(
              title, snippet, source.replace(query: '', fragment: '')),
        ]);
      }
    } catch (_) {
      // Keep other providers' successful results on parsing/network failures.
    }
    return const DictionarySearchResult([], hasFailures: true);
  }

  bool _isBaiduEntry(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'baike.baidu.com' &&
      uri.port == 443 &&
      uri.userInfo.isEmpty &&
      uri.path.startsWith('/item/');

  Future<DictionarySearchResult> _searchSite(
      http.Client client, String host, String term) async {
    try {
      // Quote the literal phrase instead of interpreting search operators or
      // splitting Chinese terms into unrelated individual characters.
      final phrase = term.replaceAll(RegExp(r'["\r\n]'), ' ');
      final uri = Uri.https(host, '/w/api.php', {
        'action': 'query',
        'list': 'search',
        'srsearch': '"$phrase"',
        'srnamespace': '0',
        'srprop': 'snippet',
        'srlimit': '3',
        'format': 'json',
        'utf8': '1',
      });
      final response = await client.send(http.Request('GET', uri)
        ..followRedirects = false
        ..headers['User-Agent'] =
            'ModuReader (dictionary lookup; https://github.com/sobranie2406/modureader)');
      if (response.statusCode != 200) {
        return const DictionarySearchResult([], hasFailures: true);
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 1024 * 1024) {
          throw const FormatException('Search response too large');
        }
        bytes.addAll(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final rows = (data['query'] as Map<String, dynamic>)['search'] as List;
      final hits = <DictionarySearchHit>[];
      for (final row in rows.take(3)) {
        final id = row['pageid'];
        final title = row['title'];
        final snippet = row['snippet'];
        if (id is! int || id <= 0 || title is! String || snippet is! String) {
          continue;
        }
        final text = _plainText(snippet, 1500);
        if (text.isEmpty) continue;
        hits.add(DictionarySearchHit(_plainText(title, 200), text,
            Uri.https(host, '/w/index.php', {'curid': '$id'})));
      }
      return DictionarySearchResult(hits);
    } catch (_) {
      return const DictionarySearchResult([], hasFailures: true);
    }
  }

  String _plainText(String value, int limit) {
    final fragment = html.parseFragment(value);
    for (final element in fragment.querySelectorAll('script, style')) {
      element.remove();
    }
    final text = (fragment.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= limit ? text : text.substring(0, limit);
  }
}
