import 'dart:io';
import 'dart:convert';

import 'package:modu_reader/service/tts/edge_tts_backend.dart';
import 'package:modu_reader/service/tts/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Edge reading cache accepts const config without mutating it', () {
    final provider = EdgeTtsProvider();
    final before = Map<String, dynamic>.from(provider.getConfig());
    expect(jsonDecode(provider.cacheConfiguration()), before);
    expect(provider.getConfig(), before);
    expect(provider.synthesisTimeout, const Duration(seconds: 60));
  });
  test('generates the current Edge time-bound token format', () {
    expect(
      EdgeTtsClient.generateSecMsGec(
        now: DateTime.utc(2025, 1, 1),
      ),
      '54404AFE67C9B44A-E72E51D8B4F5F75E9A96B7E20D7877227455BC310433BD30C817CD54A1D9313E',
    );
  });

  // Independent expected values from edge-tts 7.3.0 generate_sec_ms_gec_v2.
  test('v2 token matches upstream vectors including dates after 2038', () {
    final vectors = {
      DateTime.utc(2026, 10, 15):
          'F3FD83535256D08E-CF2FA3106FF93AB92502C05F6EF45B92187ED35987A62A77464E342750F61216',
      DateTime.utc(2026, 10, 15, 0, 5):
          'BC7569B4AA9A3A86-5299C23F1D621C77C10E9D7C28D5798AD7EBFFF02E6EC21899E3774660824207',
      DateTime.utc(2040):
          '2CFC54CBD2FE13D1-EE7F9D639CE5B91702482E38BC8A74B625D862C6F376E8BF33B9EF5E55D4FC8E',
    };
    for (final entry in vectors.entries) {
      expect(EdgeTtsClient.generateSecMsGec(now: entry.key), entry.value);
    }
  });

  test('token window boundaries and clock correction remain stable', () {
    final start = DateTime.utc(2026, 10, 15);
    final token = EdgeTtsClient.generateSecMsGec(now: start);
    expect(
        EdgeTtsClient.generateSecMsGec(
          now: start.add(const Duration(minutes: 5, microseconds: -1)),
        ),
        token);
    expect(
        EdgeTtsClient.generateSecMsGec(
          now: start.add(const Duration(minutes: 5)),
        ),
        isNot(token));
    expect(
        EdgeTtsClient.generateSecMsGec(
          now: start.add(const Duration(hours: 1)),
          clockSkewSeconds: -3600,
        ),
        token);
    expect(
        EdgeTtsClient.generateSecMsGec(
          now: start.subtract(const Duration(hours: 1)),
          clockSkewSeconds: 3600,
        ),
        token);
  });

  test('voice list uses v2 and retries once with server clock', () async {
    var calls = 0;
    final serverTime = DateTime.utc(2025, 1, 1, 0, 2);
    final client = EdgeTtsClient(httpClient: MockClient((request) async {
      calls++;
      expect(
          request.url.queryParameters['Sec-MS-GEC-Version'], '2-143.0.3650.75');
      expect(request.url.queryParameters['Sec-MS-GEC'],
          matches(RegExp(r'^[A-F0-9]{16}-[A-F0-9]{64}$')));
      if (calls == 1) {
        return http.Response('', 403,
            headers: {'date': HttpDate.format(serverTime)});
      }
      expect(request.url.queryParameters['Sec-MS-GEC'],
          EdgeTtsClient.generateSecMsGec(now: serverTime));
      return http.Response('[{"ShortName":"zh-CN-XiaoxiaoNeural"}]', 200);
    }));
    addTearDown(client.close);
    expect((await client.getVoices()).single.shortName, 'zh-CN-XiaoxiaoNeural');
    expect(calls, 2);
  });

  for (final status in [403, 429, 500]) {
    test('voice failures remain bounded for HTTP $status', () async {
      var calls = 0;
      final client = EdgeTtsClient(httpClient: MockClient((request) async {
        calls++;
        return http.Response('', status,
            headers: {'date': HttpDate.format(DateTime.now().toUtc())});
      }));
      addTearDown(client.close);
      await expectLater(client.getVoices(), throwsA(isA<HttpException>()));
      expect(calls, status == 403 ? 2 : 1);
    });
  }

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
      for (final name in ['zh-CN-XiaoxiaoNeural', 'zh-CN-YunxiNeural']) {
        final voice = voices.firstWhere((item) => item.shortName == name);
        final audio = await client.synthesize(
          '默读 Edge 语音测试。',
          voice: voice.shortName,
        );
        expect(audio.length, greaterThan(1000), reason: name);
        final startsWithId3 = audio.length >= 3 &&
            audio[0] == 0x49 &&
            audio[1] == 0x44 &&
            audio[2] == 0x33;
        final startsWithMp3Frame =
            audio.length >= 2 && audio[0] == 0xff && (audio[1] & 0xe0) == 0xe0;
        expect(startsWithId3 || startsWithMp3Frame, isTrue, reason: name);
      }
    },
    skip: runLiveTest ? false : '需要显式启用 Edge TTS 网络验证',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
