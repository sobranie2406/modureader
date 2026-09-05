import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:anx_reader/service/book_player/reader_background_response.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

class OffsetImageBundle extends CachingAssetBundle {
  OffsetImageBundle(this.bytes);
  final Uint8List bytes;
  final loaded = <String>[];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final buffer = Uint8List(bytes.length + 24)
      ..fillRange(0, bytes.length + 24, 0xAC);
    buffer.setRange(8, 8 + bytes.length, bytes);
    return ByteData.view(buffer.buffer, 8, bytes.length);
  }
}

Future<Uint8List> body(Response response) async =>
    Uint8List.fromList(await response.read().expand((chunk) => chunk).toList());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async => directory =
      await Directory.systemTemp.createTemp('modu-background-test-'));
  tearDown(() async => directory.delete(recursive: true));

  for (var i = 1; i <= 6; i++) {
    test(
        'built-in background $i preserves offset asset bytes and decodes as JPEG',
        () async {
      final image = await File('assets/images/bgimg/bg$i.jpg').readAsBytes();
      final bundle = OffsetImageBundle(image);
      // Reproduce the old response: it included bytes before/after the asset.
      final data = await bundle.load('fixture');
      expect(data.offsetInBytes, 8);
      expect(data.buffer.asUint8List(), isNot(orderedEquals(image)));

      final response = await readerBackgroundResponse(
        Uri.parse(
            'http://127.0.0.1:1234/bgimg/assets/assets/images/bgimg/bg$i.jpg'),
        directory: directory,
        assets: bundle,
      );
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'image/jpeg');
      expect(response.headers['cache-control'], 'no-store');
      final received = await body(response);
      expect(received, orderedEquals(image));
      final codec = await ui.instantiateImageCodec(received);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(0));
      frame.image.dispose();
      codec.dispose();
    });
  }

  test(
      'local filename is decoded once, with correct MIME and fresh replacement bytes',
      () async {
    final bundle = OffsetImageBundle(Uint8List(0));
    const filename = "书 背景 #100% (day)'s.png";
    final file =
        await File('${directory.path}/$filename').writeAsBytes([1, 2, 3]);
    final uri = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        pathSegments: ['bgimg', 'local', filename]);
    var response = await readerBackgroundResponse(uri,
        directory: directory, assets: bundle);
    expect(response.statusCode, 200);
    expect(response.headers['content-type'], 'image/png');
    expect(await body(response), [1, 2, 3]);
    await file.writeAsBytes([4, 5, 6]);
    response = await readerBackgroundResponse(uri,
        directory: directory, assets: bundle);
    expect(response.headers['cache-control'], 'no-store');
    expect(await body(response), [4, 5, 6]);
    expect(bundle.loaded, isEmpty);
  });

  test('imported PNG night image with a JPG filename uses its actual encoding',
      () async {
    final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jXioAAAAASUVORK5CYII=');
    await File('${directory.path}/day_night.jpg').writeAsBytes(png);
    final response = await readerBackgroundResponse(
        Uri.parse('http://127.0.0.1/bgimg/local/day_night.jpg'),
        directory: directory,
        assets: rootBundle);
    expect(response.headers['content-type'], 'image/png');
    expect(await body(response), orderedEquals(png));
  });

  test(
      'missing, unsupported and escaping paths return 404 without reading arbitrary assets',
      () async {
    final bundle = OffsetImageBundle(Uint8List(0));
    for (final route in [
      '/bgimg/local/missing.jpg',
      '/bgimg/local/key.json',
      '/bgimg/local/%2E%2E%2Fprivate.png',
      '/bgimg/local/%5Cprivate.png',
      '/bgimg/assets/pubspec.yaml',
      '/bgimg/assets/assets/other/private.png',
      '/bgimg/assets/assets/images/bgimg/%2E%2E/private.png',
    ]) {
      final response = await readerBackgroundResponse(
          Uri.parse('http://127.0.0.1$route'),
          directory: directory,
          assets: bundle);
      expect(response.statusCode, 404, reason: route);
    }
    expect(bundle.loaded, isEmpty);
  });

  test(
      'missing bundled background returns 404 rather than an uncaught asset error',
      () async {
    final response = await readerBackgroundResponse(
        Uri.parse(
            'http://127.0.0.1/bgimg/assets/assets/images/bgimg/missing.jpg'),
        directory: directory,
        assets: rootBundle);
    expect(response.statusCode, 404);
  });
}
