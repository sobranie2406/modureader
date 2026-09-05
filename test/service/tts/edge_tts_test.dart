import 'dart:io';

import 'package:anx_reader/service/tts/edge_tts_backend.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('generates the current Edge time-bound token format', () {
    expect(
      EdgeTtsClient.generateSecMsGec(
        now: DateTime.utc(2025, 1, 1),
      ),
      'B0EDD22C7C09868E2F24C10264A8A3EB877773A7B6040B68AFA4FBCBABEA0238',
    );
  });

  test('TTS catalog excludes removed Azure and legacy Aliyun providers', () {
    final serviceIds = TtsService.values.map((service) => service.name);
    expect(
      serviceIds,
      ['system', 'edge', 'dashscope', 'xiaomi', 'openai'],
    );
    expect(getTtsService('azure'), TtsService.system);
    expect(getTtsService('aliyun'), TtsService.system);
  });

  final runLiveTest = Platform.environment['EDGE_TTS_LIVE_TEST'] == '1';
  test(
    'fetches Edge voices and synthesizes real MP3 audio',
    () async {
      final client = EdgeTtsClient();
      addTearDown(client.close);

      final voices = await client.getVoices();
      expect(voices, isNotEmpty);
      final voice = voices.firstWhere(
        (item) => item.shortName == 'zh-CN-XiaoxiaoNeural',
        orElse: () => voices.first,
      );

      final audio = await client.synthesize(
        '默读 Edge 语音测试。',
        voice: voice.shortName,
      );
      expect(audio.length, greaterThan(1000));
      final startsWithId3 = audio.length >= 3 &&
          audio[0] == 0x49 &&
          audio[1] == 0x44 &&
          audio[2] == 0x33;
      final startsWithMp3Frame =
          audio.length >= 2 && audio[0] == 0xff && (audio[1] & 0xe0) == 0xe0;
      expect(startsWithId3 || startsWithMp3Frame, isTrue);
    },
    skip: runLiveTest ? false : '需要显式启用 Edge TTS 网络验证',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
