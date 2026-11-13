import 'dart:io';
import 'dart:convert';
import 'package:modu_reader/service/weread/weread_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late WereadStore store;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('weread-store-test-');
    store = WereadStore('book-local-key', directory: dir);
  });
  tearDown(() => dir.delete(recursive: true));

  test(
      'binding and public cache survive reopen; no secret or local position retained',
      () async {
    final data =
        await store.bind({'bookId': 'b', 'title': '书', 'apiKey': 'secret'});
    final revision = WereadData.revision(data)!;
    await store.saveSection(revision, 'highlights', {
      'items': [
        {'text': '引用', 'count': 5, 'range': '1-2'},
      ]
    });
    final loaded = await WereadStore('book-local-key', directory: dir).read();
    expect(WereadData.bookId(loaded), 'b');
    expect(jsonEncode(loaded), isNot(contains('secret')));
    expect(jsonEncode(loaded), isNot(contains('range')));
    expect(WereadData.content(loaded, 'highlights')['items'], [
      {'text': '引用', 'count': 5}
    ]);
  });

  test('replace and unlink discard old generation and late responses',
      () async {
    final old = await store.bind({'bookId': 'a'});
    final next = await store.bind({'bookId': 'b'});
    await store
        .saveSection(WereadData.revision(old)!, 'reviews', {'items': []});
    expect(await store.read(), next);
    expect(WereadData.merge(next, old), next);
    final cleared = await store.bind(null);
    expect(WereadData.bookId(cleared), null);
    expect(WereadData.merge(cleared, next), cleared);
    expect(WereadData.merge(next, cleared), cleared);
  });

  test(
      'recommendation details remain unchanged through reopen and cross-device merge',
      () async {
    await store.bind({
      'bookId': 'b',
      'newRating': 83.6,
      'newRatingCount': 101,
      'newRatingDetail': {'good': 86, 'fair': 14, 'poor': 1},
      'wordCount': 364000,
      'cover': 'https://cdn.weread.qq.com/cover.jpg',
    });
    final other = WereadStore('another-device', directory: dir);
    final original = await store.read();
    await other.merge(original);
    await store.merge(await other.read());
    expect(WereadData.content(await store.read(), 'info'),
        WereadData.content(original, 'info'));
    expect(WereadData.content(await other.read(), 'info')['newRating'], 83.6);
  });

  test(
      'independent sections merge deterministically without overwriting local edits',
      () async {
    final initial = await store.bind({'bookId': 'b'});
    final other = WereadStore('other-device', directory: dir);
    await other.merge(initial);
    final revision = WereadData.revision(initial)!;
    final a = await store
        .saveSection(revision, 'reviews', {'items': [], 'total': 10});
    final b = await other.saveSection(revision, 'highlights', {
      'items': [
        {'text': 'quote', 'count': 1}
      ]
    });
    expect(WereadData.merge(a, b), WereadData.merge(b, a));
    await store.merge(b);
    expect(WereadData.content(await store.read(), 'reviews')['total'], 10);
    expect(WereadData.content(await store.read(), 'highlights')['items'],
        hasLength(1));
  });

  test('concurrent refreshes under shared write lock keep both sections',
      () async {
    final first = await store.bind({'bookId': 'b'});
    final second = WereadStore('book-local-key', directory: dir);
    await Future.wait([
      store.saveSection(WereadData.revision(first)!, 'reviews', {'items': []}),
      second.saveSection(
          WereadData.revision(first)!, 'highlights', {'items': []}),
    ]);
    expect(
        (await store.read())['sections'], containsPair('reviews', isNotNull));
    expect((await store.read())['sections'],
        containsPair('highlights', isNotNull));
  });

  test('cross-book section injection rejected without losing saved cache',
      () async {
    final first = await store.bind({'bookId': 'b'});
    await expectLater(
        store.saveSection(
            WereadData.revision(first)!, 'info', {'bookId': 'evil'}),
        throwsA(isA<FormatException>()));
    expect(await store.read(), first);
  });
}
