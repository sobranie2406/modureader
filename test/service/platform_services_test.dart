import 'package:anx_reader/service/ai/ai_provider.dart';
import 'package:anx_reader/service/sync/sync_merge.dart';
import 'package:anx_reader/service/local_data/local_data_store.dart';
import 'package:anx_reader/service/tts/tts_pipeline.dart';
import 'package:anx_reader/service/tts/tts_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AI provider configuration redacts its secret', () {
    const config = AiProviderConfig(
      id: 'glm',
      name: '智谱 GLM',
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4/',
      modelId: 'glm-5.2',
      apiKey: 'secret',
    );

    expect(config.toSafeMap()['apiKey'], '***');
    expect(config.toSafeMap()['modelId'], 'glm-5.2');
  });

  test('TTS pipeline splits sentences and advances its cursor', () {
    final pipeline = TtsPipeline('第一句。第二句！第三句？');

    expect(pipeline.sentences, ['第一句。', '第二句！', '第三句？']);
    expect(pipeline.current, '第一句。');
    expect(pipeline.next(), '第二句！');
    expect(pipeline.next(), '第三句？');
    expect(pipeline.next(), isNull);
  });

  test('TTS playback controller resumes from a stable reader location',
      () async {
    final firstLocation =
        const ReaderLocation(bookId: 'book-1', chapterId: 'chapter-1');
    final spoken = <String>[];
    final controller = TtsPlaybackController(
      items: [
        TtsPlaybackItem(location: firstLocation, text: '第一句。'),
        TtsPlaybackItem(
          location: const ReaderLocation(
            bookId: 'book-1',
            chapterId: 'chapter-1',
            textOffset: 4,
          ),
          text: '第二句。',
        ),
      ],
      speak: (item) async {
        spoken.add(item.text);
      },
    );

    await controller.playFrom(firstLocation);

    expect(spoken, ['第一句。', '第二句。']);
    expect(controller.status, TtsPlaybackStatus.completed);
    expect(controller.current?.text, '第二句。');
  });

  test('TTS cache keys request parameters and evicts least recently used',
      () async {
    final cache = TtsCache(maxEntries: 2);
    var syntheses = 0;
    final provider = _FakeTtsProvider(() async {
      syntheses++;
      return const TtsAudioChunk(bytes: [1, 2, 3], mimeType: 'audio/wav');
    });
    const request = TtsRequest(
      text: '你好。',
      voice: 'female-1',
      model: 'demo',
      parameters: {'rate': '1.0'},
    );

    await cache.synthesize(provider, request);
    await cache.synthesize(provider, request);
    expect(syntheses, 1);
    await cache.synthesize(
      provider,
      const TtsRequest(text: '第二句。', voice: 'female-1', model: 'demo'),
    );
    await cache.synthesize(
      provider,
      const TtsRequest(text: '第三句。', voice: 'female-1', model: 'demo'),
    );
    await cache.synthesize(provider, request);
    expect(syntheses, 4);
  });

  test('sync merge keeps the newest progress and records conflicts', () {
    final merger = SyncMerger();
    final local = SyncRecord(
      id: 'progress:book-1',
      value: 'local-cfi',
      updatedAt: DateTime(2026, 1, 2),
      deviceId: 'mac',
    );
    final remote = SyncRecord(
      id: 'progress:book-1',
      value: 'remote-cfi',
      updatedAt: DateTime(2026, 1, 1),
      deviceId: 'android',
    );

    final result = merger.merge(local, remote);

    expect(result.winner.value, 'local-cfi');
    expect(result.conflict, isNotNull);
  });
}

class _FakeTtsProvider implements TtsProvider {
  _FakeTtsProvider(this._synthesize);

  final Future<TtsAudioChunk> Function() _synthesize;

  @override
  Future<TtsAudioChunk> synthesize(TtsRequest request) => _synthesize();
}
