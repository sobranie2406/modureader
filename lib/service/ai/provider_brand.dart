import 'package:anx_reader/models/ai_provider.dart';

/// Official website artwork bundled locally; never request icons with API keys.
enum ProviderBrand {
  openai,
  claude,
  gemini,
  deepseek,
  glm,
  openrouter,
  minimax,
  kimi,
  qwen,
  mimo,
  doubao,
  grok,
  siliconflow;

  String get asset => 'assets/images/providers/$name.png';
}

const _brandDomains = {
  ProviderBrand.openai: ['openai.com', 'chatgpt.com'],
  ProviderBrand.claude: ['anthropic.com', 'claude.ai', 'claude.com'],
  ProviderBrand.gemini: [
    'generativelanguage.googleapis.com',
    'gemini.google.com'
  ],
  ProviderBrand.deepseek: ['deepseek.com'],
  ProviderBrand.glm: ['bigmodel.cn', 'z.ai'],
  ProviderBrand.openrouter: ['openrouter.ai'],
  ProviderBrand.minimax: ['minimaxi.com', 'minimax.io', 'minimax.chat'],
  ProviderBrand.kimi: ['moonshot.cn', 'moonshot.ai', 'kimi.com'],
  ProviderBrand.qwen: [
    'dashscope.aliyuncs.com',
    'dashscope-intl.aliyuncs.com',
    'qwen.ai'
  ],
  ProviderBrand.siliconflow: ['siliconflow.cn', 'siliconflow.com'],
  ProviderBrand.mimo: ['xiaomimimo.com'],
  ProviderBrand.doubao: ['doubao.com'],
  ProviderBrand.grok: ['x.ai', 'grok.com'],
};

const _brandNames = {
  ProviderBrand.openai: ['openai', 'chatgpt'],
  ProviderBrand.claude: ['claude', 'anthropic'],
  ProviderBrand.gemini: ['gemini'],
  ProviderBrand.deepseek: ['deepseek', '深度求索'],
  ProviderBrand.glm: ['glm', 'z.ai', '智谱', '智谱清言'],
  ProviderBrand.openrouter: ['openrouter'],
  ProviderBrand.minimax: ['minimax', '稀宇'],
  ProviderBrand.kimi: ['kimi', 'moonshot', '月之暗面'],
  ProviderBrand.qwen: ['qwen', '通义千问', '千问', '百炼', 'dashscope'],
  ProviderBrand.siliconflow: ['siliconflow', '硅基流动'],
  ProviderBrand.mimo: ['mimo', '小米'],
  ProviderBrand.doubao: ['doubao', '豆包'],
  ProviderBrand.grok: ['grok', 'xai', 'x.ai'],
};

/// Includes imported/custom providers. Prefer the actual service's host (so an
/// aggregator does not acquire the logo of whichever model it happens to run).
/// For proxies, use an explicit brand name, then a recognized model family.
/// Protocol alone is NOT brand identity: OpenAI-compatible is not OpenAI.
ProviderBrand? resolveProviderBrand(AiProvider provider) {
  final host = Uri.tryParse(provider.url.trim())?.host.toLowerCase() ?? '';
  for (final entry in _brandDomains.entries) {
    if (entry.value
        .any((domain) => host == domain || host.endsWith('.$domain'))) {
      return entry.key;
    }
  }
  final title = provider.title.trim().toLowerCase().replaceAll(
        RegExp(r'openai[\s-]*(?:compatible|兼容|协议)'),
        '',
      );
  ProviderBrand? namedBrand;
  var firstMatch = title.length + 1;
  for (final entry in _brandNames.entries) {
    for (final name in entry.value) {
      final match = RegExp(
        '(^|[^a-z0-9])${RegExp.escape(name)}([^a-z0-9]|\$)',
      ).firstMatch(title);
      if (match != null && match.start < firstMatch) {
        firstMatch = match.start;
        namedBrand = entry.key;
      }
    }
  }
  if (namedBrand != null) return namedBrand;
  final model = provider.model.toLowerCase().split('/').last;
  for (final entry in <ProviderBrand, String>{
    ProviderBrand.openai: r'^(gpt-\d|chatgpt-|o[134](?:-|$))',
    ProviderBrand.claude: r'^claude(?:-|$)',
    ProviderBrand.gemini: r'^gemini(?:-|$)',
    ProviderBrand.deepseek: r'^deepseek(?:-|$)',
    ProviderBrand.glm: r'^glm(?:-|$)',
    ProviderBrand.minimax: r'^minimax(?:-|$)',
    ProviderBrand.kimi: r'^(kimi|moonshot)(?:-|$)',
    ProviderBrand.qwen: r'^(qwen(?:\d|[.-]|$)|qwq(?:-|$))',
    ProviderBrand.mimo: r'^mimo(?:-|$)',
    ProviderBrand.doubao: r'^doubao(?:-|$)',
    ProviderBrand.grok: r'^grok(?:-|$)',
  }.entries) {
    if (RegExp(entry.value).hasMatch(model)) return entry.key;
  }
  return null;
}
