import 'dart:ui' as ui;

import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:anx_reader/service/ai/provider_brand.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

AiProvider custom({String url = '', String title = '', String model = ''}) =>
    AiProvider(
        id: 'imported-custom-id',
        title: title,
        url: url,
        model: model,
        protocol: AiProtocol.openai);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('custom and imported endpoints get official service identities', () {
    for (final entry in {
      'https://api.openai.com/v1': ProviderBrand.openai,
      'https://api.anthropic.com/v1': ProviderBrand.claude,
      'https://generativelanguage.googleapis.com/v1beta': ProviderBrand.gemini,
      'https://api.deepseek.com/v1': ProviderBrand.deepseek,
      'https://open.bigmodel.cn/api/paas/v4': ProviderBrand.glm,
      'https://openrouter.ai/api/v1': ProviderBrand.openrouter,
      'https://api.minimaxi.com/anthropic': ProviderBrand.minimax,
      'https://api.moonshot.cn/v1': ProviderBrand.kimi,
      'https://dashscope.aliyuncs.com/compatible-mode/v1': ProviderBrand.qwen,
      'https://api.siliconflow.cn/v1': ProviderBrand.siliconflow,
      'https://api.xiaomimimo.com/v1': ProviderBrand.mimo,
      'https://www.doubao.com/': ProviderBrand.doubao,
      'https://api.x.ai/v1': ProviderBrand.grok,
    }.entries) {
      expect(resolveProviderBrand(custom(url: entry.key)), entry.value,
          reason: entry.key);
    }
  });

  test('proxy endpoints resolve explicit names and model families', () {
    for (final entry in {
      '我的 MiniMax 接口': ProviderBrand.minimax,
      'Kimi': ProviderBrand.kimi,
      '智谱 GLM': ProviderBrand.glm,
      '通义千问': ProviderBrand.qwen,
      '硅基流动': ProviderBrand.siliconflow,
      'DeepSeek (OpenAI compatible)': ProviderBrand.deepseek,
    }.entries) {
      expect(
          resolveProviderBrand(
              custom(url: 'https://proxy.example/v1', title: entry.key)),
          entry.value);
    }
    for (final entry in {
      'openai/gpt-4o-mini': ProviderBrand.openai,
      'anthropic/claude-sonnet-4-6': ProviderBrand.claude,
      'google/gemini-2.5-flash': ProviderBrand.gemini,
      'deepseek-ai/DeepSeek-R1': ProviderBrand.deepseek,
      'z-ai/glm-5.2': ProviderBrand.glm,
      'MiniMax-M2.7': ProviderBrand.minimax,
      'kimi-k2.6': ProviderBrand.kimi,
      'Qwen/Qwen3.5-27B': ProviderBrand.qwen,
      'xiaomi/mimo-v2-flash': ProviderBrand.mimo,
      'doubao-seed-1-6': ProviderBrand.doubao,
      'grok-4': ProviderBrand.grok,
    }.entries) {
      expect(
          resolveProviderBrand(custom(
              url: 'https://proxy.example/v1',
              title: '自定义 OpenAI 兼容',
              model: entry.key)),
          entry.value);
    }
  });

  test('service host beats model name and stale saved logo', () {
    final provider = custom(
            url: 'https://api.siliconflow.cn/v1',
            title: 'DeepSeek',
            model: 'Qwen/Qwen3')
        .copyWith(logoAsset: 'assets/images/openai.png', isBuiltin: false);
    expect(resolveProviderBrand(provider), ProviderBrand.siliconflow);
    expect(
        resolveProviderBrand(
            provider.copyWith(url: 'https://api.minimaxi.com/v1')),
        ProviderBrand.minimax);
  });

  test('protocol, unknown models and lookalike domains do not invent a brand',
      () {
    for (final url in [
      'https://notopenai.com',
      'https://api.openai.com.attacker.test',
      'https://example.test/path/api.openai.com',
      'https://api.openai.com@example.test',
      'http://127.0.0.1:11434/v1',
      ''
    ]) {
      expect(
          resolveProviderBrand(custom(
              url: url, title: 'OpenAI compatible', model: 'my-local-model')),
          isNull);
    }
  });

  test('every official logo is bundled and decodes offline', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final brand in ProviderBrand.values) {
      expect(manifest.listAssets(), contains(brand.asset));
      final data = await rootBundle.load(brand.asset);
      final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThanOrEqualTo(32));
      expect(frame.image.height, greaterThanOrEqualTo(32));
      frame.image.dispose();
      codec.dispose();
    }
    for (final option in buildDefaultAiServices()) {
      expect(option.logo, startsWith('assets/images/providers/'));
      expect(manifest.listAssets(), contains(option.logo));
    }
  });
}
