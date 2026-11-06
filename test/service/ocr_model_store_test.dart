import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:anx_reader/service/ocr/ocr_model_store.dart';
import 'package:anx_reader/service/ocr/ocr_models.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class Adapter implements HttpClientAdapter {
  Adapter(this.handle);
  final ResponseBody Function(RequestOptions) handle;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    return handle(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final data = [1, 2, 3, 4];
  final model = OcrModelSpec('test-model', 'test', 'test', {
    'det.onnx': ('test/det.onnx', 4, sha256.convert(data).toString()),
    'rec.onnx': ('test/rec.onnx', 4, sha256.convert(data).toString()),
  });
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ocr-store-test-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  OcrModelStore create(Adapter adapter) => OcrModelStore(
      model: model, directory: dir, dio: Dio()..httpClientAdapter = adapter);

  test(
      'delete removes only this pack and partial files, retaining unrelated data',
      () async {
    final store = create(Adapter((_) => ResponseBody.fromBytes(data, 200)));
    addTearDown(store.close);
    await store.download(CancelToken(), (_, __) {});
    await File('${dir.path}/det.onnx.part').writeAsBytes(data);
    final unrelated = File('${dir.path}/recognized-text.json');
    await unrelated.writeAsString('keep');
    expect(await store.hasLocalFiles(), isTrue);
    await store.deleteDownloaded();
    expect(await store.hasLocalFiles(), isFalse);
    expect(await store.available(), isFalse);
    expect(await unrelated.readAsString(), 'keep');
    expect(await dir.exists(), isTrue);
    await store.deleteDownloaded(); // idempotent
    await store.download(CancelToken(), (_, __) {});
    expect(await store.available(), isTrue);
  });

  test(
      'recognition lease blocks deletion and replacement across store instances',
      () async {
    final store = create(Adapter((_) => ResponseBody.fromBytes(data, 200)));
    final second = create(Adapter((_) => ResponseBody.fromBytes(data, 200)));
    addTearDown(store.close);
    addTearDown(second.close);
    await store.download(CancelToken(), (_, __) {});
    final finished = Completer<void>();
    final reading = store.withModelFiles(() => finished.future);
    await expectLater(second.deleteDownloaded(), throwsStateError);
    await expectLater(
        second.download(CancelToken(), (_, __) {}), throwsStateError);
    expect(await store.available(), isTrue);
    finished.complete();
    await reading;
    await second.deleteDownloaded();
    expect(await store.available(), isFalse);
    await expectLater(
        store.withModelFiles(() async => throw StateError('worker failure')),
        throwsStateError);
    await second.deleteDownloaded(); // failure releases the lease too
  });

  test(
      'deletion does not follow model symlinks or recursively delete unexpected directories',
      () async {
    final store = create(Adapter((_) => ResponseBody.fromBytes(data, 200)));
    addTearDown(store.close);
    final kept = File('${dir.path}/other-model.onnx');
    await kept.writeAsBytes(data);
    await Link('${dir.path}/det.onnx').create(kept.path);
    await store.deleteDownloaded();
    expect(await kept.readAsBytes(), data);
    await Directory('${dir.path}/det.onnx').create();
    await File('${dir.path}/rec.onnx').writeAsBytes(data);
    await expectLater(store.deleteDownloaded(), throwsStateError);
    expect(await File('${dir.path}/rec.onnx').exists(), isTrue);
    await store.withModelFiles(() async {}); // failed deletion releases lock
  });

  test('catalog retains legacy packs and adds pinned V6 models', () {
    expect(OcrModels.all.length, 6);
    expect(OcrModels.all.map((m) => m.id).toSet().length, 6);
    expect(OcrModels.byId('unknown'), OcrModels.defaultModel);
    for (final model in OcrModels.all) {
      expect(model.totalBytes, lessThan(150 * 1024 * 1024));
      expect(model.files.keys, containsAll(['det.onnx', 'rec.onnx']));
      for (final spec in model.files.values) {
        expect(spec.$3, matches(RegExp(r'^[0-9a-f]{64}$')));
      }
      final store = OcrModelStore(model: model);
      for (final source in OcrDownloadSource.values) {
        final uri = Uri.parse(store.downloadUrl('rec.onnx', source));
        expect(OcrModelStore.allowedDownloadUri(uri, source), isTrue);
        if (!model.files['rec.onnx']!.$1.startsWith('https://') ||
            source == OcrDownloadSource.gitee) {
          expect(uri.path, contains(model.revision));
        }
      }
      store.close();
    }
  });

  test('V6 manifest agrees with catalog and has unique mirror URLs', () async {
    final manifest =
        jsonDecode(await File('docs/ocr-v6-manifest.json').readAsString());
    final mirrors = <String>{};
    for (final entry in manifest['models']) {
      final model = OcrModels.byId(entry['id']);
      final store = OcrModelStore(model: model);
      addTearDown(store.close);
      expect(model.files.length, entry['files'].length);
      for (final file in entry['files']) {
        final name = file['local'] as String;
        expect(model.files[name]!.$2, file['size']);
        expect(model.files[name]!.$3, file['sha256']);
        expect(store.downloadUrl(name, OcrDownloadSource.upstream),
            file['source']);
        final mirror = store.downloadUrl(name, OcrDownloadSource.gitee);
        expect(mirror, file['mirror']);
        expect(mirrors.add(mirror), isTrue);
      }
    }
    expect(mirrors.length, 6);
  });

  test('offline import requires sidecar and deletion removes it safely',
      () async {
    final files = {
      'det.onnx': [1, 2],
      'rec.onnx': [3, 4],
      'rec.yml': [5, 6]
    };
    final spec = OcrModelSpec('test-v6', 'test', 'test', {
      for (final entry in files.entries)
        entry.key: (
          entry.key,
          entry.value.length,
          sha256.convert(entry.value).toString()
        ),
    });
    final store = OcrModelStore(
        model: spec, directory: Directory('${dir.path}/installed'));
    addTearDown(store.close);
    final inputs = <File>[];
    for (final entry in files.entries) {
      inputs.add(
          await File('${dir.path}/${entry.key}').writeAsBytes(entry.value));
    }
    await expectLater(
        store.importFiles(inputs.take(2).toList()), throwsFormatException);
    expect(await store.available(), isFalse);
    await store.importFiles(inputs);
    await store.verify();
    expect(await store.available(), isTrue);
    await store.deleteDownloaded();
    expect(await File('${dir.path}/installed/rec.yml').exists(), isFalse);
    expect(await inputs.last.exists(), isTrue);
  });

  test('both sources restrict redirect origins and require HTTPS', () {
    for (final source in OcrDownloadSource.values) {
      for (final url in [
        'http://huggingface.co/a',
        'https://evil.test/a',
        'https://huggingface.co.evil.test/a',
        'https://user@hf.co/a',
        'https://hf.co:444/a',
        'https://gitee.com/other/model/a'
      ]) {
        expect(
            OcrModelStore.allowedDownloadUri(Uri.parse(url), source), isFalse);
      }
    }
    expect(
        OcrModelStore.allowedDownloadUri(
            Uri.parse('https://foruda.gitee.com/attach_file/a'),
            OcrDownloadSource.gitee),
        isTrue);
    expect(
        OcrModelStore.allowedDownloadUri(
            Uri.parse('https://foruda.gitee.com/other/a'),
            OcrDownloadSource.gitee),
        isFalse);
  });

  test('verified files reused across sources without requests', () async {
    final adapter = Adapter((_) => ResponseBody.fromBytes(data, 200));
    final store = create(adapter);
    addTearDown(store.close);
    await store.download(CancelToken(), (_, __) {});
    await store.verify();
    expect(adapter.requests.length, 2);
    store.downloadSource = OcrDownloadSource.gitee;
    await store.download(CancelToken(), (_, __) {});
    expect(adapter.requests.length, 2);
    expect(await store.available(), isTrue);
  });

  test('wrong digest fails and removes partial file', () async {
    final store =
        create(Adapter((_) => ResponseBody.fromBytes([0, 0, 0, 0], 200)));
    addTearDown(store.close);
    await expectLater(
        store.download(CancelToken(), (_, __) {}), throwsFormatException);
    expect(await dir.list().toList(), isEmpty);
    expect(await store.available(), isFalse);
  });

  test('untrusted redirect cannot be fetched', () async {
    final adapter = Adapter((_) => ResponseBody.fromString('', 302, headers: {
          'location': ['https://evil.test/model']
        }));
    final store = create(adapter);
    addTearDown(store.close);
    await expectLater(
        store.download(CancelToken(), (_, __) {}), throwsFormatException);
    expect(adapter.requests.length, 1);
    expect(await dir.list().toList(), isEmpty);
  });

  test('allowed redirect chain reaches verified model', () async {
    final adapter = Adapter((request) => request.uri.host == 'huggingface.co'
        ? ResponseBody.fromString('', 302, headers: {
            'location': ['https://cdn.hf.co/model']
          })
        : ResponseBody.fromBytes(data, 200));
    final store = create(adapter);
    addTearDown(store.close);
    await store.download(CancelToken(), (_, __) {});
    await store.verify();
    expect(adapter.requests.length, 4);
  });

  test('cancel before download makes no request and permits retry', () async {
    final adapter = Adapter((_) => ResponseBody.fromBytes(data, 200));
    final store = create(adapter);
    addTearDown(store.close);
    await expectLater(store.download(CancelToken()..cancel(), (_, __) {}),
        throwsA(isA<DioException>()));
    expect(adapter.requests, isEmpty);
    await store.download(CancelToken(), (_, __) {});
    expect(await store.available(), isTrue);
  });
}
