import 'dart:async';
import 'dart:io';
import 'package:anx_reader/service/sync/local_book_download.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late LocalBookDownload downloads;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-download-test-');
    downloads = LocalBookDownload();
  });
  tearDown(() => root.delete(recursive: true));

  test('replacement downloads once; reopening and syncing reuse local bytes',
      () async {
    await File('${root.path}/old.epub').writeAsString('old');
    final target = File('${root.path}/replacement.epub');
    final bytes = [1, 2, 3, 4];
    var requests = 0;
    Future<void> receive(File temporary) async {
      requests++;
      expect(await target.exists(), isFalse);
      await temporary.writeAsBytes(bytes);
    }

    for (var i = 0; i < 3; i++) {
      await downloads.ensure(target,
          expectedMd5: md5.convert(bytes).toString(), download: receive);
      expect(await target.readAsBytes(), bytes);
    }
    expect(requests, 1);
    expect(root.listSync().whereType<Directory>(), isEmpty);
  });

  test('parallel requests share a transfer and only expose complete files',
      () async {
    final target = File('${root.path}/book.epub');
    final started = Completer<void>(), finish = Completer<void>();
    var requests = 0;
    Future<void> receive(File temporary) async {
      requests++;
      started.complete();
      await temporary.writeAsString('partial');
      await finish.future;
      await temporary.writeAsString('complete');
    }

    final first = downloads.ensure(target, download: receive);
    await started.future;
    final second = downloads.ensure(target, download: receive);
    expect(await target.exists(), isFalse);
    finish.complete();
    await Future.wait([first, second]);
    expect(requests, 1);
    expect(await target.readAsString(), 'complete');
  });

  test(
      'failed or corrupt transfer releases its lock and can retry without restart',
      () async {
    final target = File('${root.path}/book.epub');
    final expected = md5.convert([1, 2, 3]).toString();
    await expectLater(
        downloads.ensure(target, expectedMd5: expected, download: (file) async {
          await file.writeAsBytes([0]);
        }),
        throwsFormatException);
    expect(await target.exists(), isFalse);
    expect(root.listSync(), isEmpty);
    await expectLater(
        downloads.ensure(target, download: (_) async {
          throw const SocketException('offline');
        }),
        throwsA(isA<SocketException>()));
    await downloads.ensure(target, expectedMd5: expected,
        download: (file) async {
      await file.writeAsBytes([1, 2, 3]);
    });
    expect(await target.readAsBytes(), [1, 2, 3]);
  });

  test('same-path replacement is verified instead of trusting file existence',
      () async {
    final target = await File('${root.path}/book.epub').writeAsBytes([9]);
    await downloads.ensure(target, expectedMd5: md5.convert([7]).toString(),
        download: (file) async {
      await file.writeAsBytes([7]);
    });
    expect(await target.readAsBytes(), [7]);
  });
}
