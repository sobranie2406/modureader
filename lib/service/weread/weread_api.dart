import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Only the documented, read-only Agent gateway is used. Never send local text.
class WereadException implements Exception {
  const WereadException(this.code);
  final String code;
  @override
  String toString() => 'WeRead: $code';
}

Map<String, dynamic> wereadMap(Object? value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};
String wereadText(Object? value) => value is String ? value : '';
int wereadInt(Object? value) => value is num ? value.toInt() : 0;

Uri? wereadLink(Object? value, {bool cover = false}) {
  final uri = Uri.tryParse(wereadText(value));
  if (uri == null || uri.userInfo.isNotEmpty) return null;
  if (!cover && uri.scheme == 'weread' && uri.hasAuthority) return uri;
  if (uri.scheme != 'https' || (uri.hasPort && uri.port != 443)) return null;
  if (cover) {
    return uri.host == 'cdn.weread.qq.com' ? uri : null;
  }
  return uri.host == 'weread.qq.com' || uri.host.endsWith('.weread.qq.com')
      ? uri
      : null;
}

/// Whitelisting also prevents credentials, HTML and remote positions entering
/// the portable cache. All external content is displayed as plain text.
Map<String, dynamic> wereadInfo(Object? value, {bool fromGateway = false}) {
  final data = wereadMap(value);
  final id = wereadText(data['bookId']);
  if (id.isEmpty || id.length > 200) {
    throw const WereadException('invalidResponse');
  }
  final result = <String, dynamic>{
    'bookId': id,
    for (final key in [
      'title',
      'author',
      'translator',
      'intro',
      'publisher',
      'publishTime',
      'isbn',
      'category'
    ])
      key: wereadText(data[key]),
    'newRatingCount': wereadInt(data['newRatingCount']),
  };
  // The gateway returns tenths of a percent (836 = 83.6%).
  // Portable caches already contain percentages and must not be scaled again.
  final rawRating = data['newRating'];
  final rating = rawRating is num && fromGateway ? rawRating / 10 : rawRating;
  if (rating is num && rating.isFinite && rating >= 0 && rating <= 100) {
    result['newRating'] = rating;
  }
  final detail = wereadMap(data['newRatingDetail']);
  if (detail.isNotEmpty) {
    result['newRatingDetail'] = {
      for (final key in ['good', 'fair', 'poor'])
        if (detail[key] is num &&
            (detail[key] as num).isFinite &&
            (detail[key] as num) >= 0)
          key: wereadInt(detail[key]),
    };
  }
  if (data['wordCount'] is num &&
      (data['wordCount'] as num).isFinite &&
      (data['wordCount'] as num) >= 0) {
    result['wordCount'] = wereadInt(data['wordCount']);
  }
  for (final key in ['cover', 'readerLink', 'deepLink']) {
    final uri = wereadLink(data[key], cover: key == 'cover');
    if (uri != null) result[key] = uri.toString();
  }
  return result;
}

Map<String, dynamic> wereadReviews(Object? value) {
  final data = wereadMap(value);
  if (data['reviews'] is! List) {
    throw const WereadException('invalidResponse');
  }
  final rows = <Map<String, dynamic>>[];
  for (final raw in (data['reviews'] as List).take(20)) {
    final item = wereadMap(raw);
    final wrapper = wereadMap(item['review']);
    final review = wereadMap(wrapper['review']);
    rows.add({
      'id': wereadText(wrapper['reviewId']),
      'idx': wereadInt(item['idx']),
      'content': wereadText(review['content']),
      'author': wereadText(wereadMap(review['author'])['name']),
      'star': wereadInt(review['star']),
      'createTime': wereadInt(review['createTime']),
    });
  }
  return {
    'items': rows,
    'total': wereadInt(data['reviewsCnt']),
    'hasMore': data['reviewsHasMore'] == 1,
    'synckey': wereadInt(data['synckey']),
    'maxIdx': rows.isEmpty ? 0 : rows.last['idx'],
  };
}

Map<String, dynamic> wereadHighlights(Object? value) {
  final data = wereadMap(value);
  if (data['items'] is! List) {
    throw const WereadException('invalidResponse');
  }
  return {
    'items': [
      for (final raw in (data['items'] as List).take(20))
        {
          'text': wereadText(wereadMap(raw)['markText']),
          'count': wereadInt(wereadMap(raw)['totalCount']),
        }
    ],
  };
}

class WereadSearchPage {
  const WereadSearchPage(this.books, this.hasMore, this.cursor);
  final List<Map<String, dynamic>> books;
  final bool hasMore;
  final int cursor;
}

class WereadApi {
  WereadApi(this.key, {http.Client? client})
      : _client = client ?? http.Client();
  final String key;
  final http.Client _client;
  static final gateway = Uri.https('i.weread.qq.com', '/api/agent/gateway');
  static const skillVersion = '1.0.6';

  void close() => _client.close();

  Future<Uint8List> _bytes(http.Request request, int limit) async {
    try {
      return await (() async {
        request.followRedirects = false;
        final response = await _client.send(request);
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw const WereadException('unauthorized');
        }
        if (response.statusCode != 200) {
          throw const WereadException('network');
        }
        if ((response.contentLength ?? 0) > limit) {
          throw const WereadException('tooLarge');
        }
        final out = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (out.length + chunk.length > limit) {
            throw const WereadException('tooLarge');
          }
          out.add(chunk);
        }
        return out.takeBytes();
      })()
          .timeout(const Duration(seconds: 20));
    } on WereadException {
      rethrow;
    } on Exception {
      // Network errors may embed headers/URLs: never surface their raw strings.
      throw const WereadException('network');
    }
  }

  Future<Map<String, dynamic>> _call(
      String api, Map<String, dynamic> parameters) async {
    if (!RegExp(r'^wrk-[A-Za-z0-9_-]+$').hasMatch(key)) {
      throw const WereadException('unauthorized');
    }
    final request = http.Request('POST', gateway)
      ..headers.addAll({
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({
        'api_name': api,
        'skill_version': skillVersion,
        ...parameters,
      });
    final bytes = await _bytes(request, 2 * 1024 * 1024);
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const WereadException('invalidResponse');
      }
      if (decoded['errcode'] != null && decoded['errcode'].toString() != '0') {
        throw const WereadException('apiError');
      }
      return decoded;
    } on WereadException {
      rethrow;
    } catch (_) {
      throw const WereadException('invalidResponse');
    }
  }

  Future<WereadSearchPage> search(String title, String author,
      {int cursor = 0}) async {
    final keyword = [title.trim(), author.trim()]
        .where((part) => part.isNotEmpty)
        .join(' ');
    if (keyword.isEmpty || keyword.length > 500) {
      throw const WereadException('invalidQuery');
    }
    final data = await _call(
        '/store/search', {'keyword': keyword, 'scope': 10, 'maxIdx': cursor});
    if (data['results'] is! List) {
      throw const WereadException('invalidResponse');
    }
    final books = <Map<String, dynamic>>[];
    var next = cursor;
    for (final group in data['results'] as List) {
      final rawBooks = wereadMap(group)['books'];
      if (rawBooks is! List) continue;
      for (final raw in rawBooks.take(100)) {
        final row = wereadMap(raw);
        final info = wereadMap(row['bookInfo']);
        if (wereadText(info['bookId']).isEmpty) continue;
        books.add(wereadInfo(info, fromGateway: true));
        next = wereadInt(row['searchIdx']);
      }
    }
    return WereadSearchPage(books,
        data['hasMore'] == 1 && next != cursor && books.isNotEmpty, next);
  }

  Future<Map<String, dynamic>> info(String id) async {
    final result = wereadInfo(await _call('/book/info', {'bookId': id}),
        fromGateway: true);
    if (result['bookId'] != id) throw const WereadException('invalidResponse');
    return result;
  }

  Future<Map<String, dynamic>> reviews(String id,
          {int cursor = 0, int synckey = 0}) async =>
      wereadReviews(await _call('/review/list', {
        'bookId': id,
        'reviewListType': 0,
        'count': 20,
        'maxIdx': cursor,
        'synckey': synckey,
      }));

  Future<Map<String, dynamic>> highlights(String id) async =>
      wereadHighlights(await _call('/book/bestbookmarks', {'bookId': id}));

  Future<Uint8List> cover(String url) {
    final uri = wereadLink(url, cover: true);
    if (uri == null) throw const WereadException('invalidResponse');
    // No Authorization header is ever sent to the image CDN.
    return _bytes(http.Request('GET', uri), 5 * 1024 * 1024);
  }
}
