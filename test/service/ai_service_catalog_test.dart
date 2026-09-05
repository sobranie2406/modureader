import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses current default model identifiers', () {
    final services = {
      for (final service in buildDefaultAiServices())
        service.identifier: service,
    };

    expect(services['claude']!.defaultModel, 'claude-sonnet-4-6');
    expect(services['deepseek']!.defaultModel, 'deepseek-v4-flash');
    expect(services['openrouter']!.defaultModel, 'openai/gpt-4o-mini');
  });

  test('includes a dedicated GLM provider preset', () {
    final glm = buildDefaultAiServices().firstWhere(
      (service) => service.identifier == 'glm',
    );

    expect(glm.title, '智谱 GLM');
    expect(glm.defaultUrl,
        'https://open.bigmodel.cn/api/paas/v4/chat/completions');
    expect(glm.defaultModel, 'glm-5.2');
  });
}
