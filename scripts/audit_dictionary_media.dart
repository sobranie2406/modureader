// Original synthetic media only; no user dictionary data or app database.
// Run with `dart run scripts/audit_dictionary_media.dart`, then open printed URL.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:anx_reader/service/dictionary/dictionary_document.dart';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';

class MediaFixtureStore extends LocalDictionaryStore {
  MediaFixtureStore() : super('unused');
  @override
  Future<Uint8List?> resource(String id, String name) async => switch (name) {
        'pixel.png' => base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j4qkAAAAASUVORK5CYII='),
        'main.js' => Uint8List.fromList(utf8.encode(
            'document.getElementById("dynamic").textContent="脚本生成释义成功";')),
        'main.css' =>
          Uint8List.fromList(utf8.encode('h1{color:rgb(20,80,160)}')),
        'voice.wav' => tone(),
        _ => null,
      };
}

Uint8List tone() {
  const samples = 16000;
  final bytes = Uint8List(44 + samples * 2);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  data.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 16, ascii.encode('WAVEfmt '));
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, ascii.encode('data'));
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(44 + i * 2, (2000 * sin(i * 2 * pi * 440 / 16000)).round(),
        Endian.little);
  }
  return bytes;
}

Future<void> main() async {
  final document = await DictionaryDocument.open(
      MediaFixtureStore(),
      const DictionaryEntry('Synthetic dictionary', 'demo', '示例',
          dictionaryId: 'test', html: '''
      <link rel="stylesheet" href="main.css">
      <h1>词典图文音频测试</h1><p id="dynamic">等待脚本</p>
      <img alt="本地图片" width="100" height="100" src="pixel.png">
      <a href="sound://voice.wav">播放测试音频</a>
      <button onclick="document.querySelector('audio').play()">播放</button>
      <script src="main.js"></script>
    '''));
  stdout.writeln(document.uri);
  final done = Completer<void>();
  final subscription =
      ProcessSignal.sigint.watch().listen((_) => done.complete());
  await done.future;
  await subscription.cancel();
  await document.close();
}
