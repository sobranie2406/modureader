import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/service/config_transfer/config_qr_bridge.dart';
import 'package:anx_reader/service/config_transfer/config_transfer_codec.dart';
import 'package:anx_reader/service/config_transfer/library_config_transfer.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  const connection = LibraryConnection(
      url: 'https://example.com/书库/',
      username: '读者',
      password: 'secret-with-汉字&:?');

  test('library tokens round trip with explicitly included credentials', () {
    final decoded = ConfigTransferCodec.decode(ConfigTransferCodec.encode(
        kind: LibraryConfigTransfer.kind,
        data: LibraryConfigTransfer.createPayload(connection,
            includePassword: true)));
    expect(decoded.kind, LibraryConfigTransfer.kind);
    final restored = LibraryConfigTransfer.parse(decoded.data);
    expect(restored.url, connection.url);
    expect(restored.username, connection.username);
    expect(restored.password, connection.password);
    expect(restored.allowHttp, false);
  });

  test('password included by default and can be explicitly omitted', () {
    expect(LibraryConfigTransfer.createPayload(connection)['password'],
        connection.password);
    final data =
        LibraryConfigTransfer.createPayload(connection, includePassword: false);
    expect(data.containsKey('password'), false);
    expect(LibraryConfigTransfer.parse(data).password, '');
  });

  test('reject wrong type, unsafe URLs and invalid field types', () {
    final valid = LibraryConfigTransfer.createPayload(connection);
    for (final invalid in [
      {...valid, 'type': 'webdav'},
      {...valid, 'url': 'http://example.com/'},
      {...valid, 'url': 'https://user:secret@example.com/'},
      {...valid, 'url': 'https://example.com/?token=secret'},
      {...valid, 'url': 'https://example.com/%2f/'},
      {...valid, 'allowHttp': 'true'},
      {...valid, 'username': 42},
      {
        ...valid,
        'password': ['secret']
      },
    ]) {
      expect(() => LibraryConfigTransfer.parse(invalid), throwsFormatException);
    }
    expect(
        LibraryConfigTransfer.parse({
          ...valid,
          'url': 'http://example.com/books/',
          'allowHttp': true
        }).allowHttp,
        true);
  });

  test('portable QR round trip from PNG and screenshot JPEG', () async {
    final directory = await Directory.systemTemp.createTemp('modu-qr-test-');
    addTearDown(() => directory.delete(recursive: true));
    final token = ConfigTransferCodec.encode(
        kind: LibraryConfigTransfer.kind,
        data: LibraryConfigTransfer.createPayload(connection,
            includePassword: true));
    final bytes = (await ConfigQrBridge.generate(token))!;
    final png = File('${directory.path}/config.png');
    await png.writeAsBytes(bytes);
    expect(await ConfigQrBridge.decodeImage(png.path), token);
    final qr = img.decodePng(bytes)!;
    final screenshot =
        img.Image(width: qr.width + 150, height: qr.height + 300);
    img.fill(screenshot, color: img.ColorRgb8(245, 240, 230));
    img.compositeImage(screenshot, qr, dstX: 75, dstY: 150);
    final jpeg = File('${directory.path}/screenshot.jpg');
    await jpeg.writeAsBytes(img.encodeJpg(screenshot, quality: 90));
    expect(await ConfigQrBridge.decodeImage(jpeg.path), token);
  });

  test('QR rejects bad files and oversized tokens, blank image returns null',
      () async {
    final directory = await Directory.systemTemp.createTemp('modu-qr-invalid-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/invalid.png');
    await file.writeAsBytes(Uint8List.fromList([1, 2, 3]));
    await expectLater(
        ConfigQrBridge.decodeImage(file.path), throwsFormatException);
    final blank = img.Image(width: 100, height: 100);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    await file.writeAsBytes(img.encodePng(blank));
    expect(await ConfigQrBridge.decodeImage(file.path), isNull);
    await expectLater(
        ConfigQrBridge.generate('x' * 3000), throwsFormatException);
  });
}
