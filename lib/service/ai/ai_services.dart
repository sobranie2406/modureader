import 'package:anx_reader/utils/env_var.dart';

class AiServiceOption {
  const AiServiceOption({
    required this.identifier,
    required this.title,
    required this.logo,
    required this.defaultUrl,
    required this.defaultApiKey,
    required this.defaultModel,
  });

  final String identifier;
  final String title;
  final String logo;
  final String defaultUrl;
  final String defaultApiKey;
  final String defaultModel;
}

List<AiServiceOption> buildDefaultAiServices() {
  return [
    !EnvVar.enableOpenAiConfig
        ? AiServiceOption(
            identifier: 'openai',
            title: '通用',
            logo: 'assets/images/commonAi.png',
            defaultUrl:
                'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
            defaultApiKey: 'YOUR_API_KEY',
            defaultModel: 'qwen-long',
          )
        : AiServiceOption(
            identifier: 'openai',
            title: 'OpenAI',
            logo: 'assets/images/openai.png',
            defaultUrl: 'https://api.openai.com/v1/chat/completions',
            defaultApiKey: 'YOUR_API_KEY',
            defaultModel: 'gpt-4o-mini',
          ),
    AiServiceOption(
      identifier: 'claude',
      title: 'Claude',
      logo: 'assets/images/claude.png',
      defaultUrl: 'https://api.anthropic.com/v1/messages',
      defaultApiKey: 'YOUR_API_KEY',
      defaultModel: 'claude-sonnet-4-6',
    ),
    AiServiceOption(
      identifier: 'gemini',
      title: 'Gemini',
      logo: 'assets/images/gemini.png',
      defaultUrl: 'https://generativelanguage.googleapis.com',
      defaultApiKey: 'YOUR_API_KEY',
      defaultModel: 'gemini-2.5-flash',
    ),
    AiServiceOption(
      identifier: 'deepseek',
      title: 'DeepSeek',
      logo: 'assets/images/deepseek.png',
      defaultUrl: 'https://api.deepseek.com/v1/chat/completions',
      defaultApiKey: 'YOUR_API_KEY',
      defaultModel: 'deepseek-v4-flash',
    ),
    AiServiceOption(
      identifier: 'glm',
      title: '智谱 GLM',
      logo: 'assets/images/commonAi.png',
      defaultUrl: 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
      defaultApiKey: 'YOUR_API_KEY',
      defaultModel: 'glm-5.2',
    ),
    AiServiceOption(
      identifier: 'openrouter',
      title: 'OpenRouter',
      logo: 'assets/images/openrouter.png',
      defaultUrl: 'https://openrouter.ai/api/v1/chat/completions',
      defaultApiKey: 'YOUR_API_KEY',
      defaultModel: 'openai/gpt-4o-mini',
    ),
  ];
}
