import 'package:anx_reader/providers/ai_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';

void main() {
  test(
      'new reader conversation resets session identity without touching library',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(aiChatProvider(AiChatScope.reader).future);
    await container.read(aiChatProvider(AiChatScope.library).future);
    final reader = container.read(aiChatProvider(AiChatScope.reader).notifier);
    reader
        .restore([ChatMessage.humanText('旧划词问题')], sessionId: 'old-selection');
    container
        .read(aiChatProvider(AiChatScope.library).notifier)
        .restore([ChatMessage.humanText('首页问题')], sessionId: 'home');
    reader.clear();
    expect(reader.currentSessionId, isNull);
    expect(container.read(aiChatProvider(AiChatScope.reader)).value, isEmpty);
    expect(
        container
            .read(aiChatProvider(AiChatScope.library))
            .value!
            .single
            .contentAsString,
        '首页问题');
  });
  test('home and reader conversations keep independent state and sessions',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiChatProvider(AiChatScope.library).future);
    await container.read(aiChatProvider(AiChatScope.reader).future);

    container.read(aiChatProvider(AiChatScope.library).notifier).restore(
      [ChatMessage.humanText('首页问题')],
      sessionId: 'library-session',
    );

    expect(
      container
          .read(aiChatProvider(AiChatScope.library))
          .value!
          .single
          .contentAsString,
      '首页问题',
    );
    expect(container.read(aiChatProvider(AiChatScope.reader)).value, isEmpty);
    expect(
      container
          .read(aiChatProvider(AiChatScope.library).notifier)
          .currentSessionId,
      'library-session',
    );
    expect(
      container
          .read(aiChatProvider(AiChatScope.reader).notifier)
          .currentSessionId,
      isNull,
    );
  });
}
