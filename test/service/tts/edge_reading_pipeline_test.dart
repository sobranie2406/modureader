import 'dart:typed_data';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/edge_tts_backend.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StubEdge extends Fake implements TtsServiceProvider {
  final edge = EdgeTtsProvider();
  final requests = <String>[];
  @override
  String get serviceId => 'edge-regression';
  @override
  Duration get synthesisTimeout => edge.synthesisTimeout;
  @override
  String getSelectedVoice() => 'zh-CN-XiaoxiaoNeural';
  @override
  Map<String, dynamic> getConfig() => edge.getConfig();
  @override
  String cacheConfiguration() => edge.cacheConfiguration();
  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    requests.add(text);
    expect(voice, 'zh-CN-XiaoxiaoNeural');
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'reading traverses cache configuration and reaches Edge synthesis/playback',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final provider = StubEdge();
    final played = <String>[];
    final tts = OnlineTts.forTesting(
      collect: (_) async => [const TtsSentence(text: '正文合成回归测试。')],
      backend: provider,
      play: (segment) async => played.add(segment.sentence.text),
    );
    await tts.init(() async => '正文合成回归测试。', () async => '', () async => '');
    await tts.speak();
    expect(provider.requests, ['正文合成回归测试。']);
    expect(played, ['正文合成回归测试。']);
    expect(tts.playbackError, isNull);
    await tts.stop();
  });
}
