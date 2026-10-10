import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;
import 'package:anx_reader/service/dictionary/local_dictionary.dart';

enum OnlineDictionary {
  wiktionaryZh('维基词典 · 中文', 'Wiktionary · Chinese'),
  wiktionaryEn('维基词典 · 英文', 'Wiktionary · English');

  const OnlineDictionary(this.zh, this.en);
  final String zh, en;
}

/// Text-only lookups. Never render remote HTML or load its images/scripts/audio.
class OnlineDictionaryService {
  OnlineDictionaryService({Dio? dio}) : _dio = dio ?? Dio();
  final Dio _dio;
  final _cache = <String, List<DictionaryEntry>>{};
  void close() => _dio.close(force: true);

  Future<List<DictionaryEntry>> lookup(OnlineDictionary source, String word,
      {CancelToken? cancelToken}) async {
    final query = word.trim();
    if (query.isEmpty || query.length > 256) return [];
    final key = '${source.name}:$query';
    if (_cache.containsKey(key)) return _cache[key]!;
    final requestToken = cancelToken ?? CancelToken();
    final host = source == OnlineDictionary.wiktionaryZh
        ? 'zh.wiktionary.org'
        : 'en.wiktionary.org';
    final uri = Uri.https(host, '/w/api.php', {
      'action': 'parse',
      'page': query,
      'prop': 'text|revid',
      'format': 'json',
      'formatversion': '2',
      'redirects': '1',
      'disableeditsection': '1',
    });
    final entries = await (() async {
      final response = await _dio.getUri<ResponseBody>(uri,
          cancelToken: requestToken,
          options: Options(
              responseType: ResponseType.stream,
              followRedirects: false,
              sendTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 12),
              validateStatus: (s) => s == 200 || s == 404,
              headers: {
                'User-Agent':
                    'ModuReader/1.2 (https://github.com/sobranie2406/modureader)'
              }));
      final body = response.data;
      if (body == null) {
        throw const FormatException('Missing dictionary response');
      }
      if (response.statusCode == 404) {
        await body.stream.listen(null).cancel();
        return <DictionaryEntry>[];
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in body.stream) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024) {
          throw const FormatException('Dictionary response too large');
        }
        bytes.add(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes.takeBytes()));
      return parseWiktionary(data, source);
    })()
        .timeout(const Duration(seconds: 15), onTimeout: () {
      requestToken.cancel('Dictionary timeout');
      throw const DictionaryFailure('timeout');
    });
    if (_cache.length >= 32) _cache.remove(_cache.keys.first);
    _cache[key] = entries;
    return entries;
  }
}

List<DictionaryEntry> parseWiktionary(dynamic data, OnlineDictionary source) {
  if (data is! Map) throw const FormatException('Invalid dictionary response');
  if (data['error'] is Map && data['error']['code'] == 'missingtitle') {
    return [];
  }
  final page = data['parse'];
  if (page is! Map || page['text'] is! String || page['title'] is! String) {
    throw const FormatException('Invalid Wiktionary page');
  }
  final document = html.parse(page['text'] as String);
  for (final node in document.querySelectorAll(
      'script,style,table,dl,ul,sup,.mw-editsection,.references,.citation,.quotation')) {
    node.remove();
  }
  final lines = <String>[];
  var language = '', part = '', lastHeading = '';
  for (final node in document.querySelectorAll('h2,h3,h4,ol > li')) {
    final text = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (node.localName == 'h2') {
      language = text;
      part = '';
      continue;
    }
    if (node.localName == 'h3' || node.localName == 'h4') {
      part = text;
      continue;
    }
    // A nested sense is already included in its parent; avoid duplicate text.
    var nested = false;
    for (var parent = node.parent; parent != null; parent = parent.parent) {
      if (parent.localName == 'li') {
        nested = true;
        break;
      }
    }
    if (nested || text.isEmpty) continue;
    final heading = [language, part].where((s) => s.isNotEmpty).join(' · ');
    if (heading.isNotEmpty && heading != lastHeading) lines.add(heading);
    lastHeading = heading;
    lines.add(text.length > 2000 ? '${text.substring(0, 2000)}…' : text);
    if (lines.length >= 40) break;
  }
  if (lines.isEmpty) return [];
  final host = source == OnlineDictionary.wiktionaryZh
      ? 'zh.wiktionary.org'
      : 'en.wiktionary.org';
  final title = page['title'] as String;
  return [
    DictionaryEntry(source.en, title, lines.join('\n\n'),
        sourceUri: Uri.https(host, '/w/index.php', {
          'title': title,
          if (page['revid'] is int) 'oldid': '${page['revid']}',
        }),
        license: 'CC BY-SA 4.0',
        licenseUri:
            Uri.parse('https://creativecommons.org/licenses/by-sa/4.0/'),
        attribution: 'Wiktionary contributors')
  ];
}
