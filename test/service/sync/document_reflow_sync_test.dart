import 'dart:convert';
import 'dart:io';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/custom_css_profile.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:modu_reader/service/sync/document_reflow_sync.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'replaced_book_files_test.dart' show CleanupClient;

class OcrClient extends CleanupClient {
  bool corrupt = false;
  int downloads = 0;
  Future<void> Function()? afterDownload;
  @override
  Future<void> uploadFile(String localPath, String remotePath,
      {bool replace = true,
      void Function(int, int)? onProgress,
      CancelToken? cancelToken}) async {
    await super.uploadFile(localPath, remotePath);
    if (corrupt) files[remotePath] = [0];
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath,
      {void Function(int, int)? onProgress}) async {
    downloads++;
    await super.downloadFile(remotePath, localPath, onProgress: onProgress);
    final action = afterDownload;
    afterDownload = null;
    await action?.call();
  }
}

void main() {
  late Directory temp, a, b;
  late OcrClient client;
  final bookA =
      Book.mock().copyWith(id: 5, md5: md5.convert([1, 2, 3]).toString());
  final bookB = bookA.copyWith(id: 90);
  DocumentReflowStore store(Directory device, Book book) =>
      DocumentReflowStore(customCssBookKey(book), directory: device);
  Future<void> sync(Directory device, Book book) => DocumentReflowSync(
      client: client,
      cache: Directory('${device.path}/cache'),
      durableDirectory: device,
      sourceFile: (book) => File('${device.path}/${book.id}.pdf'),
      store: (book) => store(device, book)).sync([book]);
  DocumentReflowPage page(int n, String text) =>
      DocumentReflowPage(page: n, ocr: true, rawText: text);
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ocr-sync-test-');
    a = await Directory('${temp.path}/a').create();
    b = await Directory('${temp.path}/b').create();
    await File('${a.path}/${bookA.id}.pdf').writeAsBytes([1, 2, 3]);
    await File('${b.path}/${bookB.id}.pdf').writeAsBytes([1, 2, 3]);
    client = OcrClient();
  });
  tearDown(() async => temp.delete(recursive: true));

  test(
      'same original book maps different IDs; OCR, edits and note revisions travel',
      () async {
    final original = page(0, '原始文字');
    await store(a, bookA).save(original, '', onlyIfAbsent: true);
    await store(a, bookA).saveEdit(original, '校对文字');
    await store(a, bookA).save(page(3, '第四页'), '', onlyIfAbsent: true);
    await sync(a, bookA);
    await sync(b, bookB);
    expect((await store(b, bookB).read(0, ''))!.text, '校对文字');
    expect((await store(b, bookB).readAnchor(original.anchor(0, 2)))!.text,
        '原始文字');
    expect(await store(b, bookB).cachedPages(0, 5), {0, 3});
    expect(await store(b, bookB).exportTxt(), contains('第4页'));
    final other = bookB.copyWith(id: 91, md5: md5.convert([4]).toString());
    await File('${b.path}/91.pdf').writeAsBytes([4]);
    await sync(b, other);
    expect(await store(b, other).read(0, ''), isNull);
    final uploads = client.uploaded.length, downloads = client.downloads;
    await sync(b, bookB);
    expect(client.uploaded.length, uploads);
    expect(client.downloads, downloads);
  });

  test(
      'OCR syncs even when the original is not available on this device',
      () async {
    await store(a, bookA).save(page(0, '随原书缓存'), '', onlyIfAbsent: true);
    await sync(a, bookA);
    final source = File('${b.path}/${bookB.id}.pdf');
    await source.delete();
    final downloads = client.downloads;
    await sync(b, bookB);
    expect(client.downloads, greaterThan(downloads));
    expect((await store(b, bookB).read(0, ''))!.text, '随原书缓存');
    await source.writeAsBytes([1, 2, 3]);
    await sync(b, bookB);
    expect((await store(b, bookB).read(0, ''))!.text, '随原书缓存');
  });

  test(
      'offline page sets merge, edits beat passive OCR and explicit rerun propagates',
      () async {
    final original = page(0, '旧字');
    await store(a, bookA).save(original, '', onlyIfAbsent: true);
    await store(a, bookA).saveEdit(original, '校对字');
    await store(b, bookB).save(page(0, '自动识别另一版'), '', onlyIfAbsent: true);
    await store(b, bookB).save(page(1, '第二页'), '', onlyIfAbsent: true);
    await sync(a, bookA);
    await sync(b, bookB);
    await sync(a, bookA);
    expect((await store(a, bookA).read(0, ''))!.text, '校对字');
    expect(await store(a, bookA).cachedPages(0, 5), {0, 1});
    expect(client.files.length, 1);
    await store(b, bookB).save(page(0, '明确重新识别'), '');
    await sync(b, bookB);
    await sync(a, bookA);
    expect((await store(a, bookA).read(0, ''))!.text, '明确重新识别');
    expect(
        (await store(a, bookA).readAnchor(original.anchor(0, 2)))!.text, '旧字');
  });

  test(
      'concurrent corrections converge without losing either immutable revision',
      () async {
    final original = page(0, '同一页');
    await store(a, bookA).save(original, '', onlyIfAbsent: true);
    await sync(a, bookA);
    await sync(b, bookB);
    final first = await store(a, bookA).saveEdit(original, '甲校对');
    final second = await store(b, bookB).saveEdit(original, '乙校对');
    await sync(a, bookA);
    await sync(b, bookB);
    await sync(a, bookA);
    expect(await store(a, bookA).syncSnapshot(),
        await store(b, bookB).syncSnapshot());
    for (final revision in [first, second]) {
      expect((await store(a, bookA).readAnchor(revision.anchor(0, 2)))!.text,
          revision.text);
    }
  });

  test(
      'interrupted upload retains pending snapshot and retries without data loss',
      () async {
    await store(a, bookA).save(page(0, '第一页'), '');
    client.corrupt = true;
    await expectLater(sync(a, bookA), throwsFormatException);
    expect((await store(a, bookA).read(0, ''))!.text, '第一页');
    client.corrupt = false;
    await store(a, bookA).save(page(1, '第二页'), '');
    await sync(a, bookA);
    await sync(b, bookB);
    expect(await store(b, bookB).cachedPages(0, 5), {0, 1});
    expect(client.files.length, 1);
  });

  test(
      'wrong original identity is rejected before importing or overwriting local results',
      () async {
    await store(a, bookA).save(page(0, '远端'), '');
    await sync(a, bookA);
    final data = jsonDecode(utf8.decode(client.files.values.single));
    data['bookMd5'] = md5.convert([99]).toString();
    final bytes = utf8.encode(jsonEncode(data));
    client.files.clear();
    client.files[
            '${DocumentReflowSync.root}/${bookA.md5}/${sha256.convert(bytes)}.json'] =
        bytes;
    await store(b, bookB).save(page(1, '本机保留'), '');
    await expectLater(sync(b, bookB), throwsFormatException);
    expect(await store(b, bookB).read(0, ''), isNull);
    expect((await store(b, bookB).read(1, ''))!.text, '本机保留');
  });

  test(
      'editing during download is included, not replaced by the starting snapshot',
      () async {
    await store(a, bookA).save(page(0, '远端'), '');
    await sync(a, bookA);
    final original = page(1, '本机');
    await store(b, bookB).save(original, '', onlyIfAbsent: true);
    client.afterDownload = () async {
      await store(b, bookB).saveEdit(original, '同步中校对');
    };
    await sync(b, bookB);
    await sync(a, bookA);
    expect((await store(a, bookA).read(1, ''))!.text, '同步中校对');
  });
}
