import 'dart:async';
import 'package:anx_reader/service/knowledge/embedding_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _SilentClient extends http.BaseClient {
  final response = Completer<http.StreamedResponse>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      response.future;
  @override
  void close() {
    closed = true;
    if (!response.isCompleted)
      response.completeError(StateError('transport closed'));
  }
}

void main() {
  const config = VectorModelConfig(endpoint: 'http://127.0.0.1:1');
  test('silent remote request times out and closes the transport', () async {
    final client = _SilentClient();
    final provider = OpenAiCompatibleEmbeddingProvider(
        config: config,
        client: client,
        requestTimeout: const Duration(milliseconds: 30));
    await expectLater(
        provider.embed('synthetic fixture'), throwsA(isA<TimeoutException>()));
    expect(client.closed, isTrue);
  });
  test('cancellation aborts a pending request without waiting for timeout',
      () async {
    final client = _SilentClient();
    final provider =
        OpenAiCompatibleEmbeddingProvider(config: config, client: client);
    var cancelled = false;
    final result = provider
        .embedBatchCancellable(['fixture'], isCancelled: () => cancelled);
    final check = expectLater(
        result.timeout(const Duration(seconds: 1)), throwsStateError);
    cancelled = true;
    await check;
    expect(client.closed, isTrue);
  });
}
