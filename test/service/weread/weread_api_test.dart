import 'dart:convert';
import 'package:modu_reader/service/weread/weread_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
      'official gateway, flat parameters, version, scope 17 results, no body upload',
      () async {
    final api = WereadApi('wrk-test', client: MockClient((request) async {
      expect(
          request.url.toString(), 'https://i.weread.qq.com/api/agent/gateway');
      expect(request.followRedirects, false);
      expect(request.headers['Authorization'], 'Bearer wrk-test');
      expect(jsonDecode(request.body), {
        'api_name': '/store/search',
        'skill_version': '1.0.5',
        'keyword': '三体 刘慈欣',
        'scope': 10,
        'maxIdx': 0,
      });
      return http.Response(
          jsonEncode({
            'hasMore': 1,
            'results': [
              {
                'scope': 17,
                'books': [
                  {
                    'searchIdx': 10,
                    'bookInfo': {'bookId': 'b1', 'title': '三体'}
                  }
                ]
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    final result = await api.search('三体', '刘慈欣');
    expect(result.books.single['bookId'], 'b1');
    expect(result.hasMore, true);
    expect(result.cursor, 10);
    api.close();
  });

  test('scores stay percent, details and links are whitelisted', () {
    final data = wereadInfo({
      'bookId': 'b',
      'newRating': 75.4,
      'newRatingCount': 1454,
      'translator': '译者',
      'isbn': '123',
      'htmlContent': '<script>x</script>',
      'accessToken': 'DO-NOT-COPY',
      'cover': 'https://cdn.weread.qq.com/cover.jpg',
      'readerLink': 'https://weread.qq.com/web/reader/a',
    });
    expect(data['newRating'], 75.4);
    expect(data['newRatingCount'], 1454);
    expect(data['translator'], '译者');
    expect(data, isNot(contains('accessToken')));
    expect(data, isNot(contains('htmlContent')));
    expect(wereadLink('https://weread.qq.com.evil.test/x'), isNull);
    expect(wereadLink('file:///private/secret'), isNull);
    expect(wereadLink('https://user:password@weread.qq.com/x'), isNull);
    expect(wereadLink('https://127.0.0.1/x', cover: true), isNull);
    expect(wereadLink('weread://reader/book'), isNotNull);
  });

  test('gateway tenths convert once; rating distribution survives cache reads',
      () async {
    final raw = {
      'bookId': 'b',
      'newRating': 836,
      'newRatingCount': 101,
      'newRatingDetail': {
        'good': 86,
        'fair': 14,
        'poor': 1,
        'myRating': 'private'
      },
      'wordCount': 364000,
    };
    final api = WereadApi('wrk-test',
        client: MockClient((_) async => http.Response(jsonEncode(raw), 200)));
    final info = await api.info('b');
    expect(info['newRating'], 83.6);
    expect(info['newRatingDetail'], {'good': 86, 'fair': 14, 'poor': 1});
    expect(info['wordCount'], 364000);
    expect(wereadInfo(wereadInfo(info)), info);
    for (final value in [0, 83, 100, 1000]) {
      expect(
          wereadInfo({...raw, 'newRating': value},
              fromGateway: true)['newRating'],
          value / 10);
    }
    for (final value in [-1, 1001, double.nan, double.infinity, '836', null]) {
      expect(wereadInfo({...raw, 'newRating': value}, fromGateway: true),
          isNot(contains('newRating')));
    }
    api.close();
  });

  test('double nested public reviews, pagination and no local positions',
      () async {
    final api = WereadApi('wrk-test', client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      expect(body['maxIdx'], 22);
      expect(body['synckey'], 7);
      expect(body['reviewListType'], 0);
      return http.Response(
          jsonEncode({
            'synckey': 8,
            'reviewsHasMore': 1,
            'reviewsCnt': 100,
            'reviews': [
              {
                'idx': 44,
                'review': {
                  'reviewId': 'r1',
                  'review': {
                    'content': '好书',
                    'star': 80,
                    'createTime': 1748563200,
                    'author': {'name': '读者', 'userVid': 123},
                  }
                }
              }
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    final result = await api.reviews('b', cursor: 22, synckey: 7);
    expect(result['items'], [
      {
        'id': 'r1',
        'idx': 44,
        'content': '好书',
        'author': '读者',
        'star': 80,
        'createTime': 1748563200
      }
    ]);
    expect(result['maxIdx'], 44);
    expect(result['synckey'], 8);
    expect(result['hasMore'], true);
    expect(
        wereadHighlights({
          'items': [
            {
              'markText': '划线',
              'totalCount': 3,
              'range': '1-10',
              'chapterUid': 50,
            }
          ]
        })['items'],
        [
          {'text': '划线', 'count': 3}
        ]);
  });

  for (final error in [
    'upgrade',
    'api',
    'malformed',
    'redirect',
    'unauthorized'
  ]) {
    test('sanitized $error failure without key or server payload', () async {
      final api = WereadApi('wrk-secret', client: MockClient((request) async {
        return switch (error) {
          'upgrade' =>
            http.Response('{"upgrade_info":{"message":"secret"}}', 200),
          'api' => http.Response('{"errcode":9,"errmsg":"wrk-secret"}', 200),
          'malformed' => http.Response('<html>wrk-secret</html>', 200),
          'redirect' =>
            http.Response('', 302, headers: {'location': 'https://evil.test'}),
          _ => http.Response('wrk-secret', 401),
        };
      }));
      await expectLater(
          api.info('b'),
          throwsA(isA<WereadException>().having((error) => error.toString(),
              'no key', isNot(contains('wrk-secret')))));
    });
  }

  test('wrong book and oversized response fail closed', () async {
    final wrong = WereadApi('wrk-test',
        client:
            MockClient((_) async => http.Response('{"bookId":"other"}', 200)));
    await expectLater(wrong.info('b'), throwsA(isA<WereadException>()));
    final large = WereadApi('wrk-test',
        client: MockClient(
            (_) async => http.Response('a' * (2 * 1024 * 1024 + 1), 200)));
    await expectLater(large.info('b'), throwsA(isA<WereadException>()));
  });

  test('cover requests never carry API key; arbitrary image hosts rejected',
      () async {
    final api = WereadApi('wrk-test', client: MockClient((request) async {
      expect(request.headers.containsKey('Authorization'), false);
      expect(request.followRedirects, false);
      return http.Response.bytes([1, 2, 3], 200);
    }));
    expect(await api.cover('https://cdn.weread.qq.com/cover/a.jpg'), [1, 2, 3]);
    expect(() => api.cover('https://example.com/a.jpg'),
        throwsA(isA<WereadException>()));
  });
}
