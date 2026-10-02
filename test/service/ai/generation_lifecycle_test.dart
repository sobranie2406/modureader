import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/ai/coalesced_stream.dart';
import 'package:anx_reader/service/ai/index.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'normal API completion is not user cancellation and keeps the final snapshot',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final runner = CancelableLangchainRunner();
    const provider = AiProvider(
        id: 'fixture',
        title: 'Fixture',
        url: 'https://example.test/v1',
        protocol: AiProtocol.openai,
        model: 'fixture',
        apiKeys: [AiApiKey(id: 'fixture', key: 'not-a-real-key')]);
    String event(String text) => 'data: ${jsonEncode({
              'id': 'fixture',
              'object': 'chat.completion.chunk',
              'created': 1,
              'model': 'fixture',
              'choices': [
                {
                  'index': 0,
                  'delta': {'content': text},
                  'finish_reason': null
                }
              ],
            })}\n\n';
    final received = await http.runWithClient(() async {
      final visible = <String>[];
      await for (final snapshot in coalesceSnapshots(aiGenerateStream(
        [ChatMessage.humanText('你好')],
        providerOverride: provider,
        requestRunner: runner,
      ))) {
        // This is the same guard used by AiChat before updating/saving replies.
        if (runner.isCancelled) break;
        visible.add(snapshot);
      }
      return visible;
    },
        () => MockClient((_) async => http.Response(
              '${event('后来泛指所有')}${event('房屋或房间。')}data: [DONE]\n\n',
              200,
              headers: {'content-type': 'text/event-stream; charset=utf-8'},
            )));
    expect(runner.isCancelled, isFalse);
    expect(received.last, '后来泛指所有房屋或房间。');
  });

  test('stopping an unfinished API stream still cancels its request', () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final runner = CancelableLangchainRunner();
    final connected = Completer<void>();
    var transportCancelled = false;
    final bytes = StreamController<List<int>>(onCancel: () {
      transportCancelled = true;
    });
    const provider = AiProvider(
        id: 'fixture',
        title: 'Fixture',
        url: 'https://example.test/v1',
        protocol: AiProtocol.openai,
        model: 'fixture',
        apiKeys: [AiApiKey(id: 'fixture', key: 'not-a-real-key')]);
    await http.runWithClient(() async {
      final subscription = aiGenerateStream([ChatMessage.humanText('你好')],
              providerOverride: provider, requestRunner: runner)
          .listen((_) {});
      await connected.future.timeout(const Duration(seconds: 5));
      final cancellation = subscription.cancel();
      expect(runner.isCancelled, isTrue);
      // The mock transport has no socket to close; release its pending read.
      unawaited(bytes.close());
      await cancellation.timeout(const Duration(seconds: 5));
    },
        () => MockClient.streaming((_, __) async {
              connected.complete();
              return http.StreamedResponse(bytes.stream, 200,
                  headers: {'content-type': 'text/event-stream'});
            }));
    expect(runner.isCancelled, isTrue);
    expect(transportCancelled, isTrue);
    await bytes.close();
  });
}
