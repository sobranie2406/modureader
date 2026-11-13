import 'dart:convert';
import 'dart:io';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/custom_css_profile.dart';
import 'package:modu_reader/service/sync/weread_metadata_sync.dart';
import 'package:modu_reader/service/weread/weread_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'document_reflow_sync_test.dart' show OcrClient;

void main() {
  late Directory temp, a, b;
  late OcrClient client;
  final bookA = Book.mock().copyWith(id: 1, md5: md5.convert([1]).toString());
  final bookB = bookA.copyWith(id: 50);
  WereadStore store(Directory dir, Book book) =>
      WereadStore(customCssBookKey(book),
          directory: Directory('${dir.path}/data'));
  Future<void> sync(Directory dir, Book book) => WereadMetadataSync(
      client: client,
      cache: Directory('${dir.path}/cache'),
      durableDirectory: dir,
      sourceFile: (book) => File('${dir.path}/${book.id}.epub'),
      store: (book) => store(dir, book)).sync([book]);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('weread-sync-test-');
    a = await Directory('${temp.path}/a').create();
    b = await Directory('${temp.path}/b').create();
    await File('${a.path}/1.epub').writeAsBytes([1]);
    await File('${b.path}/50.epub').writeAsBytes([1]);
    client = OcrClient();
  });
  tearDown(() => temp.delete(recursive: true));

  test(
      'links and sections follow same checksum across different local book IDs',
      () async {
    final initial =
        await store(a, bookA).bind({'bookId': 'wr1', 'intro': '外部简介'});
    await store(a, bookA)
        .saveSection(WereadData.revision(initial)!, 'reviews', {
      'items': [
        {'id': 'r1', 'content': '书评', 'author': 'reader', 'star': 100}
      ],
    });
    await sync(a, bookA);
    await sync(b, bookB);
    expect(WereadData.bookId(await store(b, bookB).read()), 'wr1');
    expect(WereadData.content(await store(b, bookB).read(), 'reviews')['items'],
        hasLength(1));
    final count = client.uploaded.length;
    await sync(b, bookB);
    expect(client.uploaded.length, count);
    expect(utf8.decode(client.files.values.first), isNot(contains('apiKey')));
  });

  test(
      'metadata syncs without downloading the original',
      () async {
    await store(a, bookA).bind({'bookId': 'wr1'});
    await sync(a, bookA);
    await File('${b.path}/50.epub').delete();
    final downloads = client.downloads;
    await sync(b, bookB);
    expect(client.downloads, greaterThan(downloads));
    expect(WereadData.bookId(await store(b, bookB).read()), 'wr1');
    await File('${b.path}/50.epub').writeAsBytes([1]);
    await sync(b, bookB);
    expect(WereadData.bookId(await store(b, bookB).read()), 'wr1');
  });

  test('unlink tombstone propagates; old cache does not resurrect association',
      () async {
    await store(a, bookA).bind({'bookId': 'wr1'});
    await sync(a, bookA);
    await sync(b, bookB);
    await store(b, bookB).bind(null);
    await sync(b, bookB);
    await sync(a, bookA);
    expect(WereadData.bookId(await store(a, bookA).read()), null);
    expect((await store(a, bookA).read())['sections'], isEmpty);
  });

  test('local rebind during download wins over old remote response', () async {
    await store(a, bookA).bind({'bookId': 'old'});
    await sync(a, bookA);
    client.afterDownload = () async {
      await store(b, bookB).bind({'bookId': 'new'});
    };
    await sync(b, bookB);
    await sync(a, bookA);
    expect(WereadData.bookId(await store(a, bookA).read()), 'new');
  });

  test('failed read-back retains pending publication and local link for retry',
      () async {
    await store(a, bookA).bind({'bookId': 'wr1'});
    client.corrupt = true;
    await expectLater(sync(a, bookA), throwsA(isA<FormatException>()));
    expect(WereadData.bookId(await store(a, bookA).read()), 'wr1');
    client.corrupt = false;
    await sync(a, bookA);
    await sync(b, bookB);
    expect(WereadData.bookId(await store(b, bookB).read()), 'wr1');
  });

  test('another checksum cannot reuse this book association', () async {
    await store(a, bookA).bind({'bookId': 'wr1'});
    await sync(a, bookA);
    final other = bookB.copyWith(id: 51, md5: md5.convert([2]).toString());
    await File('${b.path}/51.epub').writeAsBytes([2]);
    await sync(b, other);
    expect(WereadData.bookId(await store(b, other).read()), null);
  });
}
